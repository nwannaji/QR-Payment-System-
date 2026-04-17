require('dotenv').config();
const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const axios = require('axios');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const app = express();
const db = require('./db');
const { initializeDatabase } = require('./schema');
const { sendMoneyInSMS, sendMoneyOutSMS } = require('./services/sms_service');
const {
  hashPassword,
  verifyPassword,
  generateAccessToken,
  generateRefreshToken,
  verifyToken,
  signQRPayload,
  verifyQRPayload,
  verifyQRCompact,
  verifyPaystackWebhook,
  sanitizeString,
  isValidEmail,
  isValidPhone,
  isValidAmount,
  getRateLimitKey,
} = require('./security');

const PAYSTACK_SECRET_KEY = process.env.PAYSTACK_SECRET_KEY || 'sk_test_74ad39eaf08ed2a02ee8cde4c5ae06a121838f0a';
const PAYSTACK_PUBLIC_KEY = process.env.PAYSTACK_PUBLIC_KEY || 'pk_test_39ec080908b5b0a244d82c64744782d9cc4e51bf';
const PAYSTACK_BASE_URL = 'https://api.paystack.co';

// ==================== SECURITY MIDDLEWARE ====================

// Helmet for security headers
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
    },
  },
  hpp: true, // HTTP Parameter Pollution protection
}));

// Rate limiting - prevent brute force & DoS
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // 100 requests per window
  message: { success: false, message: 'Too many requests, please try again later' },
  keyGenerator: (req) => getRateLimitKey(req, 'global'),
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10, // 10 auth attempts per 15 min
  message: { success: false, message: 'Too many authentication attempts' },
  keyGenerator: (req) => getRateLimitKey(req, 'auth'),
});

const paymentLimiter = rateLimit({
  windowMs: 1 * 60 * 1000, // 1 minute
  max: 20, // 20 payments per minute
  message: { success: false, message: 'Too many payment requests' },
  keyGenerator: (req) => getRateLimitKey(req, 'payment'),
});

app.use(globalLimiter);

// CORS - restrict origins in production
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['*'],
  credentials: true,
}));

// Body parsing with size limit
app.use(express.json({ limit: '10kb' }));

// Serve uploaded avatar files statically
const uploadsDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}
if (!fs.existsSync(path.join(uploadsDir, 'avatars'))) {
  fs.mkdirSync(path.join(uploadsDir, 'avatars'), { recursive: true });
}
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Multer configuration for avatar uploads
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, path.join(__dirname, 'uploads', 'avatars'));
  },
  filename: (req, file, cb) => {
    const userId = req.user?.id || generateId();
    const ext = path.extname(file.originalname).toLowerCase();
    cb(null, `${userId}${ext}`);
  },
});

const avatarUpload = multer({
  storage,
  limits: { fileSize: 2 * 1024 * 1024 }, // 2MB max
  fileFilter: (req, file, cb) => {
    const allowedTypes = ['.jpeg', '.jpg', '.png', '.gif', '.webp'];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowedTypes.includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type. Only JPEG, PNG, GIF, and WebP are allowed.'));
    }
  },
});

const generateId = () => crypto.randomUUID();

async function init() {
  await initializeDatabase();
  console.log('PostgreSQL backend server ready');
}

init();

app.get('/api/v1/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ==================== AUTH ROUTES ====================

// Apply rate limiter to auth endpoints
app.use('/api/v1/auth', authLimiter);

app.post('/api/v1/auth/register', async (req, res) => {
  const { email, password, name, phone, role, business_name, business_address } = req.body;

  // Input validation and sanitization
  const errors = {};
  const sanitizedEmail = sanitizeString(email?.toLowerCase().trim() || '');
  const sanitizedName = sanitizeString(name || '', 100);
  const sanitizedPhone = sanitizeString(phone || '', 20);
  const sanitizedBusinessName = sanitizeString(business_name || '', 255);
  const sanitizedBusinessAddress = sanitizeString(business_address || '', 500);

  if (!sanitizedEmail || !isValidEmail(sanitizedEmail)) {
    errors.email = ['Valid email is required'];
  }
  if (!password || password.length < 8) {
    errors.password = ['Password must be at least 8 characters'];
  }
  if (!sanitizedName) {
    errors.name = ['Name is required'];
  }
  if (!sanitizedPhone || !isValidPhone(sanitizedPhone)) {
    errors.phone = ['Valid Nigerian phone number is required'];
  }

  if (Object.keys(errors).length > 0) {
    return res.status(422).json({ success: false, errors });
  }

  try {
    const existing = await db.query('SELECT id FROM users WHERE email = $1', [sanitizedEmail]);
    if (existing.rows.length > 0) {
      return res.status(422).json({ success: false, errors: { email: ['Email already exists'] } });
    }

    // Hash password with bcrypt
    const hashedPassword = await hashPassword(password);
    const userId = generateId();

    await db.query(
      `INSERT INTO users (id, email, password, name, phone, role, business_name, business_address)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [userId, sanitizedEmail, hashedPassword, sanitizedName, sanitizedPhone, role === 'merchant' ? 'merchant' : 'buyer', sanitizedBusinessName || null, sanitizedBusinessAddress || null]
    );

    const walletId = generateId();
    await db.query(
      `INSERT INTO wallets (id, user_id, balance, currency) VALUES ($1, $2, 0, 'NGN')`,
      [walletId, userId]
    );

    // Generate JWT tokens
    const accessToken = generateAccessToken(userId, role || 'buyer');
    const refreshToken = generateRefreshToken(userId);

    const result = await db.query('SELECT id, email, name, phone, role, business_name, business_address, created_at, is_active FROM users WHERE id = $1', [userId]);

    res.status(201).json({
      success: true,
      accessToken,
      refreshToken,
      user: result.rows[0]
    });
  } catch (err) {
    console.error('Registration error:', err.message);
    res.status(500).json({ success: false, message: 'Registration failed' });
  }
});

app.post('/api/v1/auth/login', async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ success: false, message: 'Email and password are required' });
  }

  const sanitizedEmail = sanitizeString(email?.toLowerCase().trim() || '');

  try {
    const result = await db.query('SELECT * FROM users WHERE email = $1', [sanitizedEmail]);
    const user = result.rows[0];

    if (!user) {
      // Use timing-safe comparison even on "user not found"
      await hashPassword('dummy_password_for_timing'); // Waste time to prevent timing attacks
      return res.status(401).json({ success: false, message: 'Invalid credentials' });
    }

    // Check if this is an old SHA-256 hashed password (64 hex characters)
    const isOldSha256Hash = /^[a-f0-9]{64}$/i.test(user.password);

    if (isOldSha256Hash) {
      // Verify using old SHA-256 method
      const sha256Hash = crypto.createHash('sha256').update(password).digest('hex');
      if (sha256Hash !== user.password) {
        return res.status(401).json({ success: false, message: 'Invalid credentials' });
      }

      // Old password matches - require password reset
      return res.status(403).json({
        success: false,
        message: 'Password reset required',
        requiresPasswordReset: true,
        userId: user.id
      });
    }

    // Verify password with bcrypt
    const isValid = await verifyPassword(password, user.password);
    if (!isValid) {
      return res.status(401).json({ success: false, message: 'Invalid credentials' });
    }

    // Check if user is active
    if (!user.is_active) {
      return res.status(403).json({ success: false, message: 'Account is deactivated' });
    }

    // Generate JWT tokens
    const accessToken = generateAccessToken(user.id, user.role);
    const refreshToken = generateRefreshToken(user.id);

    res.json({
      success: true,
      accessToken,
      refreshToken,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        phone: user.phone,
        role: user.role,
        business_name: user.business_name,
        business_address: user.business_address,
        created_at: user.created_at,
        is_active: user.is_active
      }
    });
  } catch (err) {
    console.error('Login error:', err.message);
    res.status(500).json({ success: false, message: 'Login failed' });
  }
});

app.post('/api/v1/auth/refresh', async (req, res) => {
  const { refreshToken } = req.body;

  if (!refreshToken) {
    return res.status(400).json({ success: false, message: 'Refresh token is required' });
  }

  const decoded = verifyToken(refreshToken);
  if (!decoded.valid || decoded.decoded.type !== 'refresh') {
    return res.status(401).json({ success: false, message: 'Invalid refresh token' });
  }

  // Get user from database
  const result = await db.query('SELECT id, role FROM users WHERE id = $1', [decoded.decoded.userId]);
  const user = result.rows[0];

  if (!user) {
    return res.status(401).json({ success: false, message: 'User not found' });
  }

  const newAccessToken = generateAccessToken(user.id, user.role);

  res.json({
    success: true,
    accessToken: newAccessToken,
  });
});

app.post('/api/v1/auth/logout', (req, res) => {
  // In a production app, you would blacklist the token here
  res.json({ success: true, message: 'Logged out successfully' });
});

app.post('/api/v1/auth/forgot-password', async (req, res) => {
  const { email } = req.body;
  const sanitizedEmail = sanitizeString(email?.toLowerCase().trim() || '');

  if (!sanitizedEmail || !isValidEmail(sanitizedEmail)) {
    return res.status(400).json({ success: false, message: 'Valid email is required' });
  }

  // Always return success to prevent email enumeration
  res.json({ success: true, message: 'If an account exists with this email, a reset link has been sent' });
});

// Reset password (for migration from old SHA-256 or general reset)
app.post('/api/v1/auth/reset-password', async (req, res) => {
  const { userId, currentPassword, newPassword, resetToken } = req.body;

  // Validation
  if (!userId || !newPassword) {
    return res.status(400).json({ success: false, message: 'User ID and new password are required' });
  }

  if (newPassword.length < 8) {
    return res.status(400).json({ success: false, message: 'Password must be at least 8 characters' });
  }

  try {
    const result = await db.query('SELECT * FROM users WHERE id = $1', [userId]);
    const user = result.rows[0];

    if (!user) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    // If current password is provided (not a reset token flow), verify it
    if (currentPassword) {
      // Check if old SHA-256 hash
      const isOldSha256Hash = /^[a-f0-9]{64}$/i.test(user.password);
      let isPasswordValid = false;

      if (isOldSha256Hash) {
        const sha256Hash = crypto.createHash('sha256').update(currentPassword).digest('hex');
        isPasswordValid = sha256Hash === user.password;
      } else {
        isPasswordValid = await verifyPassword(currentPassword, user.password);
      }

      if (!isPasswordValid) {
        return res.status(401).json({ success: false, message: 'Current password is incorrect' });
      }
    }

    // Hash new password with bcrypt
    const newHashedPassword = await hashPassword(newPassword);

    // Update password and clear migration flag
    await db.query(
      'UPDATE users SET password = $1, password_migration_required = false WHERE id = $2',
      [newHashedPassword, userId]
    );

    // Generate new JWT tokens
    const accessToken = generateAccessToken(user.id, user.role);
    const refreshToken = generateRefreshToken(user.id);

    res.json({
      success: true,
      message: 'Password reset successfully',
      accessToken,
      refreshToken,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        phone: user.phone,
        role: user.role,
        business_name: user.business_name,
        business_address: user.business_address,
        created_at: user.created_at,
        is_active: user.is_active
      }
    });
  } catch (err) {
    console.error('Password reset error:', err.message);
    res.status(500).json({ success: false, message: 'Password reset failed' });
  }
});

app.get('/api/v1/auth/verify', async (req, res) => {
  const authHeader = req.headers.authorization;

  if (!authHeader) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);

  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Invalid or expired token' });
  }

  // Get fresh user data
  const result = await db.query('SELECT id, email, name, phone, role, business_name, business_address, created_at, is_active FROM users WHERE id = $1', [decoded.decoded.userId]);
  const user = result.rows[0];

  if (!user) {
    return res.status(404).json({ success: false, message: 'User not found' });
  }

  res.json({ success: true, user });
});

app.get('/api/v1/user/profile', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ message: 'Unauthorized' });
  }
  const userId = decoded.decoded.userId;
  const result = await db.query('SELECT * FROM users WHERE id = $1', [userId]);
  const user = result.rows[0];

  if (!user) return res.status(404).json({ message: 'User not found' });
  res.json(user);
});

app.put('/api/v1/user/profile', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
  const userId = decoded.decoded.userId;
  const { name, phone, business_name, business_address } = req.body;

  const result = await db.query('SELECT * FROM users WHERE id = $1', [userId]);
  if (!result.rows[0]) return res.status(404).json({ success: false, message: 'User not found' });

  await db.query(
    `UPDATE users SET name = COALESCE($1, name), phone = COALESCE($2, phone),
     business_name = COALESCE($3, business_name), business_address = COALESCE($4, business_address)
     WHERE id = $5`,
    [name, phone, business_name, business_address, userId]
  );

  const updated = await db.query('SELECT * FROM users WHERE id = $1', [userId]);
  res.json(updated.rows[0]);
});

// ==================== User Avatar ====================

// Middleware to extract user from token for multer
const getAuthUser = async (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });
  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) return res.status(401).json({ success: false, message: 'Unauthorized' });
  req.user = { id: decoded.decoded.userId };
  next();
};

app.put('/api/v1/user/avatar', getAuthUser, avatarUpload.single('avatar'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ success: false, message: 'No image file provided' });
  }

  const userId = req.user.id;
  const avatarUrl = `/uploads/avatars/${req.file.filename}`;

  try {
    await db.query('UPDATE users SET avatar_url = $1 WHERE id = $2', [avatarUrl, userId]);
    res.json({ success: true, avatar_url: avatarUrl });
  } catch (err) {
    console.error('Avatar upload error:', err.message);
    res.status(500).json({ success: false, message: 'Failed to save avatar' });
  }
});

// ==================== User PIN ====================

app.put('/api/v1/user/pin', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }

  const userId = decoded.decoded.userId;
  const { current_pin, new_pin } = req.body;

  if (!new_pin || new_pin.length !== 4 || !/^\d+$/.test(new_pin)) {
    return res.status(400).json({ success: false, message: 'PIN must be 4 digits' });
  }

  try {
    // Check if user already has a PIN set
    const pinResult = await db.query('SELECT pin_hash FROM pins WHERE user_id = $1', [userId]);

    if (pinResult.rows.length > 0) {
      // PIN exists - verify current PIN first
      if (!current_pin) {
        return res.status(400).json({ success: false, message: 'Current PIN is required' });
      }

      const isValid = await verifyPassword(current_pin, pinResult.rows[0].pin_hash);
      if (!isValid) {
        return res.status(400).json({ success: false, message: 'Current PIN is incorrect' });
      }
    }
    // First-time setup: no current_pin check needed

    // Hash and store new PIN
    const newPinHash = await hashPassword(new_pin);
    await db.query(
      `INSERT INTO pins (id, user_id, pin_hash, updated_at)
       VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
       ON CONFLICT (user_id) DO UPDATE SET pin_hash = $3, updated_at = CURRENT_TIMESTAMP`,
      [generateId(), userId, newPinHash]
    );

    res.json({ success: true, message: 'PIN changed successfully' });
  } catch (err) {
    console.error('PIN change error:', err.message);
    res.status(500).json({ success: false, message: 'Failed to change PIN' });
  }
});

app.post('/api/v1/user/pin/verify', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }

  const userId = decoded.decoded.userId;
  const { pin } = req.body;

  if (!pin || pin.length !== 4 || !/^\d+$/.test(pin)) {
    return res.status(400).json({ success: false, valid: false, message: 'PIN must be 4 digits' });
  }

  try {
    const pinResult = await db.query('SELECT pin_hash FROM pins WHERE user_id = $1', [userId]);

    if (pinResult.rows.length === 0) {
      return res.status(400).json({ success: false, valid: false, message: 'PIN not set' });
    }

    const isValid = await verifyPassword(pin, pinResult.rows[0].pin_hash);
    res.json({ success: true, valid: isValid });
  } catch (err) {
    console.error('PIN verify error:', err.message);
    res.status(500).json({ success: false, valid: false, message: 'PIN verification failed' });
  }
});

// ==================== Notification Settings ====================

app.get('/api/v1/user/notifications', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }

  const userId = decoded.decoded.userId;

  try {
    const result = await db.query('SELECT sms_money_in, sms_money_out FROM notification_settings WHERE user_id = $1', [userId]);

    if (result.rows.length === 0) {
      // Return defaults if no settings exist yet
      return res.json({ success: true, settings: { sms_money_in: true, sms_money_out: true } });
    }

    res.json({ success: true, settings: result.rows[0] });
  } catch (err) {
    console.error('Get notifications error:', err.message);
    res.status(500).json({ success: false, message: 'Failed to fetch notification settings' });
  }
});

app.put('/api/v1/user/notifications', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }

  const userId = decoded.decoded.userId;
  const { sms_money_in, sms_money_out } = req.body;

  try {
    await db.query(
      `INSERT INTO notification_settings (id, user_id, sms_money_in, sms_money_out)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id) DO UPDATE SET
         sms_money_in = COALESCE($3, notification_settings.sms_money_in),
         sms_money_out = COALESCE($4, notification_settings.sms_money_out),
         updated_at = CURRENT_TIMESTAMP`,
      [generateId(), userId, sms_money_in, sms_money_out]
    );

    const result = await db.query('SELECT sms_money_in, sms_money_out FROM notification_settings WHERE user_id = $1', [userId]);
    res.json({ success: true, settings: result.rows[0] });
  } catch (err) {
    console.error('Update notifications error:', err.message);
    res.status(500).json({ success: false, message: 'Failed to update notification settings' });
  }
});

// ==================== Bank Account ====================

app.get('/api/v1/user/bank-account', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }

  const userId = decoded.decoded.userId;

  try {
    const result = await db.query('SELECT * FROM bank_accounts WHERE user_id = $1', [userId]);

    if (result.rows.length === 0) {
      return res.json({ success: true, bank_account: null });
    }

    res.json({ success: true, bank_account: result.rows[0] });
  } catch (err) {
    console.error('Get bank account error:', err.message);
    res.status(500).json({ success: false, message: 'Failed to fetch bank account' });
  }
});

app.put('/api/v1/user/bank-account', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }

  const userId = decoded.decoded.userId;
  const { bank_name, account_number, account_name } = req.body;

  // Validation
  const errors = {};
  if (!bank_name || bank_name.trim().length < 2) {
    errors.bank_name = ['Bank name is required'];
  }
  if (!account_number || !/^\d{10}$/.test(account_number.trim())) {
    errors.account_number = ['Account number must be 10 digits'];
  }
  if (!account_name || account_name.trim().length < 3) {
    errors.account_name = ['Account name is required'];
  }

  if (Object.keys(errors).length > 0) {
    return res.status(422).json({ success: false, errors });
  }

  try {
    await db.query(
      `INSERT INTO bank_accounts (id, user_id, bank_name, account_number, account_name, updated_at)
       VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP)
       ON CONFLICT (user_id) DO UPDATE SET
         bank_name = $3,
         account_number = $4,
         account_name = $5,
         updated_at = CURRENT_TIMESTAMP`,
      [generateId(), userId, bank_name.trim(), account_number.trim(), account_name.trim()]
    );

    const result = await db.query('SELECT * FROM bank_accounts WHERE user_id = $1', [userId]);
    res.json({ success: true, bank_account: result.rows[0] });
  } catch (err) {
    console.error('Update bank account error:', err.message);
    res.status(500).json({ success: false, message: 'Failed to save bank account' });
  }
});

app.delete('/api/v1/user/bank-account', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }

  const userId = decoded.decoded.userId;

  try {
    await db.query('DELETE FROM bank_accounts WHERE user_id = $1', [userId]);
    res.json({ success: true, message: 'Bank account removed' });
  } catch (err) {
    console.error('Delete bank account error:', err.message);
    res.status(500).json({ success: false, message: 'Failed to delete bank account' });
  }
});

app.get('/api/v1/wallet', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ message: 'Unauthorized' });
  }
  const userId = decoded.decoded.userId;

  const result = await db.query('SELECT * FROM wallets WHERE user_id = $1', [userId]);
  const wallet = result.rows[0];

  if (!wallet) return res.status(404).json({ message: 'Wallet not found' });
  res.json(wallet);
});

app.post('/api/v1/wallet/topup', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  // Verify JWT token
  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }

  const userId = decoded.decoded.userId;
  const { amount } = req.body;

  if (!amount || amount <= 0) {
    return res.status(400).json({ success: false, message: 'Invalid amount' });
  }

  // Get current balance before update
  const beforeResult = await db.query('SELECT * FROM wallets WHERE user_id = $1', [userId]);
  const balanceBefore = parseFloat(beforeResult.rows[0]?.balance || 0);

  if (!beforeResult.rows[0]) {
    return res.status(404).json({ success: false, message: 'Wallet not found' });
  }

  // Update wallet balance
  await db.query('UPDATE wallets SET balance = balance + $1 WHERE user_id = $2', [parseFloat(amount), userId]);

  // Get new balance after update
  const result = await db.query('SELECT * FROM wallets WHERE user_id = $1', [userId]);
  const balanceAfter = parseFloat(result.rows[0]?.balance || 0);

  // Record in wallet_ledger
  const ledgerId = generateId();
  const reference = `TOPUP-${generateId()}`;
  await db.query(
    `INSERT INTO wallet_ledger (id, wallet_id, type, amount, balance_before, balance_after, reference, description, created_at)
     VALUES ($1, $2, 'topup', $3, $4, $5, $6, 'Wallet topup', $7)`,
    [ledgerId, result.rows[0].id, parseFloat(amount), balanceBefore, balanceAfter, reference, new Date().toISOString()]
  );

  res.json({
    success: true,
    reference: reference,
    wallet: result.rows[0],
    payment_url: `https://mock-payment.com/checkout/${generateId()}`
  });
});

app.post('/api/v1/wallet/topup/verify', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
  const userId = decoded.decoded.userId;
  const result = await db.query('SELECT * FROM wallets WHERE user_id = $1', [userId]);

  if (!result.rows[0]) return res.status(404).json({ success: false, message: 'Wallet not found' });
  res.json({ success: true, wallet: result.rows[0] });
});

// Get wallet ledger entries (for wallet history)
app.get('/api/v1/wallet/ledger', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
  const userId = decoded.decoded.userId;
  const { page = 1, limit = 20 } = req.query;

  // First get the wallet
  const walletResult = await db.query('SELECT * FROM wallets WHERE user_id = $1', [userId]);
  if (!walletResult.rows[0]) return res.status(404).json({ success: false, message: 'Wallet not found' });

  const walletId = walletResult.rows[0].id;
  const offset = (parseInt(page) - 1) * parseInt(limit);

  // Get ledger entries
  const ledgerResult = await db.query(
    `SELECT * FROM wallet_ledger WHERE wallet_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
    [walletId, parseInt(limit), offset]
  );

  // Get total count
  const countResult = await db.query('SELECT COUNT(*) FROM wallet_ledger WHERE wallet_id = $1', [walletId]);

  res.json({
    success: true,
    ledger: ledgerResult.rows,
    pagination: {
      page: parseInt(page),
      limit: parseInt(limit),
      total: parseInt(countResult.rows[0].count),
      totalPages: Math.ceil(parseInt(countResult.rows[0].count) / parseInt(limit))
    }
  });
});

// Manual wallet funding for testing (not a real payment)
app.post('/api/v1/wallet/manual-fund', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
  const userId = decoded.decoded.userId;
  const { amount, reason } = req.body;

  if (!amount || amount <= 0) {
    return res.status(400).json({ success: false, message: 'Invalid amount' });
  }

  // Only allow in development environment
  if (process.env.NODE_ENV === 'production') {
    return res.status(403).json({ success: false, message: 'Not available in production' });
  }

  // Get current balance before update
  const beforeResult = await db.query('SELECT * FROM wallets WHERE user_id = $1', [userId]);
  const balanceBefore = parseFloat(beforeResult.rows[0]?.balance || 0);

  await db.query('UPDATE wallets SET balance = balance + $1 WHERE user_id = $2', [parseFloat(amount), userId]);

  const result = await db.query('SELECT * FROM wallets WHERE user_id = $1', [userId]);
  const balanceAfter = parseFloat(result.rows[0]?.balance || 0);

  // Record in wallet_ledger
  const ledgerId = generateId();
  const reference = `MANUAL-${generateId()}`;
  await db.query(
    `INSERT INTO wallet_ledger (id, wallet_id, type, amount, balance_before, balance_after, reference, description, created_at)
     VALUES ($1, $2, 'manual_fund', $3, $4, $5, $6, $7, $8)`,
    [ledgerId, result.rows[0].id, parseFloat(amount), balanceBefore, balanceAfter, reference, reason ? `Manual fund: ${reason}` : 'Manual fund (testing)', new Date().toISOString()]
  );

  console.log(`[MANUAL FUND] User ${userId} funded wallet with ₦${amount} - Reason: ${reason || 'N/A'}`);

  res.json({
    success: true,
    reference: reference,
    wallet: result.rows[0],
    message: `Wallet funded with ₦${amount}. Reason: ${reason || 'Testing'}`
  });
});

// Real Paystack wallet topup - Step 1: Initialize payment
app.post('/api/v1/wallet/topup/paystack-initialize', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
  const userId = decoded.decoded.userId;
  const userResult = await db.query('SELECT * FROM users WHERE id = $1', [userId]);
  const user = userResult.rows[0];

  if (!user) return res.status(404).json({ success: false, message: 'User not found' });

  const { amount } = req.body;
  if (!amount || amount <= 0) {
    return res.status(400).json({ success: false, message: 'Invalid amount' });
  }

  const reference = `TOPUP-${Date.now()}-${generateId()}`;

  try {
    const response = await axios.post(
      `${PAYSTACK_BASE_URL}/transaction/initialize`,
      {
        email: user.email,
        amount: Math.round(parseFloat(amount) * 100), // Convert to kobo
        currency: 'NGN',
        reference: reference,
        callback_url: `${process.env.BASE_URL || 'http://160.226.0.67:3001'}/api/v1/wallet/topup/paystack-callback`,
        metadata: {
          user_id: userId,
          type: 'wallet_topup',
        },
        payment_channels: ['card', 'bank', 'transfer', 'qr', 'mps', 'ussd'],
      },
      {
        headers: {
          Authorization: `Bearer ${PAYSTACK_SECRET_KEY}`,
          'Content-Type': 'application/json',
        },
      }
    );

    res.json({
      success: true,
      payment_url: response.data.data.authorization_url,
      reference: reference,
      access_code: response.data.data.access_code,
    });
  } catch (err) {
    console.error('Paystack topup init error:', err.response?.data || err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to initialize payment: ' + (err.response?.data?.message || err.message)
    });
  }
});

// Real Paystack wallet topup - Step 2: Callback (Paystack redirects here after payment)
app.get('/api/v1/wallet/topup/paystack-callback', async (req, res) => {
  const { reference, trx } = req.query;

  if (!reference) {
    return res.redirect('/?error=missing_reference');
  }

  try {
    // Verify the transaction with Paystack
    const verifyResponse = await axios.get(
      `${PAYSTACK_BASE_URL}/transaction/verify/${reference}`,
      {
        headers: {
          Authorization: `Bearer ${PAYSTACK_SECRET_KEY}`,
        },
      }
    );

    const verifyData = verifyResponse.data.data;

    if (verifyData.status === 'success') {
      const metadata = verifyData.metadata || {};
      const userId = metadata.user_id;

      if (!userId) {
        console.error('Paystack callback: No user_id in metadata for reference', reference);
        return res.redirect('/?error=missing_user_id');
      }

      // Credit the wallet
      const amountInNaira = verifyData.amount / 100; // Convert from kobo

      // Get current balance before update
      const beforeResult = await db.query('SELECT * FROM wallets WHERE user_id = $1', [userId]);
      const balanceBefore = parseFloat(beforeResult.rows[0]?.balance || 0);

      await db.query(
        'UPDATE wallets SET balance = balance + $1 WHERE user_id = $2',
        [amountInNaira, userId]
      );

      // Get wallet and record in ledger
      const walletResult = await db.query('SELECT * FROM wallets WHERE user_id = $1', [userId]);
      const balanceAfter = parseFloat(walletResult.rows[0]?.balance || 0);

      const ledgerId = generateId();
      await db.query(
        `INSERT INTO wallet_ledger (id, wallet_id, type, amount, balance_before, balance_after, reference, description, created_at)
         VALUES ($1, $2, 'paystack_topup', $3, $4, $5, $6, 'Paystack wallet topup', $7)`,
        [ledgerId, walletResult.rows[0].id, amountInNaira, balanceBefore, balanceAfter, reference, new Date().toISOString()]
      );

      console.log(`[PAYSTACK TOPUP] User ${userId} funded wallet with ₦${amountInNaira} via Paystack`);

      // Send money-in SMS notification
      const userInfo = await db.query('SELECT name, phone FROM users WHERE id = $1', [userId]);
      if (userInfo.rows[0]?.phone) {
        const notifResult = await db.query('SELECT sms_money_in FROM notification_settings WHERE user_id = $1', [userId]);
        if (!notifResult.rows[0] || notifResult.rows[0].sms_money_in) {
          const amountFormatted = `₦${amountInNaira.toLocaleString('en-NG')}`;
          await sendMoneyInSMS(
            userInfo.rows[0].phone,
            amountFormatted,
            'Wallet Topup',
            reference
          );
        }
      }

      // Redirect to app with success
      res.redirect(`/wallet-topup-success?reference=${reference}&amount=${amountInNaira}`);
    } else {
      res.redirect('/?error=payment_failed');
    }
  } catch (err) {
    console.error('Paystack callback error:', err.response?.data || err.message);
    res.redirect('/?error=verification_failed');
  }
});

app.get('/api/v1/transactions', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
  const userId = decoded.decoded.userId;
  const { page = 1, limit = 20, type, status } = req.query;

  let query = `SELECT t.*, u.name as buyer_name FROM transactions t LEFT JOIN users u ON t.buyer_id = u.id WHERE t.buyer_id = $1 OR t.merchant_id = $1`;
  const params = [userId];
  let paramIndex = 2;

  if (type) {
    query += ` AND t.type = $${paramIndex}`;
    params.push(type);
    paramIndex++;
  }
  if (status) {
    query += ` AND t.status = $${paramIndex}`;
    params.push(status);
    paramIndex++;
  }

  query += ' ORDER BY t.created_at DESC';

  const pageNum = parseInt(page);
  const limitNum = parseInt(limit);
  query += ` LIMIT $${paramIndex} OFFSET ${(pageNum - 1) * limitNum}`;
  params.push(limitNum);

  const result = await db.query(query, params);
  const countResult = await db.query(
    'SELECT COUNT(*) FROM transactions WHERE buyer_id = $1 OR merchant_id = $1',
    [userId]
  );

  res.json({
    transactions: result.rows,
    page: pageNum,
    limit: limitNum,
    total: parseInt(countResult.rows[0].count)
  });
});

app.get('/api/v1/transactions/:id', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
  const userId = decoded.decoded.userId;
  const { id } = req.params;

  const result = await db.query('SELECT * FROM transactions WHERE id = $1', [id]);
  const transaction = result.rows[0];

  if (!transaction) return res.status(404).json({ success: false, message: 'Transaction not found' });
  if (transaction.buyer_id !== userId && transaction.merchant_id !== userId) {
    return res.status(403).json({ success: false, message: 'Access denied' });
  }

  res.json(transaction);
});

app.post('/api/v1/transactions/payment', paymentLimiter, async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  // Verify JWT
  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Invalid or expired token' });
  }

  const buyerId = decoded.decoded.userId;
  const { merchant_id, amount, pin, description, idempotency_key } = req.body;

  // Input validation
  if (!merchant_id || !amount) {
    return res.status(400).json({ success: false, message: 'Merchant ID and amount are required' });
  }

  if (!isValidAmount(amount)) {
    return res.status(400).json({ success: false, message: 'Invalid amount' });
  }

  // Idempotency check - prevent duplicate payments
  if (idempotency_key) {
    const existingTxn = await db.query(
      'SELECT * FROM transactions WHERE reference = $1',
      [`${idempotency_key}-${buyerId}`]
    );
    if (existingTxn.rows.length > 0) {
      return res.json({ success: true, transaction: existingTxn.rows[0], duplicate: true });
    }
  }

  // Get buyer wallet with row lock for concurrent safety
  const buyerWalletResult = await db.query('SELECT * FROM wallets WHERE user_id = $1 FOR UPDATE', [buyerId]);
  const buyerWallet = buyerWalletResult.rows[0];

  if (!buyerWallet) {
    return res.status(404).json({ success: false, message: 'Wallet not found' });
  }

  if (parseFloat(buyerWallet.balance) < parseFloat(amount)) {
    return res.status(400).json({ success: false, message: 'Insufficient balance' });
  }

  // Verify merchant exists
  const merchantResult = await db.query('SELECT * FROM users WHERE id = $1 AND role = $2', [merchant_id, 'merchant']);
  const merchant = merchantResult.rows[0];
  if (!merchant) return res.status(404).json({ success: false, message: 'Invalid merchant' });

  // Use transaction for atomic operation
  const transactionId = generateId();
  const reference = idempotency_key ? `${idempotency_key}-${buyerId}` : `PAY-${generateId()}`;
  const now = new Date().toISOString();

  try {
    // Insert transaction
    await db.query(
      `INSERT INTO transactions (id, reference, buyer_id, merchant_id, merchant_name, amount, currency, status, type, description, created_at, completed_at)
       VALUES ($1, $2, $3, $4, $5, $6, 'NGN', 'completed', 'payment', $7, $8, $8)`,
      [transactionId, reference, buyerId, merchant_id, merchant.business_name || merchant.name, parseFloat(amount), sanitizeString(description || '', 255), now]
    );

    // Debit buyer
    await db.query('UPDATE wallets SET balance = balance - $1 WHERE user_id = $2', [parseFloat(amount), buyerId]);

    // Credit merchant (separate query for audit trail)
    await db.query('UPDATE wallets SET balance = balance + $1 WHERE user_id = $2', [parseFloat(amount), merchant_id]);

    // Record in merchant's wallet ledger
    const ledgerId = generateId();
    const merchantWalletResult = await db.query('SELECT * FROM wallets WHERE user_id = $1', [merchant_id]);
    await db.query(
      `INSERT INTO wallet_ledger (id, wallet_id, type, amount, balance_before, balance_after, reference, description, created_at)
       VALUES ($1, $2, 'payment', $3, $4, $5, $6, $7, $8)`,
      [ledgerId, merchantWalletResult.rows[0].id, parseFloat(amount), parseFloat(merchantWalletResult.rows[0].balance), parseFloat(merchantWalletResult.rows[0].balance) + parseFloat(amount), reference, `Payment from ${buyerId}`, now]
    );

    // Send SMS notifications
    const amountFormatted = `₦${parseFloat(amount).toLocaleString('en-NG')}`;

    // Get buyer info for money-out SMS
    const buyerInfo = await db.query('SELECT name, phone FROM users WHERE id = $1', [buyerId]);
    if (buyerInfo.rows[0]?.phone) {
      const notifResult = await db.query('SELECT sms_money_out FROM notification_settings WHERE user_id = $1', [buyerId]);
      if (!notifResult.rows[0] || notifResult.rows[0].sms_money_out) {
        await sendMoneyOutSMS(
          buyerInfo.rows[0].phone,
          amountFormatted,
          merchant.business_name || merchant.name,
          reference
        );
      }
    }

    // Get merchant info for money-in SMS
    const merchantInfo = await db.query('SELECT name, phone FROM users WHERE id = $1', [merchant_id]);
    if (merchantInfo.rows[0]?.phone) {
      const notifResult = await db.query('SELECT sms_money_in FROM notification_settings WHERE user_id = $1', [merchant_id]);
      if (!notifResult.rows[0] || notifResult.rows[0].sms_money_in) {
        await sendMoneyInSMS(
          merchantInfo.rows[0].phone,
          amountFormatted,
          buyerInfo.rows[0]?.name || 'a customer',
          reference
        );
      }
    }

    const txnResult = await db.query('SELECT * FROM transactions WHERE id = $1', [transactionId]);

    res.json({ success: true, transaction: txnResult.rows[0] });
  } catch (err) {
    console.error('Payment error:', err.message);
    res.status(500).json({ success: false, message: 'Payment failed' });
  }
});

app.post('/api/v1/qr/generate', async (req, res) => {
  const authHeader = req.headers.authorization;

  if (!authHeader) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }

  // Verify JWT token
  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Invalid or expired token' });
  }

  const userId = decoded.decoded.userId;

  const userResult = await db.query('SELECT * FROM users WHERE id = $1', [userId]);
  const user = userResult.rows[0];

  if (!user) {
    return res.status(404).json({ success: false, message: 'User not found' });
  }
  if (user.role !== 'merchant') {
    return res.status(403).json({ success: false, message: 'Only merchants can generate QR codes' });
  }

  // Generate signed QR payload to prevent fake QR codes
  // QR expires in 30 minutes
  // The QR payload is a custom app format, NOT a Paystack URL
  // Payment happens inside the app via /payments/paystack/initialize
  const signedQR = signQRPayload(user.id, 30);

  // Build a custom QR payload (JSON format for rich scanning)
  const qrPayload = {
    merchant_id: user.id,
    merchant_name: user.business_name || user.name,
    expiry: signedQR.expiry,
    signature: signedQR.signature,
  };

  res.json({
    success: true,
    qr_data: {
      merchant_id: user.id,
      merchant_name: user.business_name || user.name,
      qr_payload: qrPayload,
      qr_payload_compact: Buffer.from(
        `${user.id}|${signedQR.expiry}|${signedQR.signature}`
      ).toString('base64'),
      qr_expiry: signedQR.expiry,
      qr_timestamp: signedQR.timestamp,
    }
  });
});

app.post('/api/v1/qr/verify', async (req, res) => {
  const { qr_payload } = req.body;
  console.log('[QR VERIFY] Received request, qr_payload:', qr_payload);
  if (!qr_payload) return res.status(400).json({ success: false, message: 'QR payload is required' });

  try {
    // Parse QR payload
    let merchantId, expiry, signature;

    try {
      const qrData = JSON.parse(qr_payload);
      merchantId = qrData.merchant_id;
      expiry = qrData.expiry;
      signature = qrData.signature;
      console.log('[QR VERIFY] Parsed JSON - merchantId:', merchantId, 'expiry:', expiry);
    } catch {
      // Try compact form (base64 encoded)
      console.log('[QR VERIFY] JSON parse failed, trying base64');
      const decoded = Buffer.from(qr_payload, 'base64').toString('utf8');
      console.log('[QR VERIFY] Base64 decoded:', decoded);
      const parts = decoded.split('|');
      if (parts.length === 3) {
        merchantId = parts[0];
        expiry = parts[1];
        signature = parts[2];
        console.log('[QR VERIFY] Parsed compact - merchantId:', merchantId, 'expiry:', expiry, 'signature:', signature);
      } else {
        console.log('[QR VERIFY] Compact parse failed, parts.length:', parts.length);
        return res.status(400).json({ success: false, message: 'Invalid QR code format' });
      }
    }

    if (!merchantId || !expiry || !signature) {
      console.log('[QR VERIFY] Missing fields - merchantId:', merchantId, 'expiry:', expiry, 'signature:', signature);
      return res.status(400).json({ success: false, message: 'Invalid QR code: missing security data' });
    }

    // Verify QR signature to prevent fake QR codes
    console.log('[QR VERIFY] Calling verifyQRPayload');
    const verification = verifyQRPayload(merchantId, expiry, signature);
    console.log('[QR VERIFY] Verification result:', verification);
    if (!verification.valid) {
      console.log('[QR VERIFY] Verification failed:', verification.error);
      return res.status(400).json({ success: false, message: verification.error || 'Invalid QR code' });
    }

    // Lookup merchant
    const result = await db.query('SELECT * FROM users WHERE id = $1 AND role = $2', [merchantId, 'merchant']);
    const merchant = result.rows[0];

    if (!merchant) return res.status(404).json({ success: false, message: 'Invalid merchant' });

    console.log('[QR VERIFY] Success! Merchant:', merchant.business_name || merchant.name);
    res.json({
      success: true,
      merchant_id: merchant.id,
      merchant_name: merchant.business_name || merchant.name,
      merchant_address: merchant.business_address || ''
    });
  } catch (e) {
    console.log('[QR VERIFY] Exception:', e);
    res.status(400).json({ success: false, message: 'Invalid QR code format' });
  }
});

app.get('/api/v1/merchant/stats', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
  const userId = decoded.decoded.userId;
  const userResult = await db.query('SELECT * FROM users WHERE id = $1', [userId]);
  const user = userResult.rows[0];

  if (!user || user.role !== 'merchant') {
    return res.status(403).json({ success: false, message: 'Only merchants can access stats' });
  }

  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const weekStart = new Date(todayStart.getTime() - 7 * 24 * 60 * 60 * 1000);
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

  const totalResult = await db.query(
    "SELECT COUNT(*) as count, COALESCE(SUM(amount), 0) as total FROM transactions WHERE merchant_id = $1 AND status = 'completed'",
    [userId]
  );
  const todayResult = await db.query(
    "SELECT COALESCE(SUM(amount), 0) as total FROM transactions WHERE merchant_id = $1 AND status = 'completed' AND created_at >= $2",
    [userId, todayStart.toISOString()]
  );
  const weekResult = await db.query(
    "SELECT COALESCE(SUM(amount), 0) as total FROM transactions WHERE merchant_id = $1 AND status = 'completed' AND created_at >= $2",
    [userId, weekStart.toISOString()]
  );
  const monthResult = await db.query(
    "SELECT COALESCE(SUM(amount), 0) as total FROM transactions WHERE merchant_id = $1 AND status = 'completed' AND created_at >= $2",
    [userId, monthStart.toISOString()]
  );

  res.json({
    total_transactions: parseInt(totalResult.rows[0].count),
    total_revenue: parseFloat(totalResult.rows[0].total),
    today_revenue: parseFloat(todayResult.rows[0].total),
    week_revenue: parseFloat(weekResult.rows[0].total),
    month_revenue: parseFloat(monthResult.rows[0].total)
  });
});

app.get('/api/v1/merchant/transactions', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
  const userId = decoded.decoded.userId;
  const { page = 1, limit = 20 } = req.query;

  const pageNum = parseInt(page);
  const limitNum = parseInt(limit);

  const result = await db.query(
    `SELECT t.*, u.name as buyer_name FROM transactions t
     LEFT JOIN users u ON t.buyer_id = u.id
     WHERE t.merchant_id = $1 ORDER BY t.created_at DESC LIMIT $2 OFFSET $3`,
    [userId, limitNum, (pageNum - 1) * limitNum]
  );
  const countResult = await db.query('SELECT COUNT(*) FROM transactions WHERE merchant_id = $1', [userId]);

  res.json({
    transactions: result.rows,
    page: pageNum,
    limit: limitNum,
    total: parseInt(countResult.rows[0].count)
  });
});

// Hardcoded supplement of major Nigerian banks (ensures key banks always appear)
const MAJOR_NIGERIAN_BANKS = [
  { name: 'Access Bank', code: '044', slug: 'access-bank' },
  { name: 'First Bank of Nigeria', code: '011', slug: 'first-bank-of-nigeria' },
  { name: 'Guaranty Trust Bank', code: '058', slug: 'guaranty-trust-bank' },
  { name: 'United Bank for Africa', code: '033', slug: 'united-bank-for-africa' },
  { name: 'Zenith Bank', code: '057', slug: 'zenith-bank' },
  { name: 'First City Monument Bank', code: '214', slug: 'first-city-monument-bank' },
  { name: 'Ecobank Nigeria', code: '050', slug: 'ecobank-nigeria' },
  { name: 'Sterling Bank', code: '232', slug: 'sterling-bank' },
  { name: 'Wema Bank', code: '035', slug: 'wema-bank' },
  { name: 'Polaris Bank', code: '076', slug: 'polaris-bank' },
  { name: 'Fidelity Bank', code: '070', slug: 'fidelity-bank' },
  { name: 'Union Bank of Nigeria', code: '032', slug: 'union-bank-of-nigeria' },
  { name: 'Keystone Bank', code: '082', slug: 'keystone-bank' },
  { name: 'Stanbic IBTC Bank', code: '221', slug: 'stanbic-ibtc-bank' },
  { name: 'Heritage Bank', code: '030', slug: 'heritage-bank' },
  { name: 'Suntrust Bank', code: '100', slug: 'suntrust-bank' },
  { name: 'Jaiz Bank', code: '301', slug: 'jaiz-bank' },
  { name: 'Providus Bank', code: '101', slug: 'providus-bank' },
  { name: 'Parallex Bank', code: '526', slug: 'parallex-bank' },
  { name: 'Globus Bank', code: '527', slug: 'globus-bank' },
  { name: 'Titan Trust Bank', code: '102', slug: 'titan-trust-bank' },
  { name: 'Taj Bank', code: '523', slug: 'taj-bank' },
  { name: 'Premium Trust Bank', code: '512', slug: 'premium-trust-bank' },
  { name: 'Opay', code: '100039', slug: 'opay' },
  { name: 'Moniepoint Microfinance Bank', code: '100040', slug: 'moniepoint-microfinance-bank' },
  { name: 'Palmpay', code: '100033', slug: 'palmpay' },
  { name: 'Kuda Bank', code: '100035', slug: 'kuda-bank' },
  { name: 'V Bank (VFD Microfinance Bank)', code: '100028', slug: 'vbank' },
  { name: 'Chipper Cash', code: '100042', slug: 'chipper-cash' },
  { name: 'Paga', code: '100031', slug: 'paga' },
];

// Get list of Nigerian banks (for Flutter dropdown)
let cachedBanks = null;
let cachedBanksTime = 0;
const BANKS_CACHE_TTL = 60 * 60 * 1000; // 1 hour

app.get('/api/v1/payments/paystack/banks', async (req, res) => {
  try {
    // Return cached banks if still fresh
    if (cachedBanks && (Date.now() - cachedBanksTime) < BANKS_CACHE_TTL) {
      return res.json({ success: true, banks: cachedBanks });
    }

    let banks = [];
    try {
      const response = await axios.get(`${PAYSTACK_BASE_URL}/bank`, {
        params: { country: 'nigeria', use_cursor: false },
        headers: { Authorization: `Bearer ${PAYSTACK_SECRET_KEY}` },
      });

      banks = response.data.data
        .filter(b => b.active)
        .map(b => ({ name: b.name, code: b.code, slug: b.slug }));

      console.log(`Fetched ${banks.length} banks from Paystack`);
    } catch (apiErr) {
      console.warn('Paystack bank list fetch failed, using supplement only:', apiErr.message);
    }

    // Merge: supplement with major banks, avoiding duplicates by code
    const bankCodes = new Set(banks.map(b => b.code));
    for (const bank of MAJOR_NIGERIAN_BANKS) {
      if (!bankCodes.has(bank.code)) {
        banks.push(bank);
      }
    }

    // Sort alphabetically by name
    banks.sort((a, b) => a.name.localeCompare(b.name));

    cachedBanks = banks;
    cachedBanksTime = Date.now();

    console.log(`Returning ${banks.length} Nigerian banks (Paystack + supplement)`);
    res.json({ success: true, banks });
  } catch (err) {
    console.error('Bank list error:', err.message);
    if (cachedBanks) {
      return res.json({ success: true, banks: cachedBanks });
    }
    res.status(500).json({ success: false, message: 'Failed to fetch banks' });
  }
});

// Initiate bank payment (redirects to Paystack checkout with bank channel)
app.post('/api/v1/payments/paystack/bank-charge', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
  const userId = decoded.decoded.userId;
  const userResult = await db.query('SELECT * FROM users WHERE id = $1', [userId]);
  const user = userResult.rows[0];

  if (!user) return res.status(404).json({ success: false, message: 'User not found' });

  const { amount, merchant_id, merchant_name, bank_code } = req.body;
  if (!amount || amount <= 0) return res.status(400).json({ success: false, message: 'Invalid amount' });
  if (!bank_code) return res.status(400).json({ success: false, message: 'Bank code is required' });

  const merchantResult = await db.query('SELECT * FROM users WHERE id = $1 AND role = $2', [merchant_id, 'merchant']);
  if (!merchantResult.rows[0]) return res.status(404).json({ success: false, message: 'Merchant not found' });

  const reference = `PAY-${Date.now()}-${generateId()}`;
  const transactionId = generateId();
  const resolvedMerchantName = merchant_name || merchantResult.rows[0].business_name || merchantResult.rows[0].name || 'Merchant';

  // Create pending transaction
  await db.query(
    `INSERT INTO transactions (id, reference, buyer_id, merchant_id, merchant_name, amount, currency, status, type, created_at)
     VALUES ($1, $2, $3, $4, $5, $6, 'NGN', 'pending', 'payment', $7)`,
    [transactionId, reference, userId, merchant_id, resolvedMerchantName, parseFloat(amount), new Date().toISOString()]
  );

  // Initialize Paystack standard checkout (reliable, works with all banks)
  try {
    const response = await axios.post(
      `${PAYSTACK_BASE_URL}/transaction/initialize`,
      {
        email: user.email,
        amount: Math.round(parseFloat(amount) * 100),
        currency: 'NGN',
        reference: reference,
        callback_url: `${process.env.BASE_URL || 'http://160.226.0.67:3001'}/api/v1/payments/paystack/callback`,
        metadata: {
          merchant_id: merchant_id,
          merchant_name: resolvedMerchantName,
          buyer_id: userId,
          bank_code: bank_code,
          payment_method: 'bank_checkout',
        },
        payment_channels: ['card', 'bank', 'transfer', 'ussd'],
      },
      {
        headers: {
          Authorization: `Bearer ${PAYSTACK_SECRET_KEY}`,
          'Content-Type': 'application/json',
        },
        timeout: 15000,
      }
    );

    const authorizationUrl = response.data.data.authorization_url;
    console.log(`Payment initialized: ${reference}, bank=${bank_code}`);

    return res.json({
      success: true,
      auth_url: authorizationUrl,
      reference: reference,
      message: 'Redirected to Paystack checkout.',
    });
  } catch (err) {
    console.error('Payment init error:', err.response?.data || err.message);
    return res.status(500).json({
      success: false,
      message: err.response?.data?.message || 'Failed to initialize payment',
    });
  }
});

app.post('/api/v1/payments/paystack/initialize', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const decoded = verifyToken(token);
  if (!decoded.valid) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
  const userId = decoded.decoded.userId;
  const userResult = await db.query('SELECT * FROM users WHERE id = $1', [userId]);
  const user = userResult.rows[0];

  if (!user) return res.status(404).json({ success: false, message: 'User not found' });

  const { amount, merchant_id, merchant_name } = req.body;
  if (!amount || amount <= 0) return res.status(400).json({ success: false, message: 'Invalid amount' });

  const merchantResult = await db.query('SELECT * FROM users WHERE id = $1 AND role = $2', [merchant_id, 'merchant']);
  if (!merchantResult.rows[0]) return res.status(404).json({ success: false, message: 'Merchant not found' });

  const reference = `PAY-${Date.now()}-${generateId()}`;
  const transactionId = generateId();
  const resolvedMerchantName = merchant_name || merchantResult.rows[0].business_name || merchantResult.rows[0].name || 'Merchant';

  await db.query(
    `INSERT INTO transactions (id, reference, buyer_id, merchant_id, merchant_name, amount, currency, status, type, created_at)
     VALUES ($1, $2, $3, $4, $5, $6, 'NGN', 'pending', 'payment', $7)`,
    [transactionId, reference, userId, merchant_id, resolvedMerchantName, parseFloat(amount), new Date().toISOString()]
  );

  try {
    const response = await axios.post(
      `${PAYSTACK_BASE_URL}/transaction/initialize`,
      {
        email: user.email,
        amount: Math.round(parseFloat(amount) * 100), // amount in kobo
        currency: 'NGN',
        reference: reference,
        callback_url: `${process.env.BASE_URL || 'http://160.226.0.67:3001'}/api/v1/payments/paystack/callback`,
        metadata: {
          merchant_id: merchant_id,
          merchant_name: merchant_name,
          buyer_id: userId,
        },
        payment_channels: ['card', 'bank', 'transfer', 'qr', 'mps', 'ussd'],
      },
      {
        headers: {
          Authorization: `Bearer ${PAYSTACK_SECRET_KEY}`,
          'Content-Type': 'application/json',
        },
      }
    );

    const authorizationUrl = response.data.data.authorization_url;
    const accessCode = response.data.data.access_code;

    res.json({
      success: true,
      payment_url: authorizationUrl,
      reference: reference,
      access_code: accessCode,
      message: 'Payment link generated'
    });
  } catch (err) {
    console.error('Paystack initialize error:', err.response?.data || err.message);
    res.status(500).json({
      success: false,
      message: err.response?.data?.message || 'Failed to initialize payment'
    });
  }
});

app.get('/api/v1/payments/paystack/callback', async (req, res) => {
  const { reference, trxref } = req.query;
  const ref = reference || trxref;

  console.log(`Paystack callback: reference=${ref}`);

  // Helper: deep-link redirect back to app
  const deepLink = ref ? `qrpay://payment/success?reference=${ref}` : 'qrpay://payment/success';

  if (ref) {
    // Try verifying with Paystack (with retries)
    let verifyData;
    let verified = false;

    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        const verifyResponse = await axios.get(
          `${PAYSTACK_BASE_URL}/transaction/verify/${ref}`,
          {
            headers: { Authorization: `Bearer ${PAYSTACK_SECRET_KEY}` },
            timeout: 15000,
          }
        );
        verifyData = verifyResponse.data.data;
        verified = true;
        console.log(`Paystack callback verify attempt ${attempt} succeeded for ${ref}: status=${verifyData.status}`);
        break;
      } catch (err) {
        console.error(`Paystack callback verify attempt ${attempt}/3 failed:`, err.code || err.message);
        if (attempt < 3) {
          await new Promise(r => setTimeout(r, 2000));
        }
      }
    }

    if (verified && verifyData) {
      if (verifyData.status === 'success') {
        const txnResult = await db.query('SELECT * FROM transactions WHERE reference = $1', [ref]);
        const transaction = txnResult.rows[0];

        if (transaction && transaction.status !== 'completed') {
          await db.query("UPDATE transactions SET status = 'completed', completed_at = $1 WHERE reference = $2",
            [new Date().toISOString(), ref]);
          await db.query('UPDATE wallets SET balance = balance + $1 WHERE user_id = $2',
            [transaction.amount, transaction.merchant_id]);
          await db.query('UPDATE wallets SET balance = balance - $1 WHERE user_id = $2',
            [transaction.amount, transaction.buyer_id]);

          // Record in merchant wallet ledger
          const merchantWalletResult = await db.query('SELECT id FROM wallets WHERE user_id = $1', [transaction.merchant_id]);
          if (merchantWalletResult.rows[0]) {
            const walletId = merchantWalletResult.rows[0].id;
            const balanceResult = await db.query('SELECT balance FROM wallets WHERE id = $1', [walletId]);
            const balanceBefore = parseFloat(balanceResult.rows[0]?.balance || 0);
            const balanceAfter = balanceBefore + parseFloat(transaction.amount);
            await db.query(
              `INSERT INTO wallet_ledger (id, wallet_id, type, amount, balance_before, balance_after, reference, description, created_at)
               VALUES ($1, $2, 'payment', $3, $4, $5, $6, $7, $8)`,
              [generateId(), walletId, transaction.amount, balanceBefore, balanceAfter, ref, `Payment from ${transaction.buyer_id}`, new Date().toISOString()]
            );
          }

          // Record in buyer wallet ledger
          const buyerWalletResult = await db.query('SELECT id FROM wallets WHERE user_id = $1', [transaction.buyer_id]);
          if (buyerWalletResult.rows[0]) {
            const walletId = buyerWalletResult.rows[0].id;
            const balanceResult = await db.query('SELECT balance FROM wallets WHERE id = $1', [walletId]);
            const balanceBefore = parseFloat(balanceResult.rows[0]?.balance || 0);
            const balanceAfter = balanceBefore - parseFloat(transaction.amount);
            await db.query(
              `INSERT INTO wallet_ledger (id, wallet_id, type, amount, balance_before, balance_after, reference, description, created_at)
               VALUES ($1, $2, 'payment', $3, $4, $5, $6, $7, $8)`,
              [generateId(), walletId, transaction.amount, balanceBefore, balanceAfter, ref, `Payment to ${transaction.merchant_name || transaction.merchant_id}`, new Date().toISOString()]
            );
          }

          console.log(`Payment completed via callback: ${ref}, merchant credited ₦${transaction.amount}, buyer debited ₦${transaction.amount}`);
        }

        res.send(`<!DOCTYPE html><html><head><title>Payment Successful</title>
          <style>body{font-family:Arial,sans-serif;text-align:center;padding:50px;background:#f5f5f5}
          .container{max-width:400px;margin:0 auto;background:white;padding:40px;border-radius:16px;box-shadow:0 4px 12px rgba(0,0,0,0.1)}
          .check{width:80px;height:80px;background:#4CAF50;border-radius:50%;display:inline-flex;align-items:center;justify-content:center;color:white;font-size:40px;margin-bottom:20px}
          .ref{color:#666;font-size:14px;margin-top:20px}</style></head>
          <body><div class="container"><div class="check">&#10003;</div>
          <h1 style="color:#4CAF50">Payment Successful!</h1>
          <p>Your transaction has been completed.</p>
          <p class="ref">Reference: ${ref}</p>
          <p>Amount: ₦${verifyData.amount / 100}</p>
          <p>Redirecting back to the app...</p></div>
          <script>setTimeout(()=>{window.location.href='${deepLink}';},3000);</script>
          </body></html>`);
      } else {
        // Payment failed or non-success status
        const paystackStatus = (verifyData.status || '').toLowerCase();
        const failedDeepLink = `qrpay://payment/failed?reference=${ref}&status=${encodeURIComponent(paystackStatus)}`;
        res.send(`<!DOCTYPE html><html><head><title>Payment Failed</title>
          <style>body{font-family:Arial,sans-serif;text-align:center;padding:50px;background:#f5f5f5}
          .container{max-width:400px;margin:0 auto;background:white;padding:40px;border-radius:16px;box-shadow:0 4px 12px rgba(0,0,0,0.1)}</style></head>
          <body><div class="container">
          <h1 style="color:#f44336">Payment Failed</h1>
          <p>Your payment was not completed.</p>
          <p>Please return to the app to try again.</p></div>
          <script>setTimeout(()=>{window.location.href='${failedDeepLink}';},5000);</script>
          </body></html>`);
      }
    } else {
      // All verification attempts failed — redirect back to app so it can retry
      console.error(`Paystack callback: all 3 verify attempts failed for ${ref}`);
      res.send(`<!DOCTYPE html><html><head><title>Verifying Payment</title>
        <style>body{font-family:Arial,sans-serif;text-align:center;padding:50px;background:#f5f5f5}
        .container{max-width:400px;margin:0 auto;background:white;padding:40px;border-radius:16px;box-shadow:0 4px 12px rgba(0,0,0,0.1)}
        .spinner{width:40px;height:40px;border:4px solid #ddd;border-top:4px solid #4CAF50;border-radius:50%;animation:spin 1s linear infinite;margin:20px auto}
        @keyframes spin{to{transform:rotate(360deg)}}</style></head>
        <body><div class="container">
        <div class="spinner"></div>
        <h2 style="color:#333">Processing Payment</h2>
        <p>Your payment is being verified. Please return to the app to confirm.</p>
        <p style="color:#666;font-size:12px">Reference: ${ref}</p></div>
        <script>setTimeout(()=>{window.location.href='${deepLink}';},3000);</script>
        </body></html>`);
    }
  } else {
    res.send(`<!DOCTYPE html><html><head><title>Payment Cancelled</title>
      <style>body{font-family:Arial,sans-serif;text-align:center;padding:50px;background:#f5f5f5}
      .container{max-width:400px;margin:0 auto;background:white;padding:40px;border-radius:16px;box-shadow:0 4px 12px rgba(0,0,0,0.1)}</style></head>
      <body><div class="container"><h1 style="color:#f44336">Payment Cancelled</h1>
      <p>No payment reference was provided.</p>
      <p>Please return to the app.</p></div>
      <script>setTimeout(()=>{window.location.href='qrpay://payment/success';},5000);</script>
      </body></html>`);
  }
});

// Verify Paystack payment status (called by Flutter app after returning from Paystack)
app.get('/api/v1/payments/paystack/verify/:reference', async (req, res) => {
  const { reference } = req.params;

  try {
    const txnResult = await db.query('SELECT * FROM transactions WHERE reference = $1', [reference]);
    const transaction = txnResult.rows[0];

    if (!transaction) {
      return res.status(404).json({ success: false, message: 'Transaction not found' });
    }

    // If already completed (e.g. Paystack callback already credited the merchant), return success
    if (transaction.status === 'completed') {
      return res.json({
        success: true,
        status: 'completed',
        amount: parseFloat(transaction.amount),
        merchant_id: transaction.merchant_id,
        merchant_name: transaction.merchant_name,
        reference: transaction.reference,
        completed_at: transaction.completed_at,
      });
    }

    // If still pending, verify with Paystack (with retry and timeout)
    let verifyData;
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        const verifyResponse = await axios.get(
          `${PAYSTACK_BASE_URL}/transaction/verify/${reference}`,
          {
            headers: { Authorization: `Bearer ${PAYSTACK_SECRET_KEY}` },
            timeout: 15000,
          }
        );
        verifyData = verifyResponse.data.data;
        console.log(`Paystack verify result for ${reference}: status=${verifyData.status}`);
        break;
      } catch (axiosErr) {
        console.error(`Paystack verify attempt ${attempt}/${3} failed:`, axiosErr.code || axiosErr.message);
        if (attempt < 3) {
          await new Promise(r => setTimeout(r, 2000));
        } else {
          return res.json({
            success: false,
            status: 'pending_verification',
            message: 'Could not verify payment with Paystack right now. The payment may still be processing. Tap "Verify Payment" to try again.',
          });
        }
      }
    }

    const paystackStatus = (verifyData.status || '').toLowerCase();

    if (paystackStatus === 'success') {
      // Update transaction status
      await db.query("UPDATE transactions SET status = 'completed', completed_at = $1 WHERE reference = $2",
        [new Date().toISOString(), reference]);

      // Credit merchant
      await db.query('UPDATE wallets SET balance = balance + $1 WHERE user_id = $2',
        [transaction.amount, transaction.merchant_id]);

      // Debit buyer
      await db.query('UPDATE wallets SET balance = balance - $1 WHERE user_id = $2',
        [transaction.amount, transaction.buyer_id]);

      // Record in merchant wallet ledger
      const merchantWalletResult = await db.query('SELECT id FROM wallets WHERE user_id = $1', [transaction.merchant_id]);
      if (merchantWalletResult.rows[0]) {
        const walletId = merchantWalletResult.rows[0].id;
        const balanceResult = await db.query('SELECT balance FROM wallets WHERE id = $1', [walletId]);
        const balanceBefore = parseFloat(balanceResult.rows[0]?.balance || 0);
        const balanceAfter = balanceBefore + parseFloat(transaction.amount);
        await db.query(
          `INSERT INTO wallet_ledger (id, wallet_id, type, amount, balance_before, balance_after, reference, description, created_at)
           VALUES ($1, $2, 'payment', $3, $4, $5, $6, $7, $8)`,
          [generateId(), walletId, transaction.amount, balanceBefore, balanceAfter, reference, `Payment from ${transaction.buyer_id}`, new Date().toISOString()]
        );
      }

      // Record in buyer wallet ledger
      const buyerWalletResult = await db.query('SELECT id FROM wallets WHERE user_id = $1', [transaction.buyer_id]);
      if (buyerWalletResult.rows[0]) {
        const walletId = buyerWalletResult.rows[0].id;
        const balanceResult = await db.query('SELECT balance FROM wallets WHERE id = $1', [walletId]);
        const balanceBefore = parseFloat(balanceResult.rows[0]?.balance || 0);
        const balanceAfter = balanceBefore - parseFloat(transaction.amount);
        await db.query(
          `INSERT INTO wallet_ledger (id, wallet_id, type, amount, balance_before, balance_after, reference, description, created_at)
           VALUES ($1, $2, 'payment', $3, $4, $5, $6, $7, $8)`,
          [generateId(), walletId, transaction.amount, balanceBefore, balanceAfter, reference, `Payment to ${transaction.merchant_name || transaction.merchant_id}`, new Date().toISOString()]
        );
      }

      console.log(`Payment completed via verify endpoint: ${reference}, merchant credited ₦${transaction.amount}, buyer debited ₦${transaction.amount}`);

      return res.json({
        success: true,
        status: 'completed',
        amount: parseFloat(transaction.amount),
        merchant_id: transaction.merchant_id,
        merchant_name: transaction.merchant_name,
        reference: transaction.reference,
        completed_at: new Date().toISOString(),
      });
    } else if (paystackStatus === 'processing') {
      // Payment is still being processed (e.g. bank transfer pending confirmation)
      return res.json({
        success: false,
        status: 'processing',
        message: 'Your payment is still being processed. This can take a few minutes for bank transfers. Please try again shortly.',
      });
    } else {
      // Payment failed, was abandoned, or has another status
      return res.json({
        success: false,
        status: paystackStatus || transaction.status,
        message: paystackStatus === 'abandoned'
          ? 'The payment was not completed. Please try making the payment again.'
          : paystackStatus === 'failed'
          ? 'The payment failed. Please try again or use a different payment method.'
          : 'Payment has not been completed yet. Please complete the payment on the Paystack page and try again.',
      });
    }
  } catch (err) {
    console.error('Payment verify error:', err.response?.data || err.message);
    return res.status(500).json({ success: false, message: 'Failed to verify payment. Please try again.' });
  }
});

app.post('/api/v1/payments/paystack/webhook', async (req, res) => {
  const event = req.body;
  console.log('Paystack webhook received:', event.event);

  if (event.event === 'charge.success') {
    const reference = event.data.reference;
    const txnResult = await db.query('SELECT * FROM transactions WHERE reference = $1', [reference]);
    const transaction = txnResult.rows[0];

    if (transaction && transaction.status === 'pending') {
      await db.query("UPDATE transactions SET status = 'completed', completed_at = $1 WHERE reference = $2",
        [new Date().toISOString(), reference]);
      await db.query('UPDATE wallets SET balance = balance + $1 WHERE user_id = $2',
        [transaction.amount, transaction.merchant_id]);
      await db.query('UPDATE wallets SET balance = balance - $1 WHERE user_id = $2',
        [transaction.amount, transaction.buyer_id]);

      // Record in merchant wallet ledger
      const merchantWalletResult = await db.query('SELECT id FROM wallets WHERE user_id = $1', [transaction.merchant_id]);
      if (merchantWalletResult.rows[0]) {
        const walletId = merchantWalletResult.rows[0].id;
        const balanceResult = await db.query('SELECT balance FROM wallets WHERE id = $1', [walletId]);
        const balanceBefore = parseFloat(balanceResult.rows[0]?.balance || 0);
        const balanceAfter = balanceBefore + parseFloat(transaction.amount);
        await db.query(
          `INSERT INTO wallet_ledger (id, wallet_id, type, amount, balance_before, balance_after, reference, description, created_at)
           VALUES ($1, $2, 'payment', $3, $4, $5, $6, $7, $8)`,
          [generateId(), walletId, transaction.amount, balanceBefore, balanceAfter, reference, `Payment from ${transaction.buyer_id}`, new Date().toISOString()]
        );
      }

      // Record in buyer wallet ledger
      const buyerWalletResult = await db.query('SELECT id FROM wallets WHERE user_id = $1', [transaction.buyer_id]);
      if (buyerWalletResult.rows[0]) {
        const walletId = buyerWalletResult.rows[0].id;
        const balanceResult = await db.query('SELECT balance FROM wallets WHERE id = $1', [walletId]);
        const balanceBefore = parseFloat(balanceResult.rows[0]?.balance || 0);
        const balanceAfter = balanceBefore - parseFloat(transaction.amount);
        await db.query(
          `INSERT INTO wallet_ledger (id, wallet_id, type, amount, balance_before, balance_after, reference, description, created_at)
           VALUES ($1, $2, 'payment', $3, $4, $5, $6, $7, $8)`,
          [generateId(), walletId, transaction.amount, balanceBefore, balanceAfter, reference, `Payment to ${transaction.merchant_name || transaction.merchant_id}`, new Date().toISOString()]
        );
      }

      console.log(`Webhook: Payment ${reference} completed, merchant credited ₦${transaction.amount}, buyer debited ₦${transaction.amount}`);
    }
  }

  res.status(200).send('OK');
});

const PORT = parseInt(process.env.PORT || '3000');
app.listen(PORT, '0.0.0.0', () => {
  console.log(`PostgreSQL backend server running on http://0.0.0.0:${PORT}`);
  console.log(`API base URL: http://0.0.0.0:${PORT}/api/v1`);
});
