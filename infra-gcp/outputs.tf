output "artifact_registry_repo" {
  description = "Push images here"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo_name}"
}

output "image_deployed" {
  description = "Image currently referenced by the Cloud Run Job"
  value       = local.image
}

output "job_name" {
  value = google_cloud_run_v2_job.converter.name
}

output "converter_service_account" {
  value = google_service_account.converter.email
}

output "workflow_name" {
  value = google_workflows_workflow.converter.name
}

output "eventarc_trigger" {
  value = google_eventarc_trigger.usdz_finalized.name
}
