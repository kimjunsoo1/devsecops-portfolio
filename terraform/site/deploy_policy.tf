# ---------------------------------------------------------------------------
# 배포 역할의 권한.
#
# 모듈 2 에서 만든 역할에는 권한이 하나도 없었습니다.
# 이제 "정적 사이트를 배포한다" 에 필요한 것만 정확히 붙입니다.
#
# 흔한 실수는 AmazonS3FullAccess 를 붙이는 것입니다.
# 그러면 CI 토큰이 유출됐을 때 계정의 모든 버킷 - Terraform 상태 버킷과
# CloudTrail 감사 로그 버킷을 포함해서 - 를 지울 수 있습니다.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "deploy" {
  # 무엇이 이미 올라가 있는지 알아야 sync 가 동작합니다.
  # 이 버킷 하나에만 허용합니다.
  statement {
    sid       = "ListSiteBucketOnly"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.site.arn]
  }

  # 객체 쓰기. DeleteObject 는 --delete 로 삭제된 파일을 정리하는 데 필요합니다.
  statement {
    sid    = "WriteSiteObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = ["${aws_s3_bucket.site.arn}/*"]
  }

  # 캐시 무효화. 이 배포 하나에만 허용합니다.
  # 리소스를 "*" 로 두면 계정의 다른 배포까지 건드릴 수 있습니다.
  statement {
    sid       = "InvalidateThisDistributionOnly"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.site.arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.project}-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}
