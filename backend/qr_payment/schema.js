const db = require('./db');

async function initializeDatabase() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS users (
      id VARCHAR(36) PRIMARY KEY,
      email VARCHAR(255) UNIQUE NOT NULL,
      password VARCHAR(255) NOT NULL,
      name VARCHAR(255) NOT NULL,
      phone VARCHAR(50) NOT NULL,
      role VARCHAR(20) NOT NULL DEFAULT 'buyer',
      business_name VARCHAR(255),
      business_address TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      is_active BOOLEAN DEFAULT true,
      password_migration_required BOOLEAN DEFAULT false
    )
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS wallets (
      id VARCHAR(36) PRIMARY KEY,
      user_id VARCHAR(36) UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      balance DECIMAL(15, 2) DEFAULT 0,
      currency VARCHAR(10) DEFAULT 'NGN',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS transactions (
      id VARCHAR(36) PRIMARY KEY,
      reference VARCHAR(100) UNIQUE NOT NULL,
      buyer_id VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      merchant_id VARCHAR(36) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      merchant_name VARCHAR(255),
      amount DECIMAL(15, 2) NOT NULL,
      currency VARCHAR(10) DEFAULT 'NGN',
      status VARCHAR(20) DEFAULT 'pending',
      type VARCHAR(20) DEFAULT 'payment',
      description TEXT,
      paystack_reference VARCHAR(100),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      completed_at TIMESTAMP
    )
  `);

  // Wallet ledger for all balance changes (topups, withdrawals, etc.)
  // This is separate from transactions which tracks buyer-merchant payments
  await db.query(`
    CREATE TABLE IF NOT EXISTS wallet_ledger (
      id VARCHAR(36) PRIMARY KEY,
      wallet_id VARCHAR(36) NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
      type VARCHAR(20) NOT NULL,
      amount DECIMAL(15, 2) NOT NULL,
      balance_before DECIMAL(15, 2) NOT NULL,
      balance_after DECIMAL(15, 2) NOT NULL,
      reference VARCHAR(100) UNIQUE NOT NULL,
      description TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);

  // Migration: Add password_migration_required column if it doesn't exist
  // and mark all existing users as requiring password reset
  try {
    await db.query(`
      ALTER TABLE users ADD COLUMN IF NOT EXISTS password_migration_required BOOLEAN DEFAULT false
    `);
    // Force all existing users to reset password (they have old SHA-256 hashes)
    await db.query(`
      UPDATE users SET password_migration_required = true WHERE password_migration_required = false
    `);
    console.log('Password migration column added and users marked for password reset');
  } catch (err) {
    console.log('Migration note:', err.message);
  }

  // Migration: Add password_migration_required column if it doesn't exist
  // and mark all existing users as requiring password reset
  try {
    await db.query(`
      ALTER TABLE users ADD COLUMN IF NOT EXISTS password_migration_required BOOLEAN DEFAULT false
    `);
    // Force all existing users to reset password (they have old SHA-256 hashes)
    await db.query(`
      UPDATE users SET password_migration_required = true WHERE password_migration_required = false
    `);
    console.log('Password migration column added and users marked for password reset');
  } catch (err) {
    console.log('Migration note:', err.message);
  }

  // Migration: Add avatar_url column to users
  try {
    await db.query(`
      ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url VARCHAR(500)
    `);
    console.log('Avatar URL column added to users');
  } catch (err) {
    console.log('Avatar column migration note:', err.message);
  }

  // Create pins table for secure PIN storage
  await db.query(`
    CREATE TABLE IF NOT EXISTS pins (
      id VARCHAR(36) PRIMARY KEY,
      user_id VARCHAR(36) UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      pin_hash VARCHAR(255) NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
  console.log('Pins table created');

  // Create notification_settings table
  await db.query(`
    CREATE TABLE IF NOT EXISTS notification_settings (
      id VARCHAR(36) PRIMARY KEY,
      user_id VARCHAR(36) UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      sms_money_in BOOLEAN DEFAULT true,
      sms_money_out BOOLEAN DEFAULT true,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
  console.log('Notification settings table created');

  // Create bank_accounts table for merchant withdrawal details
  await db.query(`
    CREATE TABLE IF NOT EXISTS bank_accounts (
      id VARCHAR(36) PRIMARY KEY,
      user_id VARCHAR(36) UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      bank_name VARCHAR(100) NOT NULL,
      account_number VARCHAR(10) NOT NULL,
      account_name VARCHAR(255) NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
  console.log('Bank accounts table created');

  console.log('Database tables initialized');
}

module.exports = { initializeDatabase };
