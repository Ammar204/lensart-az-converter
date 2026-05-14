'use strict';

const axios = require('axios');
const crypto = require('crypto');

/**
 * Fires a POST webhook to the NestJS backend once conversion is done.
 *
 * Final URL: `${webhookUrl}/${scanId}/conversion-complete` (webhookUrl is treated as a base).
 *
 * Body:
 * {
 *   "status": "completed" | "failed",
 *   "error":  "<message>"   // only on failure
 * }
 *
 * Includes an HMAC-SHA256 signature header so the backend can verify authenticity.
 *
 * @param {object} params
 * @param {string} params.webhookUrl     base URL, e.g. https://api.example.com/scans
 * @param {string} params.webhookSecret
 * @param {string} params.scanId         UUID parsed from the S3 key
 * @param {'completed'|'failed'} params.status
 * @param {string} [params.error]
 */
async function fireWebhook({ webhookUrl, webhookSecret, scanId, status, error }) {
  const url = webhookUrl;

  const body = {
    scanId,
    status,
    ...(error ? { error } : {}),
  };

  const bodyStr = JSON.stringify(body);

  // HMAC-SHA256 signature so the backend can verify this is us
  const signature = crypto
    .createHmac('sha256', webhookSecret || '')
    .update(bodyStr)
    .digest('hex');

  console.log(`[webhook] Firing ${status} → ${url}`);

  try {
    await axios.post(url, body, {
      headers: {
        'Content-Type': 'application/json',
        'X-LensArt-Signature': `sha256=${signature}`,
      },
      timeout: 10_000,
    });
    console.log('[webhook] Delivered successfully');
  } catch (err) {
    // Don't crash the container over a webhook failure — just log it
    console.error('[webhook] Delivery failed:', err.message);
  }
}

module.exports = { fireWebhook };
