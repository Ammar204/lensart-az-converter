'use strict';

const { Storage } = require('@google-cloud/storage');
const fs = require('fs');
const path = require('path');
const { pipeline } = require('stream/promises');

/**
 * Downloads a Cloud Storage object to a local temp file.
 *
 * Streams straight to disk rather than buffering — a LiDAR USDZ can be tens of
 * MB and Cloud Run's /tmp is an in-memory tmpfs that counts against the task's
 * memory limit.
 *
 * @param {Storage} storage
 * @param {string} bucket
 * @param {string} key   e.g. "models/scan_<uuid>.usdz"
 * @param {string} destDir  local directory to write the file into
 * @returns {Promise<string>}  absolute path to the downloaded file
 */
async function downloadFromGcs(storage, bucket, key, destDir) {
  const filename = path.basename(key);
  const destPath = path.join(destDir, filename);

  console.log(`[downloader] Downloading gs://${bucket}/${key} → ${destPath}`);

  await pipeline(
    storage.bucket(bucket).file(key).createReadStream(),
    fs.createWriteStream(destPath),
  );

  const { size } = fs.statSync(destPath);
  if (size === 0) throw new Error(`Downloaded object gs://${bucket}/${key} is empty`);

  console.log(`[downloader] Download complete (${destPath}, ${size} bytes)`);
  return destPath;
}

module.exports = { downloadFromGcs };
