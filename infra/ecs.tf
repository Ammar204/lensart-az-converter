# ═══════════════════════════════════════════════════════════════════════════════
# ECR Repository
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_ecr_repository" "converter" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "converter" {
  repository = aws_ecr_repository.converter.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 3 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 3
      }
      action = { type = "expire" }
    }]
  })
}

# ═══════════════════════════════════════════════════════════════════════════════
# ECS Cluster
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_ecs_cluster" "main" {
  name = var.ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# IAM — ECS Task Execution Role (pulls image from ECR, writes logs)
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "ecs_execution" {
  name = "${var.ecs_task_family}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ═══════════════════════════════════════════════════════════════════════════════
# IAM — ECS Task Role (what the running container can do)
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "ecs_task" {
  name = "${var.ecs_task_family}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "s3-read-write"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.lensart.arn}/${var.s3_usdz_prefix}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = "${aws_s3_bucket.lensart.arn}/${var.s3_output_prefix}/*"
      }
    ]
  })
}

# ═══════════════════════════════════════════════════════════════════════════════
# CloudWatch Log Group for ECS task
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_cloudwatch_log_group" "converter" {
  name              = "/ecs/${var.ecs_task_family}"
  retention_in_days = 14
}

# ═══════════════════════════════════════════════════════════════════════════════
# ECS Task Definition
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_ecs_task_definition" "converter" {
  family                   = var.ecs_task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name  = var.ecs_container_name
    image = "${aws_ecr_repository.converter.repository_url}:${var.image_tag}"

    essential = true

    # Default env vars — Lambda overrides S3_KEY and S3_BUCKET per invocation
    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "S3_BUCKET", value = var.s3_bucket_name },
      { name = "OUTPUT_PREFIX", value = var.s3_output_prefix },
      { name = "WEBHOOK_URL", value = var.webhook_url },
      { name = "WEBHOOK_SECRET", value = var.webhook_secret },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.converter.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ═══════════════════════════════════════════════════════════════════════════════
# IAM — Lambda Execution Role
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "lambda_exec" {
  name = "${var.lambda_function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_ecs" {
  name = "ecs-run-task"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = aws_ecs_task_definition.converter.arn
      },
      {
        # Lambda must be able to pass the task role to ECS
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.ecs_execution.arn,
          aws_iam_role.ecs_task.arn,
        ]
      }
    ]
  })
}

# ═══════════════════════════════════════════════════════════════════════════════
# Lambda Function (zip deployed; swap for S3 source if you prefer)
# ═══════════════════════════════════════════════════════════════════════════════

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/lambda_function.zip"
  excludes    = [".env.example", ".env"]
}

resource "aws_lambda_function" "converter_trigger" {
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_exec.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      ECS_CLUSTER            = aws_ecs_cluster.main.name
      ECS_TASK_DEFINITION    = var.ecs_task_family
      ECS_CONTAINER_NAME     = var.ecs_container_name
      ECS_LAUNCH_TYPE        = "FARGATE"
      ECS_SUBNET_IDS         = join(",", var.subnet_ids)
      ECS_SECURITY_GROUP_IDS = join(",", var.security_group_ids)
      ECS_ASSIGN_PUBLIC_IP   = var.assign_public_ip
      S3_BUCKET              = var.s3_bucket_name
      OUTPUT_PREFIX          = var.s3_output_prefix
      WEBHOOK_URL            = var.webhook_url
      WEBHOOK_SECRET         = var.webhook_secret
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# S3 → Lambda Event Notification
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.converter_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.lensart.arn
}

resource "aws_s3_bucket_notification" "usdz_upload" {
  bucket = aws_s3_bucket.lensart.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.converter_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "${var.s3_usdz_prefix}/"
    filter_suffix       = ".usdz"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
