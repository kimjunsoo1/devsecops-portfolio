data "aws_caller_identity" "current" {}

locals {
  # 계정 ID 를 붙여 전역 유일한 버킷 이름을 만듭니다.
  state_bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "tfstate" {
  #checkov:skip=CKV_AWS_18:S3 서버 액세스 로깅 미적용. 상태 버킷 접근 기록은 가치가 있으나 로그 버킷이 다시 이 룰에 걸리는 재귀가 생긴다. 현재는 CloudTrail 관리 이벤트로 버킷 정책 변경을 추적하는 수준에서 수용하며, 계정에 사람이 늘면 재검토한다. revisit=2027-06-01
  #checkov:skip=CKV_AWS_144:교차 리전 복제 미적용. Terraform 상태는 버전 관리로 이전 버전을 보존하고, 최악의 경우 import 로 복구할 수 있다. 복제 비용 대비 실익이 낮다. permanent
  #checkov:skip=CKV_AWS_145:CMK 대신 SSE-S3 사용. 상태 파일에는 민감할 수 있는 값이 들어가므로 CMK 가 이론적으로 맞다. 다만 1인 계정에서는 키 정책으로 접근을 나눌 상대가 없고, 버킷 정책과 계정 차원 퍼블릭 차단과 DenyInsecureTransport 로 위협 모델을 덮는다고 판단했다. 계정에 사람이 늘면 즉시 재검토한다. revisit=2027-06-01
  #checkov:skip=CKV2_AWS_62:이벤트 알림 미설정. 상태 파일 변경마다 알림을 받아 처리할 소비자가 없다. 상태 변경은 PR 과 apply 로그로 추적한다. 아키텍처상 해당 없음. permanent
  bucket = local.state_bucket_name

  # 실수로 state 버킷을 날리면 복구가 매우 번거롭습니다.
  lifecycle {
    prevent_destroy = true
  }
}

# 버전 관리: state 를 잘못 덮어썼을 때 되돌리는 유일한 수단입니다.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# state 에는 리소스 속성이 평문으로 들어갑니다. 암호화는 선택이 아닙니다.
# SSE-S3(AES256)는 무료입니다. KMS 를 쓰면 요청당 과금이 붙습니다.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 오래된 state 버전이 무한정 쌓이는 것을 막습니다.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# HTTP 로 오는 요청은 전부 거부합니다. Checkov CKV_AWS_70 대응이기도 합니다.
data "aws_iam_policy_document" "tfstate" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tfstate.json

  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}
