'use strict';

const { execFile } = require('child_process');
const path = require('path');
const util = require('util');

const execFileAsync = util.promisify(execFile);

/**
 * Converts a USDZ file to GLB using the `usd2gltf` Python CLI tool
 * (installed in the Docker image via `pip install usd2gltf`).
 *
 * Output file is written to the same directory as the input,
 * with the same basename but a `.glb` extension.
 *
 * @param {string} usdzPath  Absolute path to the input .usdz file
 * @returns {Promise<string>}  Absolute path to the output .glb file
 */
async function convertUsdzToGlb(usdzPath) {
  const dir = path.dirname(usdzPath);
  const basename = path.basename(usdzPath, '.usdz');
  const glbPath = path.join(dir, `${basename}.glb`);

  console.log(`[converter] Converting ${usdzPath} → ${glbPath}`);

  try {
    // usd2gltf -i <input.usdz> -o <output.glb>
    const { stdout, stderr } = await execFileAsync('usd2gltf', [
      '-i', usdzPath,
      '-o', glbPath,
    ], {
      timeout: 5 * 60 * 1000, // 5-minute safety cap
    });

    if (stdout) console.log('[converter] stdout:', stdout);
    if (stderr) console.warn('[converter] stderr:', stderr);
  } catch (err) {
    throw new Error(`Conversion failed: ${err.message}`);
  }

  console.log(`[converter] Conversion complete → ${glbPath}`);
  return glbPath;
}

module.exports = { convertUsdzToGlb };
