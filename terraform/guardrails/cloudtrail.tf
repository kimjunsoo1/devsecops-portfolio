# ---------------------------------------------------------------------------
# CloudTrail — "누가 무엇을 했는가" 의 기록.
# 계정당 첫 번째 트레일의 관리 이벤트는 무료입니다. 두 번째부터 과금됩니다.
# ---------------------------------------------------------------------------

locals {
  trail_name = "${var.project}-trail"
  trail_arn  = "arn:${data.aws_partition.current.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.trail_name}"
}

resource "aws_s3_bucket" "trail" {
  bucket = "${var.project}-cloudtrail-${local.account_id}"

  # 감사 로그 버킷을 실수로 지우지 않도록 잠급니다.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket = aws_s3_bucket.trail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# 보관 기간을 정하지 않으면 로그가 영구히 쌓입니다. 개인 프로젝트엔 90일이면 충분합니다.
resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "expire-trail-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.cloudtrail_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "trail_bucket" {
  # CloudTrail 이 버킷 소유권을 확인하는 호출
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]

    # SourceArn 조건이 없으면 다른 계정의 트레일도 이 버킷을 쓸 수 있습니다
    # (confused deputy). 반드시 넣으세요.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  # 실제 로그 파일 쓰기
  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${local.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
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
      aws_s3_bucket.trail.arn,
      "${aws_s3_bucket.trail.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.trail]
}

resource "aws_cloudtrail" "this" {
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.trail.id

  # 서울에서만 켜면 다른 리전에서 벌어진 일은 기록되지 않습니다.
  # 공격자가 잘 쓰지 않는 리전을 고르는 이유가 이것입니다.
  is_multi_region_trail = true

  # IAM 같은 글로벌 서비스 이벤트도 포함
  include_global_service_events = true

  # 로그 파일이 변조되지 않았음을 증명하는 해시 체인. 무료입니다.
  enable_log_file_validation = true

  depends_on = [aws_s3_bucket_policy.trail]
}
