'use strict';

const os = require('os');
const path = require('path');
const fs = require('fs');
const { Storage } = require('@google-cloud/storage');

const { downloadFromGcs } = require('./downloader');
const { convertUsdzToGlb } = require('./converter');
const { uploadToGcs } = require('./uploader');
const { fireWebhook } = require('./webhook');

// ── Env vars (GCS_BUCKET/GCS_KEY injected per-execution by the Workflow) ─────
const {
  GOOGLE_CLOUD_PROJECT,
  GCS_BUCKET,
  GCS_KEY,                         // e.g. "models/scan_<uuid>.usdz"
  OUTPUT_PREFIX = 'converted',     // GLB lands at "converted/scan_<uuid>.glb"
  WEBHOOK_URL,
  WEBHOOK_SECRET = '',
} = process.env;

// Validation
if (!GCS_BUCKET || !GCS_KEY) {
  console.error('[main] FATAL: GCS_BUCKET and GCS_KEY must be set');
  process.exit(1);
}

if (!WEBHOOK_URL) {
  console.warn('[main] WARNING: WEBHOOK_URL not set — backend will not be notified');
}

// Extract scanId from key like "models/scan_<uuid>.usdz".
// Note: if this fails there is no scanId to report against, so the backend
// cannot be told. The scan stays `pending` — hence the loud log.
const scanIdMatch = GCS_KEY.match(/scan_([0-9a-f-]{36})\.usdz$/i);
if (!scanIdMatch) {
  console.error(`[main] FATAL: cannot extract scanId from GCS_KEY="${GCS_KEY}" (expected models/scan_<uuid>.usdz)`);
  process.exit(1);
}
const SCAN_ID = scanIdMatch[1];

// ── Storage client ────────────────────────────────────────────────────────────
// Credentials come from Application Default Credentials: on Cloud Run the
// attached service account is picked up from the metadata server, so there is
// no key file to ship. Locally, GOOGLE_APPLICATION_CREDENTIALS is honoured by
// the library without any code here.
const storage = new Storage(
  GOOGLE_CLOUD_PROJECT ? { projectId: GOOGLE_CLOUD_PROJECT } : {},
);

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'lensart-'));
  let glbKey = null;

  console.log(`[main] Starting conversion job`);
  console.log(`[main]   Source : gs://${GCS_BUCKET}/${GCS_KEY}`);
  console.log(`[main]   Output : gs://${GCS_BUCKET}/${OUTPUT_PREFIX}/`);
  console.log(`[main]   Tmp dir: ${tmpDir}`);

  try {
    // 1️⃣  Download USDZ
    const usdzPath = await downloadFromGcs(storage, GCS_BUCKET, GCS_KEY, tmpDir);

    // 2️⃣  Convert USDZ → GLB
    const glbPath = await convertUsdzToGlb(usdzPath);

    // 3️⃣  Upload GLB
    glbKey = await uploadToGcs(storage, GCS_BUCKET, OUTPUT_PREFIX, glbPath);

    console.log(`[main] ✅ Job complete. GLB at gs://${GCS_BUCKET}/${glbKey}`);

    // 4️⃣  Notify backend.
    // The conversion itself succeeded, so we must NOT report `failed` here —
    // that would overwrite a good result. But a silently undelivered webhook
    // leaves the scan `pending` forever, so surface it as a failed execution.
    if (WEBHOOK_URL) {
      const delivered = await fireWebhook({
        webhookUrl: WEBHOOK_URL,
        webhookSecret: WEBHOOK_SECRET,
        scanId: SCAN_ID,
        status: 'completed',
      });
      if (!delivered) {
        console.error(
          `[main] Conversion succeeded but the webhook never reached the backend. ` +
          `Scan ${SCAN_ID} will stay "pending" until it is retried.`,
        );
        process.exitCode = 1;
      }
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
