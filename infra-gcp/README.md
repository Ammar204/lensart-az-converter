# GCP deployment (Cloud Run Job)

Temporary GCP home for the converter while the rest of the infra is on GCP. The
AWS deployment is untouched and still deployable — it lives on the `main`
branch (`infra/` Terraform + `lambda/`). This branch (`gcp`) is the GCP port.

## Pipeline

```
GCS finalize on lensart-files-prod
  → Eventarc trigger (lensart-converter-usdz)
    → Workflow (lensart-converter-dispatch)   ← filters models/*.usdz
      → Cloud Run Job (lensart-converter)     ← env overrides GCS_BUCKET/GCS_KEY
        → download → usd2gltf → upload converted/*.glb → webhook → exit
```

Each hop maps to the AWS design: the Eventarc trigger replaces the S3 bucket
notification, and the Workflow replaces `lambda/index.js`'s `ecs:RunTask` call.
The container is unchanged in shape — it still takes everything from env vars
and exits when finished.

## Deployed resources

| Resource | Name |
|---|---|
| Project / region | `lensart-project` / `asia-south1` |
| Artifact Registry | `asia-south1-docker.pkg.dev/lensart-project/lensart-converter` |
| Cloud Run Job | `lensart-converter` (2 vCPU, 4Gi, 900s timeout, parallelism 1) |
| Job identity | `lensart-converter@lensart-project.iam.gserviceaccount.com` |
| Dispatcher identity | `lensart-converter-wf@lensart-project.iam.gserviceaccount.com` |
| Trigger identity | `lensart-converter-ea@lensart-project.iam.gserviceaccount.com` |
| Workflow | `lensart-converter-dispatch` |
| Eventarc trigger | `lensart-converter-usdz` |

Credentials: the job runs **as an attached service account**, so there is no key
file anywhere. `Storage()` picks it up through Application Default Credentials.

## Deploy

```sh
# 1. Build and push (see the Cloud Build note below — the flags are required)
gcloud builds submit \
  --tag asia-south1-docker.pkg.dev/lensart-project/lensart-converter/converter:<tag> \
  --project=lensart-project --region=asia-south1 \
  --service-account=projects/lensart-project/serviceAccounts/678939585624-compute@developer.gserviceaccount.com \
  --default-buckets-behavior=regional-user-owned-bucket

# 2. Point the job at the new image
terraform -chdir=infra-gcp apply -var image_tag=<tag>
```

`terraform.tfvars` is gitignored and holds `image_tag`, `webhook_url` and
`webhook_secret`.

## Things that will trip you up

**Cloud Build needs an explicit service account.** Google no longer creates the
legacy `<num>@cloudbuild.gserviceaccount.com` agent in new projects, so a plain
`gcloud builds submit` fails with `PERMISSION_DENIED` *even as project owner*.
Hence the `--service-account` and `--default-buckets-behavior` flags above. The
compute SA was granted `logging.logWriter`, `artifactregistry.writer` and
`storage.objectAdmin` to make this work.

**The Workflow's prefix filter is load-bearing.** Eventarc storage triggers can
only filter by *bucket*, not by object prefix. The job writes
`converted/*.glb` back into the bucket it is watching, so without the
`^models/scan_<uuid>[.]usdz$` check in `workflow.yaml` every conversion would
trigger another one forever. Verified: a write to `converted/` invokes the
Workflow, which returns `skipped` and starts no job.

**`run.jobs.runWithOverrides`, not `run.jobs.run`.** `roles/run.invoker` is not
sufficient because the dispatcher passes container overrides. Rather than the
broad `roles/run.developer`, a custom role (`lensartConverterJobRunner`) is
bound *on the job itself*, mirroring the AWS policy that scopes `ecs:RunTask` to
one task-definition ARN.

**Service agents are created lazily.** On a fresh project the first apply fails
with "Workflows service agent does not exist" and a missing
`gs-project-accounts` SA. Fix:

```sh
gcloud storage service-agent --project=lensart-project
TOKEN=$(gcloud auth print-access-token)
for s in workflows eventarc pubsub; do
  curl -sS -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Length: 0" \
    "https://serviceusage.googleapis.com/v1beta1/projects/lensart-project/services/$s.googleapis.com:generateServiceIdentity"
done
```

Then re-apply. Eventarc also needs a minute for its agent's permissions to
propagate — a first-attempt failure there is normal; just apply again.

**Cloud Run `/tmp` is an in-memory tmpfs** and counts against the 4Gi limit,
unlike Fargate's 20GB of real ephemeral disk. The job holds the USDZ and the GLB
at once. If conversions start failing with no clear error, raise `job_memory`
to `8Gi` — no code change needed.

## Rolling back to AWS

Nothing here touches the AWS setup. To go back: check out `main`, apply
`infra/`, and re-enable the S3 bucket notification. Optionally
`terraform -chdir=infra-gcp destroy` to remove the GCP side.
