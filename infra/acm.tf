# DNS is at Namecheap, not Route 53, so validation records are added by hand
# (Task 2). No aws_acm_certificate_validation resource: it would block apply on
# a manual step with a 45-minute timeout.
resource "aws_acm_certificate" "cdn" {
  provider          = aws.us_east_1
  domain_name       = var.cdn_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
