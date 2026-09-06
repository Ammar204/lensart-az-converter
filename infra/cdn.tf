resource "aws_cloudfront_origin_access_control" "lensart" {
  name                              = "lensart-s3-oac"
  description                       = "Signs CloudFront requests to the private asset bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# The landing page renders GLBs with <model-viewer>, which fetches cross-origin.
# Without these headers the models fail to load with no server-side error at all.
# Putting CORS here rather than on the bucket keeps Origin out of the cache key.
#
# There is no S3 bucket CORS config, which is fine only because that GLB fetch
# is a simple request and never preflights. A future request with a
# non-safelisted header will preflight; CloudFront forwards OPTIONS to S3,
# which has no CORS config and will 403 it.
resource "aws_cloudfront_response_headers_policy" "assets_cors" {
  name = "lensart-assets-cors"

  cors_config {
    access_control_allow_credentials = false
    origin_override                  = true

    access_control_allow_headers {
      items = ["*"]
    }

    access_control_allow_methods {
      items = ["GET", "HEAD", "OPTIONS"]
    }

    access_control_allow_origins {
      items = ["*"]
    }
  }
}

resource "aws_cloudfront_distribution" "assets" {
  enabled = true
  comment = "LensArt assets"
  aliases = [var.cdn_domain_name]

  # PriceClass_100 is North America and Europe only and would miss the entire
  # user base. _200 adds India, the Middle East, Africa and SE Asia.
  price_class = "PriceClass_200"

  origin {
    domain_name              = aws_s3_bucket.lensart.bucket_regional_domain_name
    origin_id                = "s3-lensart"
    origin_access_control_id = aws_cloudfront_origin_access_control.lensart.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-lensart"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # Managed-CachingOptimized
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.assets_cors.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cdn.arn

    # sni-only is free. The alternative, "vip", is the legacy dedicated-IP
    # option at $600/month and exists only for pre-SNI clients. Never use it.
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Grants read to the CloudFront service principal, scoped by SourceArn to this
# one distribution. This is not a "public" policy, so the public access block
# from Task 1 permits it.
resource "aws_s3_bucket_policy" "cloudfront_read" {
  bucket = aws_s3_bucket.lensart.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.lensart.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.assets.arn
        }
      }
    }]
  })
}
