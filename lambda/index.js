'use strict';

const { ECSClient, RunTaskCommand } = require('@aws-sdk/client-ecs');

const ecs = new ECSClient({ region: process.env.AWS_REGION || 'us-east-1' });

// ── Config from Lambda environment variables ──────────────────────────────────
const {
  ECS_CLUSTER,
  ECS_TASK_DEFINITION,
  ECS_CONTAINER_NAME,
  ECS_LAUNCH_TYPE = 'FARGATE',
  ECS_SUBNET_IDS = '',
  ECS_SECURITY_GROUP_IDS = '',
  ECS_ASSIGN_PUBLIC_IP = 'ENABLED',
  S3_BUCKET = 'lensart-files',
  OUTPUT_PREFIX = 'converted',
  WEBHOOK_URL,
  WEBHOOK_SECRET = '',
} = process.env;

/**
 * Parses an S3 ObjectCreated event and launches an ECS Fargate task
 * that will download the USDZ, convert it to GLB, and upload it back.
 *
 * S3 key format expected: "models/<uuid>.usdz"
 * Only .usdz files under the "models/" prefix are processed.
 *
 * @param {import('aws-lambda').S3Event} event
 */
exports.handler = async (event) => {
  console.log('[lambda] Received event:', JSON.stringify(event, null, 2));

  const results = [];

  for (const record of event.Records) {
    // Decode the S3 key (AWS URL-encodes spaces as '+')
    const s3Key = decodeURIComponent(record.s3.object.key.replace(/\+/g, ' '));
    const bucket = record.s3.bucket.name;

    console.log(`[lambda] Processing: s3://${bucket}/${s3Key}`);

    // Guard: only process USDZ files under models/
    if (!s3Key.startsWith('models/') || !s3Key.endsWith('.usdz')) {
      console.log(`[lambda] Skipping non-USDZ or wrong prefix: ${s3Key}`);
      results.push({ s3Key, skipped: true });
      continue;
    }

    try {
      const taskArn = await runEcsTask({ bucket, s3Key });
      console.log(`[lambda] ECS task launched: ${taskArn}`);
      results.push({ s3Key, taskArn });
    } catch (err) {
      console.error(`[lambda] Failed to launch ECS task for ${s3Key}:`, err.message);
      // Re-throw so Lambda marks the invocation as failed and retries
      throw err;
    }
  }

  return { statusCode: 200, results };
};

/**
 * Calls ECS RunTask with environment overrides for the converter container.
 *
 * @param {{ bucket: string, s3Key: string }} params
 * @returns {Promise<string>} Task ARN
 */
async function runEcsTask({ bucket, s3Key }) {
  const subnets = ECS_SUBNET_IDS.split(',').map((s) => s.trim()).filter(Boolean);
  const securityGroups = ECS_SECURITY_GROUP_IDS.split(',').map((s) => s.trim()).filter(Boolean);

  const command = new RunTaskCommand({
    cluster: ECS_CLUSTER,
    taskDefinition: ECS_TASK_DEFINITION,
    launchType: ECS_LAUNCH_TYPE,

    networkConfiguration: {
      awsvpcConfiguration: {
        subnets,
        securityGroups,
        assignPublicIp: ECS_ASSIGN_PUBLIC_IP,
      },
    },

    // Override the container env vars so each task knows which file to process
    overrides: {
      containerOverrides: [
        {
          name: ECS_CONTAINER_NAME,
          environment: [
            { name: 'S3_BUCKET',       value: bucket },
            { name: 'S3_KEY',          value: s3Key },
            { name: 'OUTPUT_PREFIX',   value: OUTPUT_PREFIX },
            { name: 'WEBHOOK_URL',     value: WEBHOOK_URL || '' },
            { name: 'WEBHOOK_SECRET',  value: WEBHOOK_SECRET },
          ],
        },
      ],
    },
  });

  const response = await ecs.send(command);

  if (response.failures && response.failures.length > 0) {
    const reasons = response.failures.map((f) => `${f.arn}: ${f.reason}`).join(', ');
    throw new Error(`ECS RunTask failures: ${reasons}`);
  }

  const taskArn = response.tasks?.[0]?.taskArn;
  if (!taskArn) throw new Error('ECS RunTask returned no task ARN');

  return taskArn;
}
