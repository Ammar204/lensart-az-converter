'use strict';

const { Storage } = require('@google-cloud/storage');
const path = require('path');
const mime = require('mime-types');

/**
 * Uploads a local file to Cloud Storage under the given prefix.
 *
 * @param {Storage} storage
 * @param {string} bucket
 * @param {string} outputPrefix  e.g. "converted"
 * @param {string} filePath      Absolute local path to the .glb file
 * @returns {Promise<string>}  The full object key of the uploaded file
 */
async function uploadToGcs(storage, bucket, outputPrefix, filePath) {
  const filename = path.basename(filePath);
  const objectKey = `${outputPrefix}/${filename}`;
  const contentType = mime.lookup(filePath) || 'model/gltf-binary';

  console.log(`[uploader] Uploading ${filePath} → gs://${bucket}/${objectKey}`);

  await storage.bucket(bucket).upload(filePath, {
    destination: objectKey,
    contentType,
    // Resumable uploads negotiate a session first, which is wasted work for a
    // file this size written once from a short-lived job.
    resumable: false,
  });

  console.log(`[uploader] Upload complete → gs://${bucket}/${objectKey}`);
  return objectKey;
}

module.exports = { uploadToGcs };
