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
  #checkov:skip=CKV_AWS_18:S3 서버 액세스 로깅 미적용. 이 버킷은 CloudFront 가 OAC 로만 읽으므로 접근 기록은 CloudFront 계층에서 받는 것이 맞다(CKV_AWS_86 참조). 또한 로그 버킷을 만들면 그 버킷이 다시 이 룰에 걸리는 재귀가 생긴다. 계층 선택의 문제. permanent
  #checkov:skip=CKV_AWS_144:교차 리전 복제 미적용. 복제는 스토리지와 전송 비용을 두 배로 만든다. 이 버킷의 내용물은 git 에서 언제든 재배포할 수 있는 빌드 산출물이므로 복제로 지킬 고유 데이터가 없다. 비용 기반 거절. permanent
  #checkov:skip=CKV_AWS_145:CMK 대신 SSE-S3(AES256) 사용. 이 버킷에 담기는 것은 CloudFront 가 전 세계에 공개하는 정적 파일이라 기밀성 요구가 없다. 공개 콘텐츠에 월 1달러 키 비용을 쓸 이유가 없다. 저장 시 암호화 요건은 AES256 으로 충족한다. permanent
  #checkov:skip=CKV2_AWS_62:이벤트 알림 미설정. 알림을 받아 처리할 소비자가 없다. 배포는 GitHub Actions 가 동기적으로 수행하고 완료 여부는 워크플로 결과로 확인한다. 아키텍처상 해당 없음. permanent
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
