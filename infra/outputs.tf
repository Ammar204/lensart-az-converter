output "ecr_repository_url" {
  description = "Push your Docker image here"
  value       = aws_ecr_repository.converter.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name (use in Lambda env)"
  value       = aws_ecs_cluster.main.name
}

output "ecs_task_definition_arn" {
  description = "Latest task definition ARN"
  value       = aws_ecs_task_definition.converter.arn
}

output "lambda_function_name" {
  description = "Lambda trigger function name"
  value       = aws_lambda_function.converter_trigger.function_name
}

output "lambda_function_arn" {
  description = "Lambda trigger function ARN"
  value       = aws_lambda_function.converter_trigger.arn
}

output "s3_bucket_name" {
  description = "Asset bucket name"
  value       = aws_s3_bucket.lensart.id
}

output "acm_certificate_arn" {
  description = "The cdn.lensart.app certificate"
  value       = aws_acm_certificate.cdn.arn
}

output "acm_validation_records" {
  description = "Add these CNAME records at Namecheap to issue the certificate"
  value = [
    for o in aws_acm_certificate.cdn.domain_validation_options : {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  ]
}

output "backend_access_key_id" {
  description = "AWS_ACCESS_KEY_ID for the NestJS backend"
  value       = aws_iam_access_key.backend.id
}

output "backend_secret_access_key" {
  description = "AWS_SECRET_ACCESS_KEY for the NestJS backend"
  value       = aws_iam_access_key.backend.secret
  sensitive   = true
}
