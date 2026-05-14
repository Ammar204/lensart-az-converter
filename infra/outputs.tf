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
