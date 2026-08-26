variable "project_id" {
  description = "GCP project to deploy into"
  type        = string
  default     = "lensart-project"
}

variable "region" {
  description = "Region for Cloud Run, Artifact Registry, Workflows and Eventarc. Must match the bucket's location for storage triggers."
  type        = string
  default     = "asia-south1"
}

variable "gcs_bucket" {
  description = "Existing bucket holding models/ and converted/"
  type        = string
  default     = "lensart-files-prod"
}

variable "usdz_prefix" {
  description = "Object prefix that triggers the pipeline (without trailing slash)"
  type        = string
  default     = "models"
}

variable "output_prefix" {
  description = "Prefix where converted GLB files are written"
  type        = string
  default     = "converted"
}

variable "artifact_repo_name" {
  description = "Artifact Registry repository name"
  type        = string
  default     = "lensart-converter"
}

variable "job_name" {
  description = "Cloud Run Job name"
  type        = string
  default     = "lensart-converter"
}

variable "image_tag" {
  description = "Tag of the image in Artifact Registry to deploy"
  type        = string
}

variable "job_cpu" {
  description = "vCPU for the job (matches the 2048 CPU units of the Fargate task)"
  type        = string
  default     = "2"
}

variable "job_memory" {
  description = "Memory for the job. Note Cloud Run's /tmp is an in-memory tmpfs counting against this — raise to 8Gi if conversions OOM."
  type        = string
  default     = "4Gi"
}

variable "job_timeout_seconds" {
  description = "Hard bound on a task. The conversion has its own 5-minute cap in src/converter.js; ECS never gave the task an outer timeout."
  type        = number
  default     = 900
}

variable "job_max_retries" {
  description = "Cloud Run task retries on failure"
  type        = number
  default     = 1
}

variable "job_parallelism" {
  description = "Max concurrent tasks per execution. Guards against unbounded fan-out on an upload burst."
  type        = number
  default     = 1
}

variable "webhook_url" {
  description = "FULL backend webhook endpoint, used verbatim (e.g. https://api.example.com/webhook/scan-uploaded)"
  type        = string
}

variable "webhook_secret" {
  description = "Shared secret for the X-LensArt-Signature HMAC. Must match the backend's WEBHOOK_SECRET."
  type        = string
  sensitive   = true
}
