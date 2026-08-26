'use strict';

const axios = require('axios');
const crypto = require('crypto');

const MAX_ATTEMPTS = 4;
const BASE_DELAY_MS = 500;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Fires a POST webhook to the NestJS backend once conversion is done.
 *
 * `webhookUrl` is used VERBATIM as the POST target — nothing is appended.
 * It must be the full endpoint, e.g. https://api.example.com/webhook/scan-uploaded
 *
 * Body:
 * {
 *   "scanId": "<uuid>",
 *   "status": "completed" | "failed",
 *   "error":  "<message>"   // only on failure
 * }
 *
 * Includes an HMAC-SHA256 signature header so the backend can verify authenticity.
 * The signature is computed over the exact JSON string sent, which axios
 * reproduces byte-for-byte, so the backend's rawBody check matches.
 *
 * Retries on network errors and 5xx with exponential backoff. A 4xx is not
 * retried — it means the request is wrong, and repeating it will not help.
 *
 * @param {object} params
 * @param {string} params.webhookUrl     full endpoint URL
 * @param {string} params.webhookSecret
 * @param {string} params.scanId         UUID parsed from the object key
 * @param {'completed'|'failed'} params.status
 * @param {string} [params.error]
 * @returns {Promise<boolean>}  true if delivered, false if it never got through
 */
async function fireWebhook({ webhookUrl, webhookSecret, scanId, status, error }) {
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

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    console.log(`[webhook] Firing ${status} → ${webhookUrl} (attempt ${attempt}/${MAX_ATTEMPTS})`);
    try {
      await axios.post(webhookUrl, body, {
        headers: {
          'Content-Type': 'application/json',
          'X-LensArt-Signature': `sha256=${signature}`,
        },
        timeout: 10_000,
      });
      console.log('[webhook] Delivered successfully');
      return true;
    } catch (err) {
      const code = err.response?.status;

      // A 4xx will not fix itself — fail fast rather than burning retries.
      if (code && code >= 400 && code < 500) {
        console.error(`[webhook] Delivery failed with ${code} (not retrying):`, err.message);
        return false;
      }

      const last = attempt === MAX_ATTEMPTS;
      console.error(
        `[webhook] Delivery attempt ${attempt} failed${code ? ` (${code})` : ''}:`,
        err.message,
      );
      if (last) return false;

      const delay = BASE_DELAY_MS * 2 ** (attempt - 1);
      await sleep(delay);
    }
  }

  return false;
}

module.exports = { fireWebhook };
