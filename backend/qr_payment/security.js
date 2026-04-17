const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const path = require('path');

// Security constants
const BCRYPT_ROUNDS = 12;
const JWT_EXPIRY = '1h';
const JWT_REFRESH_EXPIRY = '7d';

// Persist JWT_SECRET and QR_SECRET to file to survive restarts
const SECRET_FILE = path.join(__dirname, '.secrets.json');

function loadOrGenerateSecrets() {
  try {
    if (fs.existsSync(SECRET_FILE)) {
      const secrets = JSON.parse(fs.readFileSync(SECRET_FILE, 'utf8'));
      return {
        JWT_SECRET: secrets.JWT_SECRET,
        QR_SECRET: secrets.QR_SECRET
      };
    }
  } catch (err) {
    console.error('Error loading secrets file:', err.message);
  }

  // Generate new secrets
  const newSecrets = {
    JWT_SECRET: crypto.randomBytes(64).toString('hex'),
    QR_SECRET: crypto.randomBytes(32).toString('hex')
  };

  try {
    fs.writeFileSync(SECRET_FILE, JSON.stringify(newSecrets, null, 2));
    console.log('Generated new security secrets ( persisted to .secrets.json)');
  } catch (err) {
    console.error('Error writing secrets file:', err.message);
  }

  return newSecrets;
}

const { JWT_SECRET, QR_SECRET } = loadOrGenerateSecrets();
console.log('Security module loaded. JWT_SECRET available:', !!JWT_SECRET, 'QR_SECRET available:', !!QR_SECRET);

// ==================== PASSWORD HASHING ====================

/**
 * Hash a password using bcrypt
 */
async function hashPassword(password) {
  return bcrypt.hash(password, BCRYPT_ROUNDS);
}

/**
 * Verify a password against a hash
 */
async function verifyPassword(password, hash) {
  return bcrypt.compare(password, hash);
}

// ==================== JWT AUTH ====================

/**
 * Generate JWT access token
 */
function generateAccessToken(userId, role) {
  return jwt.sign(
    { userId, role, type: 'access' },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRY, issuer: 'qr_payment' }
  );
}

/**
 * Generate JWT refresh token
 */
function generateRefreshToken(userId) {
  return jwt.sign(
    { userId, type: 'refresh' },
    JWT_SECRET,
    { expiresIn: JWT_REFRESH_EXPIRY, issuer: 'qr_payment' }
  );
}

/**
 * Verify JWT token
 */
function verifyToken(token) {
  try {
    const decoded = jwt.verify(token, JWT_SECRET, { issuer: 'qr_payment' });
    return { valid: true, decoded };
  } catch (err) {
    return { valid: false, error: err.message };
  }
}

/**
 * Extract user ID from token (without verification - for logging)
 */
function extractUserIdFromToken(authHeader) {
  if (!authHeader) return null;
  try {
    // For Bearer tokens
    const token = authHeader.replace(/^Bearer\s+/i, '');
    const decoded = jwt.decode(token);
    return decoded?.userId || null;
  } catch {
    return null;
  }
}

// ==================== QR CODE SIGNING ====================

/**
 * Sign QR payload with HMAC-SHA256
 * Format: merchant_id:timestamp:signature
 */
function signQRPayload(merchantId, expiresInMinutes = 30) {
  const timestamp = Date.now();
  const expiry = timestamp + (expiresInMinutes * 60 * 1000);
  const payload = `${merchantId}:${expiry}`;
  const signature = crypto
    .createHmac('sha256', QR_SECRET)
    .update(payload)
    .digest('hex');

  return {
    merchantId,
    timestamp,
    expiry,
    signature,
    // Compact form for QR code storage
    compact: Buffer.from(`${merchantId}|${expiry}|${signature}`).toString('base64')
  };
}

/**
 * Verify QR payload signature
 */
function verifyQRPayload(merchantId, expiry, signature) {
  // Check if expired
  if (Date.now() > parseInt(expiry)) {
    return { valid: false, error: 'QR code has expired' };
  }

  const payload = `${merchantId}:${expiry}`;
  const expectedSignature = crypto
    .createHmac('sha256', QR_SECRET)
    .update(payload)
    .digest('hex');

  // Use timing-safe comparison
  if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expectedSignature))) {
    return { valid: false, error: 'Invalid QR signature' };
  }

  return { valid: true };
}

/**
 * Sign QR payload from compact form
 */
function verifyQRCompact(compact) {
  try {
    const decoded = Buffer.from(compact, 'base64').toString('utf8');
    const [merchantId, expiry, signature] = decoded.split('|');
    return verifyQRPayload(merchantId, expiry, signature);
  } catch {
    return { valid: false, error: 'Invalid QR format' };
  }
}

// ==================== TRANSACTION SIGNING ====================

/**
 * Generate idempotency key for preventing duplicate transactions
 */
function generateIdempotencyKey() {
  return crypto.randomBytes(16).toString('hex');
}

/**
 * Sign transaction data for integrity
 */
function signTransaction(transactionData) {
  const data = JSON.stringify(transactionData);
  const signature = crypto
    .createHash('sha256')
    .update(data)
    .digest('hex');
  return signature;
}

/**
 * Verify webhook signature from Paystack
 */
function verifyPaystackWebhook(payload, signature, secret) {
  const expectedSignature = crypto
    .createHash('sha512')
    .update(payload)
    .digest('hex');
  try {
    return crypto.timingSafeEqual(
      Buffer.from(signature || ''),
      Buffer.from(expectedSignature)
    );
  } catch {
    return false;
  }
}

// ==================== INPUT VALIDATION ====================

/**
 * Sanitize string input - prevent SQL injection, XSS
 */
function sanitizeString(str, maxLength = 255) {
  if (typeof str !== 'string') return '';
  return str
    .trim()
    .slice(0, maxLength)
    .replace(/[<>'"]/g, ''); // Remove potential XSS characters
}

/**
 * Validate email format
 */
function isValidEmail(email) {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

/**
 * Validate phone number (basic Nigerian format)
 */
function isValidPhone(phone) {
  const phoneRegex = /^(\+234|0)[789][01]\d{8}$/;
  return phoneRegex.test(phone.replace(/\s/g, ''));
}

/**
 * Validate amount (positive number with max 2 decimal places)
 */
function isValidAmount(amount) {
  if (typeof amount !== 'number' || isNaN(amount) || amount <= 0) return false;
  // Max 2 decimal places
  return /^\d+(\.\d{1,2})?$/.test(amount.toString());
}

// ==================== RATE LIMITING HELPERS ====================

/**
 * Generate rate limit key based on IP and user ID
 */
function getRateLimitKey(req, prefix = 'rl') {
  const ip = req.ip || req.connection.remoteAddress || 'unknown';
  const userId = extractUserIdFromToken(req.headers.authorization) || '';
  return `${prefix}:${ip}:${userId}`.slice(0, 100);
}

module.exports = {
  // Password
  hashPassword,
  verifyPassword,
  // JWT
  generateAccessToken,
  generateRefreshToken,
  verifyToken,
  extractUserIdFromToken,
  // QR
  signQRPayload,
  verifyQRPayload,
  verifyQRCompact,
  // Transaction
  generateIdempotencyKey,
  signTransaction,
  verifyPaystackWebhook,
  // Validation
  sanitizeString,
  isValidEmail,
  isValidPhone,
  isValidAmount,
  // Rate limiting
  getRateLimitKey,
  // Constants
  JWT_SECRET,
  QR_SECRET,
};
