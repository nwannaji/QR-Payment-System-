const axios = require('axios');

const AFRICAS_TALKING_API_KEY = process.env.AFRICAS_TALKING_API_KEY;
const AFRICAS_TALKING_USERNAME = process.env.AFRICAS_TALKING_USERNAME || 'sandbox';
const SMS_SENDER = process.env.SMS_SENDER || 'QRPay';

/**
 * Send SMS via Africa's Talking or mock in development.
 * @param {string} phoneNumber - Nigerian phone number (e.g., +2348012345678)
 * @param {string} message - SMS message content
 * @returns {Promise<{success: boolean, mock?: boolean, data?: any, error?: string}>}
 */
async function sendSMS(phoneNumber, message) {
  // Normalize phone number
  let normalizedPhone = phoneNumber.trim();
  if (normalizedPhone.startsWith('0')) {
    normalizedPhone = '+234' + normalizedPhone.substring(1);
  }
  if (!normalizedPhone.startsWith('+')) {
    normalizedPhone = '+' + normalizedPhone;
  }

  // Mock in development
  if (process.env.NODE_ENV !== 'production' || !AFRICASTALKING_API_KEY) {
    console.log(`[SMS MOCK] To: ${normalizedPhone}`);
    console.log(`[SMS MOCK] Message: ${message}`);
    console.log(`[SMS MOCK] API Key present: ${!!AFRICASTALKING_API_KEY}, Env: ${process.env.NODE_ENV}`);
    return { success: true, mock: true };
  }

  // Production: Use Africa's Talking API
  try {
    const response = await axios.post(
      'https://api.africastalking.com/version1/messaging',
      new URLSearchParams({
        username: AFRICAS_TALKING_USERNAME,
        to: normalizedPhone,
        message: message,
        from: SMS_SENDER,
      }),
      {
        headers: {
          'ApiKey': AFRICASTALKING_API_KEY,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      }
    );
    return { success: true, data: response.data };
  } catch (err) {
    console.error('SMS send failed:', err.response?.data || err.message);
    return { success: false, error: err.response?.data?.message || err.message };
  }
}

/**
 * Send money-in notification SMS.
 * @param {string} phoneNumber - Recipient's phone
 * @param {string} amount - Amount received (e.g., "₦1,000")
 * @param {string} senderName - Name of the sender
 * @param {string} reference - Transaction reference
 */
async function sendMoneyInSMS(phoneNumber, amount, senderName, reference) {
  const message = `QRPay: You received ${amount} from ${senderName}. Ref: ${reference}`;
  return sendSMS(phoneNumber, message);
}

/**
 * Send money-out notification SMS.
 * @param {string} phoneNumber - Sender's phone
 * @param {string} amount - Amount paid (e.g., "₦1,000")
 * @param {string} recipientName - Name of the recipient
 * @param {string} reference - Transaction reference
 */
async function sendMoneyOutSMS(phoneNumber, amount, recipientName, reference) {
  const message = `QRPay: You paid ${amount} to ${recipientName}. Ref: ${reference}`;
  return sendSMS(phoneNumber, message);
}

module.exports = { sendSMS, sendMoneyInSMS, sendMoneyOutSMS };
