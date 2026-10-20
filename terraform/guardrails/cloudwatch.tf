# ---------------------------------------------------------------------------
# CloudTrail -> CloudWatch Logs
#
# S3 에 쌓인 로그는 "사후에 찾아보는" 기록입니다. 사람이 열어보지 않으면
# 아무 일도 일어나지 않습니다. 메트릭 필터와 알람을 붙이려면 CloudWatch
# Logs 로도 보내야 합니다.
#
# 이 파일이 이 프로젝트가 예방 통제에서 탐지 통제로 넘어가는 지점입니다.
# 지금까지의 모든 것(OIDC, OAC, 스캐너 게이트, 암호화)은 "나쁜 일이
# 일어나지 않게" 하는 장치였습니다. 여기서부터는 "일어났을 때 알아채는"
# 장치입니다.
#
# 비용: 수집 GB 당 $0.50, 보관 GB 당 월 $0.03. 1인 계정의 관리 이벤트는
# 월 수십 MB 수준이라 월 $0.1 를 넘기지 않습니다. 알람은 10개까지 무료입니다.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "trail" {
  name              = "/aws/cloudtrail/${local.trail_name}"
  retention_in_days = var.cloudtrail_retention_days

  # 감사 로그와 같은 키로 암호화합니다. kms.tf 의 AllowCloudWatchLogs
  # 문장이 logs.<region>.amazonaws.com 서비스 주체에게 이 계정의 로그
  # 그룹 범위로 키 사용을 허용합니다.
  kms_key_id = aws_kms_key.audit.arn

  #checkov:skip=CKV_AWS_66:보관 365일 요구. 감사 원본은 trail 버킷(S3)이 같은 기간 보관하고 로그 파일 검증 해시 체인으로 무결성을 보장한다. 이 로그 그룹은 알람 평가용 복사본이므로 원본과 같은 기간으로 맞춘다. 보존 요구가 생기면 S3 쪽 수명주기를 먼저 늘린다.
  #checkov:skip=CKV_AWS_338:CKV_AWS_66 과 같은 사안을 보는 별개 룰이다. 같은 보관 기간을 Checkov 내부에서 두 룰이 각각 평가하므로 억제도 두 개가 필요하다. 근거는 CKV_AWS_66 과 동일 - S3 원본이 감사 보존을 담당하고 이 그룹은 알람 평가용 복사본이다.
}

# ---------------------------------------------------------------------------
# CloudTrail 이 로그 그룹에 이벤트를 쓸 때 맡는 역할
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "trail_cwl_assume" {
  statement {
    sid     = "AllowCloudTrailToAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    # confused deputy 방지. 이 조건이 없으면 다른 계정의 트레일도 이
    # 역할을 맡을 수 있습니다. trail 버킷 정책에 SourceArn 을 넣은 것과
    # 같은 이유입니다.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_iam_role" "trail_cwl" {
  name = "${var.project}-cloudtrail-to-cwl"

  # 설명은 ASCII 만 허용됩니다.
  description        = "Allows CloudTrail to write log events to CloudWatch Logs"
  assume_role_policy = data.aws_iam_policy_document.trail_cwl_assume.json
}

data "aws_iam_policy_document" "trail_cwl" {
  statement {
    sid    = "WriteTrailEvents"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    # 스트림 이름은 CloudTrail 이 정하므로 와일드카드가 필요하지만,
    # 이 로그 그룹 아래로만 제한합니다. logs:* 나 Resource "*" 를
    # 쓰지 않는 이유입니다.
    resources = ["${trimsuffix(aws_cloudwatch_log_group.trail.arn, ":*")}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "trail_cwl" {
  name   = "write-to-log-group"
  role   = aws_iam_role.trail_cwl.id
  policy = data.aws_iam_policy_document.trail_cwl.json
}
