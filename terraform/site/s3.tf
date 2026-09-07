# ---------------------------------------------------------------------------
# 사이트 원본 버킷.
#
# 예전 방식(S3 정적 웹사이트 호스팅)은 버킷을 퍼블릭으로 열어야 합니다.
# 1주차에 켜둔 계정 수준 퍼블릭 차단과 정면으로 부딪히고,
# 무엇보다 버킷 URL 이 그대로 노출되어 CloudFront 를 우회할 수 있습니다.
#
# 여기서는 버킷을 완전히 비공개로 두고, CloudFront 만 읽게 합니다.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "site" {
  bucket = "${var.project}-site-${local.account_id}"
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# 배포가 잘못됐을 때 이전 버전으로 되돌릴 수 있게 합니다.
resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = "Enabled"
  }
}

# 버전이 무한정 쌓이면 스토리지 비용이 됩니다. 30일이면 충분합니다.
resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------------------
# 버킷 정책 — CloudFront 배포 "하나"에만 읽기를 허용합니다.
#
# Service: cloudfront.amazonaws.com 만 쓰고 조건을 빼면
# 전 세계 누구의 CloudFront 배포든 이 버킷을 원본으로 쓸 수 있습니다.
# AWS:SourceArn 조건이 그것을 내 배포로 좁힙니다.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.site.arn,
      "${aws_s3_bucket.site.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.site]
}
