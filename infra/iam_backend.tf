# The NestJS API runs on EC2 outside this Terraform root, so it authenticates
# with a long-lived key rather than an instance role (spec decision D7).
resource "aws_iam_user" "backend" {
  name = "lensart-backend"
}

# PutObject only. The API never reads assets back — clients fetch them through
# CloudFront — and it must not be able to delete anything.
# models/* is required because a presigned PUT carries the signer's authority.
resource "aws_iam_user_policy" "backend_s3" {
  name = "s3-asset-write"
  user = aws_iam_user.backend.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutObject"]
      Resource = [
        "${aws_s3_bucket.lensart.arn}/${var.s3_usdz_prefix}/*",
        "${aws_s3_bucket.lensart.arn}/${var.s3_thumbnail_prefix}/*",
      ]
    }]
  })
}

resource "aws_iam_access_key" "backend" {
  user = aws_iam_user.backend.name
}
