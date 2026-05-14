'use strict';

const os = require('os');
const path = require('path');
const fs = require('fs');
const { S3Client } = require('@aws-sdk/client-s3');

const { downloadFromS3 } = require('./downloader');
const { convertUsdzToGlb } = require('./converter');
const { uploadToS3 } = require('./uploader');
const { fireWebhook } = require('./webhook');

// ── Env vars (injected by ECS task override from Lambda) ─────────────────────
const {
  AWS_REGION = 'us-east-1',
  AWS_ACCESS_KEY_ID,
  AWS_SECRET_ACCESS_KEY,
  S3_BUCKET,
  S3_KEY,                          // e.g. "models/abc-123.usdz"
  OUTPUT_PREFIX = 'converted',     // GLB lands at "converted/<uuid>.glb"
  WEBHOOK_URL,
  WEBHOOK_SECRET = '',
} = process.env;

// Validation
if (!S3_BUCKET || !S3_KEY) {
  console.error('[main] FATAL: S3_BUCKET and S3_KEY must be set');
  process.exit(1);
}

if (!WEBHOOK_URL) {
  console.warn('[main] WARNING: WEBHOOK_URL not set — backend will not be notified');
}

// Extract scanId from key like "models/scan_<uuid>.usdz"
const scanIdMatch = S3_KEY.match(/scan_([0-9a-f-]{36})\.usdz$/i);
if (!scanIdMatch) {
  console.error(`[main] FATAL: cannot extract scanId from S3_KEY="${S3_KEY}" (expected models/scan_<uuid>.usdz)`);
  process.exit(1);
}
const SCAN_ID = scanIdMatch[1];

// ── S3 client ─────────────────────────────────────────────────────────────────
const s3ClientConfig = { region: AWS_REGION };

// Use explicit credentials if provided; otherwise fall back to IAM task role
if (AWS_ACCESS_KEY_ID && AWS_SECRET_ACCESS_KEY) {
  s3ClientConfig.credentials = {
    accessKeyId: AWS_ACCESS_KEY_ID,
    secretAccessKey: AWS_SECRET_ACCESS_KEY,
  };
}

const s3 = new S3Client(s3ClientConfig);

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'lensart-'));
  let glbS3Key = null;

  console.log(`[main] Starting conversion job`);
  console.log(`[main]   Source : s3://${S3_BUCKET}/${S3_KEY}`);
  console.log(`[main]   Output : s3://${S3_BUCKET}/${OUTPUT_PREFIX}/`);
  console.log(`[main]   Tmp dir: ${tmpDir}`);

  try {
    // 1️⃣  Download USDZ
    const usdzPath = await downloadFromS3(s3, S3_BUCKET, S3_KEY, tmpDir);

    // 2️⃣  Convert USDZ → GLB
    const glbPath = await convertUsdzToGlb(usdzPath);

    // 3️⃣  Upload GLB
    glbS3Key = await uploadToS3(s3, S3_BUCKET, OUTPUT_PREFIX, glbPath);

    console.log(`[main] ✅ Job complete. GLB at s3://${S3_BUCKET}/${glbS3Key}`);

    // 4️⃣  Notify backend
    if (WEBHOOK_URL) {
      await fireWebhook({
        webhookUrl: WEBHOOK_URL,
        webhookSecret: WEBHOOK_SECRET,
        scanId: SCAN_ID,
        status: 'completed',
      });
    }
  } catch (err) {
    console.error('[main] ❌ Job failed:', err.message);

    if (WEBHOOK_URL) {
      await fireWebhook({
        webhookUrl: WEBHOOK_URL,
        webhookSecret: WEBHOOK_SECRET,
        scanId: SCAN_ID,
        status: 'failed',
        error: err.message,
      });
    }

    process.exit(1);
  } finally {
    // Clean up temp files
    try {
      fs.rmSync(tmpDir, { recursive: true, force: true });
      console.log('[main] Temp dir cleaned up');
    } catch (_) {}
  }
}

main();
