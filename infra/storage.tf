resource "aws_s3_bucket" "lensart" {
  bucket = var.s3_bucket_name
}

# Nothing is public at the bucket. Reads arrive only through CloudFront's OAC,
# and the OAC bucket policy is not a "public" policy, so block_public_policy
# does not interfere with it.
resource "aws_s3_bucket_public_access_block" "lensart" {
  bucket                  = aws_s3_bucket.lensart.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lensart" {
  bucket = aws_s3_bucket.lensart.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# A presigned PUT that the client abandons leaves billable parts behind forever.
# This does NOT solve orphaned models/thumbnails — see backlog item 2 in the spec.
resource "aws_s3_bucket_lifecycle_configuration" "lensart" {
  bucket = aws_s3_bucket.lensart.id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
