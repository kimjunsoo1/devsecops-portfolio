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

# 감사 로그는 덮어쓰기나 삭제로 지워질 수 있으면 감사 로그가 아닙니다.
# 버전 관리로 이전 객체를 남깁니다. Trivy AWS-0090 (medium) 대응.
resource "aws_s3_bucket_versioning" "trail" {
  bucket = aws_s3_bucket.trail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.audit.arn
    }

    # 버킷 키를 켜면 객체마다 KMS 를 호출하는 대신 버킷 수준 데이터 키를
    # 재사용합니다. KMS 요청 요금이 최대 99% 줄어듭니다. CMK 를 쓰면서
    # 비용이 거의 안 늘어나는 이유가 이것입니다.
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

    # 버전 관리를 켰으므로 이전 버전도 같이 정리해야 스토리지가 안 쌓입니다.
    noncurrent_version_expiration {
      noncurrent_days = var.cloudtrail_retention_days
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

  # 로그 파일을 전용 CMK 로 암호화합니다 (CKV_AWS_35 / Trivy AWS-0015).
  #
  # CloudTrail 은 암호화할 때 aws:cloudtrail:arn 을 EncryptionContext 로
  # 넣습니다. kms.tf 의 AllowCloudTrailToEncryptLogs 문장이 그 컨텍스트로
  # 키 사용 범위를 이 계정의 트레일로 한정합니다.
  #
  # 키 정책이 틀리면 CloudTrail 은 예외를 던지지 않고 조용히 배달을
  # 멈춥니다. CI 도 PR 도 초록인 채로 감사 기록만 끊깁니다. apply 후
  # get-trail-status 의 LatestDeliveryError 확인이 필수입니다.
  kms_key_id = aws_kms_key.audit.arn

  # CloudWatch Logs 로도 같은 이벤트를 보냅니다 (CKV2_AWS_10 / AWS-0162).
  # S3 는 보관과 조사용, CloudWatch 는 알람 평가용입니다.
  #
  # 그룹 ARN 뒤에 :* 를 붙여야 합니다. 안 붙이면 CloudTrail 이
  # InvalidCloudWatchLogsLogGroupArnException 을 던집니다. 프로바이더
  # 버전에 따라 .arn 이 이미 :* 를 포함할 수 있어 trimsuffix 로
  # 중복을 막습니다 - 어느 쪽이든 결과가 같습니다.
  cloud_watch_logs_group_arn = "${trimsuffix(aws_cloudwatch_log_group.trail.arn, ":*")}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.trail_cwl.arn

  # 역할과 정책이 먼저 있어야 CloudTrail 이 쓰기를 시작할 수 있습니다.
  # 정책 연결 전에 트레일이 켜지면 첫 배달이 실패합니다.
  depends_on = [
    aws_s3_bucket_policy.trail,
    aws_iam_role_policy.trail_cwl,
  ]
}
