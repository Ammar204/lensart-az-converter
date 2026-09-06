'use strict';

const { S3Client } = require('@aws-sdk/client-s3');
const { Upload } = require('@aws-sdk/lib-storage');
const fs = require('fs');
const path = require('path');
const mime = require('mime-types');

/**
 * Uploads a local file to S3 under the given prefix.
 *
 * @param {S3Client} s3
 * @param {string} bucket
 * @param {string} outputPrefix  e.g. "converted"
 * @param {string} filePath      Absolute local path to the .glb file
 * @returns {Promise<string>}  The full S3 key of the uploaded object
 */
async function uploadToS3(s3, bucket, outputPrefix, filePath) {
  const filename = path.basename(filePath);
  const s3Key = `${outputPrefix}/${filename}`;
  const contentType = mime.lookup(filePath) || 'model/gltf-binary';

  console.log(`[uploader] Uploading ${filePath} → s3://${bucket}/${s3Key}`);

  const upload = new Upload({
    client: s3,
    params: {
      Bucket: bucket,
      Key: s3Key,
      Body: fs.createReadStream(filePath),
      ContentType: contentType,
      // Keys are deterministic and reused (converted/scan_<id>.glb), so a
      // re-converted model must not sit behind CloudFront's 24h default TTL.
      CacheControl: 'public, max-age=300',
    },
  });

  upload.on('httpUploadProgress', (progress) => {
    if (progress.total) {
      const pct = ((progress.loaded / progress.total) * 100).toFixed(1);
      console.log(`[uploader] Progress: ${pct}%`);
    }
  });

  await upload.done();

  console.log(`[uploader] Upload complete → s3://${bucket}/${s3Key}`);
  return s3Key;
}

module.exports = { uploadToS3 };
