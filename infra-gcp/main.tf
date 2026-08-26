terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "this" {}

locals {
  image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo_name}/converter:${var.image_tag}"
}

# ── APIs ─────────────────────────────────────────────────────────────────────
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "workflows.googleapis.com",
    "workflowexecutions.googleapis.com",
    "eventarc.googleapis.com",
    "cloudbuild.googleapis.com",
    "pubsub.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

# ── Image registry (ECR equivalent) ──────────────────────────────────────────
resource "google_artifact_registry_repository" "converter" {
  location      = var.region
  repository_id = var.artifact_repo_name
  format        = "DOCKER"
  description   = "USDZ→GLB converter images"

  depends_on = [google_project_service.apis]
}

# ── Job identity (ECS task role equivalent) ──────────────────────────────────
resource "google_service_account" "converter" {
  account_id   = "lensart-converter"
  display_name = "LensArt converter (Cloud Run Job)"
}

# The AWS task role scopes s3:GetObject to models/* and s3:PutObject to
# converted/*. GCS IAM cannot express a prefix in a plain binding, so these two
# conditional bindings reproduce that scoping rather than granting the whole
# bucket.
resource "google_storage_bucket_iam_member" "converter_read_models" {
  bucket = var.gcs_bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.converter.email}"

  condition {
    title      = "read-usdz-prefix-only"
    expression = "resource.name.startsWith(\"projects/_/buckets/${var.gcs_bucket}/objects/${var.usdz_prefix}/\")"
  }
}

resource "google_storage_bucket_iam_member" "converter_write_converted" {
  bucket = var.gcs_bucket
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.converter.email}"

  condition {
    title      = "write-converted-prefix-only"
    expression = "resource.name.startsWith(\"projects/_/buckets/${var.gcs_bucket}/objects/${var.output_prefix}/\")"
  }
}

# ── The job itself (Fargate task equivalent) ─────────────────────────────────
resource "google_cloud_run_v2_job" "converter" {
  name                = var.job_name
  location            = var.region
  deletion_protection = false

  template {
    parallelism = var.job_parallelism
    task_count  = 1

    template {
      service_account = google_service_account.converter.email
      max_retries     = var.job_max_retries
      timeout         = "${var.job_timeout_seconds}s"

      containers {
        image = local.image

        resources {
          limits = {
            cpu    = var.job_cpu
            memory = var.job_memory
          }
        }

        # GCS_BUCKET and GCS_KEY are supplied per-execution by the Workflow,
        # mirroring how the Lambda injects S3_KEY as an ECS container override.
        env {
          name  = "GOOGLE_CLOUD_PROJECT"
          value = var.project_id
        }
        env {
          name  = "OUTPUT_PREFIX"
          value = var.output_prefix
        }
        env {
          name  = "WEBHOOK_URL"
          value = var.webhook_url
        }
        env {
          name  = "WEBHOOK_SECRET"
          value = var.webhook_secret
        }
      }
    }
  }

  depends_on = [google_project_service.apis]
}

# ── Dispatcher (Lambda equivalent) ───────────────────────────────────────────
resource "google_service_account" "workflow" {
  account_id   = "lensart-converter-wf"
  display_name = "LensArt converter dispatcher (Workflows)"
}

# The direct analogue of the Lambda's ecs:RunTask policy, which is scoped to a
# single task-definition ARN. roles/run.invoker only grants run.jobs.run, which
# is NOT enough when the caller passes container overrides — that needs
# run.jobs.runWithOverrides. roles/run.developer would cover it but also allows
# deploying services, so this custom role keeps the dispatcher least-privileged.
resource "google_project_iam_custom_role" "job_runner" {
  role_id     = "lensartConverterJobRunner"
  title       = "LensArt converter job runner"
  description = "Execute the converter Cloud Run Job with container overrides"
  permissions = [
    "run.jobs.run",
    "run.jobs.runWithOverrides",
    "run.executions.get",
  ]
}

# Bound on the job itself, not project-wide.
resource "google_cloud_run_v2_job_iam_member" "workflow_runs_job" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.converter.name
  role     = google_project_iam_custom_role.job_runner.id
  member   = "serviceAccount:${google_service_account.workflow.email}"
}

resource "google_project_iam_member" "workflow_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.workflow.email}"
}

resource "google_workflows_workflow" "converter" {
  name            = "lensart-converter-dispatch"
  region          = var.region
  service_account = google_service_account.workflow.id

  source_contents = templatefile("${path.module}/workflow.yaml", {
    project_id  = var.project_id
    region      = var.region
    job_name    = var.job_name
    usdz_prefix = var.usdz_prefix
  })

  depends_on = [google_project_service.apis]
}

# ── Trigger (S3 bucket notification equivalent) ──────────────────────────────
resource "google_service_account" "eventarc" {
  account_id   = "lensart-converter-ea"
  display_name = "LensArt converter Eventarc trigger"
}

resource "google_project_iam_member" "eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.eventarc.email}"
}

resource "google_project_iam_member" "eventarc_workflows_invoker" {
  project = var.project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.eventarc.email}"
}

# Cloud Storage's own service agent must be able to publish the notification.
resource "google_project_iam_member" "gcs_agent_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.this.number}@gs-project-accounts.iam.gserviceaccount.com"
}

# NOTE: Eventarc storage triggers cannot filter by object prefix — only by
# bucket. The converter writes converted/*.glb into this same bucket, so every
# conversion fires another event. The prefix filter inside workflow.yaml is what
# stops that becoming an infinite loop; it is load-bearing, not cosmetic.
resource "google_eventarc_trigger" "usdz_finalized" {
  name     = "lensart-converter-usdz"
  location = var.region

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }

  matching_criteria {
    attribute = "bucket"
    value     = var.gcs_bucket
  }

  destination {
    workflow = google_workflows_workflow.converter.id
  }

  service_account = google_service_account.eventarc.email

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.eventarc_receiver,
    google_project_iam_member.eventarc_workflows_invoker,
    google_project_iam_member.gcs_agent_pubsub_publisher,
  ]
}
