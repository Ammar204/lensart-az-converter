variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket holding all assets"
  type        = string
  default     = "lensart-files-prod"
}

variable "cdn_domain_name" {
  description = "Custom domain served by CloudFront"
  type        = string
  default     = "cdn.lensart.app"
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

variable "s3_thumbnail_prefix" {
  description = "S3 prefix where catalog and scan thumbnails are written"
  type        = string
  default     = "catalog-scan-thumbnails"
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
  description = "Subnets for the ECS task network (default VPC, ap-south-1)"
  type        = list(string)
  default = [
    "subnet-0e72073f2f8f3aa7c",
    "subnet-0bca681d047876f0d",
    "subnet-0d9db6addf4ff2029",
  ]
}

variable "security_group_ids" {
  description = "Security groups for the ECS task"
  type        = list(string)
  default     = ["sg-0ab6b8a2ad65767f3"]
}

variable "assign_public_ip" {
  description = "Assign a public IP to the Fargate task (ENABLED/DISABLED)"
  type        = string
  default     = "ENABLED"
}

variable "webhook_url" {
  description = "Full backend webhook endpoint, used verbatim — nothing is appended"
  type        = string
  default     = "https://api.lensart.app/webhook/scan-uploaded"
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
