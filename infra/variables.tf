variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "Name of the existing S3 bucket (lensart-files)"
  type        = string
  default     = "lensart-files"
}

variable "s3_usdz_prefix" {
  description = "S3 key prefix that triggers the pipeline (without trailing slash)"
  type        = string
  default     = "models"
}

variable "s3_output_prefix" {
  description = "S3 prefix where converted GLB files are written"
  type        = string
  default     = "converted"
}

variable "ecr_repo_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "lensart-converter"
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = "lensart-cluster"
}

variable "ecs_task_family" {
  description = "ECS task definition family name"
  type        = string
  default     = "lensart-converter"
}

variable "ecs_container_name" {
  description = "Container name inside the task definition"
  type        = string
  default     = "lensart-converter"
}

variable "ecs_task_cpu" {
  description = "Fargate task CPU units (1024 = 1 vCPU)"
  type        = string
  default     = "2048"
}

variable "ecs_task_memory" {
  description = "Fargate task memory in MiB"
  type        = string
  default     = "4096"
}

variable "subnet_ids" {
  description = "List of subnet IDs for the ECS task network"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for the ECS task"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign a public IP to the Fargate task (ENABLED/DISABLED)"
  type        = string
  default     = "ENABLED"
}

variable "webhook_url" {
  description = "Backend webhook URL called when conversion finishes"
  type        = string
}

variable "webhook_secret" {
  description = "HMAC secret shared with the backend to verify webhook authenticity"
  type        = string
  sensitive   = true
}

variable "lambda_function_name" {
  description = "Name of the Lambda trigger function"
  type        = string
  default     = "lensart-converter-trigger"
}

variable "image_tag" {
  description = "Docker image tag to deploy (e.g. git SHA)"
  type        = string
  default     = "latest"
}
