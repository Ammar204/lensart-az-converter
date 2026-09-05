'use strict';

const { S3Client, GetObjectCommand } = require('@aws-sdk/client-s3');
const fs = require('fs');
const path = require('path');
const { pipeline } = require('stream/promises');

/**
 * Downloads an S3 object to a local temp file.
 * @param {S3Client} s3
 * @param {string} bucket
 * @param {string} key   e.g. "models/scan_<uuid>.usdz"
 * @param {string} destDir  local directory to write the file into
 * @returns {Promise<string>}  absolute path to the downloaded file
 */
async function downloadFromS3(s3, bucket, key, destDir) {
  const filename = path.basename(key);
  const destPath = path.join(destDir, filename);

  console.log(`[downloader] Downloading s3://${bucket}/${key} → ${destPath}`);

  const { Body } = await s3.send(
    new GetObjectCommand({ Bucket: bucket, Key: key }),
  );

  if (!Body) throw new Error('S3 GetObject returned an empty body');

  await pipeline(Body, fs.createWriteStream(destPath));

  console.log(`[downloader] Download complete (${destPath})`);
  return destPath;
}

module.exports = { downloadFromS3 };
