# ---------------------------------------------------------------------------
# 감사·알림 경로 전용 고객 관리 키 (CMK)
#
# 키를 하나만 만듭니다. CloudTrail 로그, trail 버킷, CloudTrail 의 CloudWatch
# 로그 그룹, 알림용 SNS 주제는 모두 "감사와 알림" 이라는 하나의 신뢰 경계에
# 속합니다. 키당 월 $1 이므로 쪼갤 실익보다 비용이 큽니다.
#
# 이 키를 만드는 결정적 이유는 비용이나 규정 준수가 아니라 기능입니다.
# AWS 관리형 키(alias/aws/sns)는 키 정책을 수정할 수 없어서, CloudWatch
# 알람이 SNS 주제로 발행하지 못합니다. 탐지 통제를 붙이는 순간 CMK 는
# 선택이 아니라 전제조건이 됩니다. docs/adr/0009 참조.
# ---------------------------------------------------------------------------

locals {
  account_root_arn = "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"
}

data "aws_iam_policy_document" "audit_key" {
  # 아래 세 건은 Checkov 가 이 문서를 범용 IAM 정책으로 평가해서 생기는 오탐입니다.
  # KMS 키 정책은 정의상 키 하나에만 붙고, KMS 는 키 정책의 Resource 에 다른 ARN 을
  # 허용하지 않습니다. 즉 "*" 가 유일하게 유효한 형태이며 "이 키" 를 의미합니다.
  #checkov:skip=CKV_AWS_109:키 정책의 Resource="*" 는 "이 키" 를 의미한다. KMS 는 키 정책에 다른 리소스 ARN 을 허용하지 않으므로 제약을 더 좁힐 수단이 없다.
  #checkov:skip=CKV_AWS_111:같은 이유. 또한 계정 주체의 kms:* 문장을 빼면 키가 잠기고 복구 경로가 없다 - AWS 의 policy lockout safety check 가 그런 정책을 애초에 거부한다.
  #checkov:skip=CKV_AWS_356:같은 이유. 서비스 주체 문장들은 EncryptionContext 조건으로 이 계정의 트레일과 로그 그룹에 한정되어 있다.
  # 계정 주체에게 전권을 줍니다.
  #
  # 이 문장을 빼면 키를 잠그고 되돌릴 수 없습니다. KMS 는 IAM 정책만으로
  # 접근을 허용하지 않고 키 정책이 먼저 통과해야 합니다. 즉 관리자
  # 권한이 있어도 키 정책이 거부하면 끝입니다. 복구 경로가 없습니다.
  statement {
    sid    = "EnableAccountAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [local.account_root_arn]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # CloudTrail 이 로그 파일을 암호화할 때 데이터 키를 발급받습니다.
  #
  # 조건은 EncryptionContext 를 씁니다. CloudTrail 은 암호화할 때
  # aws:cloudtrail:arn 을 컨텍스트로 넣으므로, 이 계정의 트레일로만
  # 키 사용을 한정할 수 있습니다. AWS 문서가 제시하는 표준 형태입니다.
  statement {
    sid    = "AllowCloudTrailToEncryptLogs"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:*:${local.account_id}:trail/*"]
    }
  }

  # CloudWatch Logs 가 로그 그룹을 암호화합니다.
  # 서비스 주체에 리전이 들어갑니다 — logs.ap-northeast-2.amazonaws.com.
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:log-group:*"]
    }
  }

  # CloudWatch 알람이 암호화된 SNS 주제로 발행할 때 필요합니다.
  #
  # 이 문장이 없으면 알람은 조용히 실패합니다. 알람 상태는 ALARM 으로
  # 바뀌는데 메일이 오지 않습니다. 탐지가 작동한다고 믿고 있지만 실제로는
  # 아무도 모르는 상태 — 가장 찾기 어려운 종류의 고장입니다.
  statement {
    sid    = "AllowCloudWatchAlarmsToUseKey"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
  }

  # AWS Budgets 도 같은 주제로 발행할 수 있게 합니다.
  #
  # 현재 예산 알림은 SNS 를 거치지 않고 subscriber_email_addresses 로
  # 직접 갑니다. 알림 경로를 한 곳으로 모을 때 필요하므로 미리 넣어둡니다.
  statement {
    sid    = "AllowBudgetsToUseKey"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
  }
}

resource "aws_kms_key" "audit" {
  # 설명은 ASCII 만 허용됩니다. 한글을 넣으면 API 가 거부합니다.
  description = "Audit and alerting path - CloudTrail, trail bucket, log group, SNS"

  # 연 1회 자동 로테이션. 추가 비용이 없습니다. (CKV_AWS_7)
  enable_key_rotation = true

  # 삭제 예약 후 대기 기간. 최소 7일, 기본 30일.
  # 실수로 지웠을 때 취소할 수 있는 창입니다. 짧게 잡을 이유가 없습니다.
  deletion_window_in_days = 30

  policy = data.aws_iam_policy_document.audit_key.json

  # 이 키를 잃으면 이 키로 암호화된 CloudTrail 로그를 복호화할 수 없습니다.
  # 감사 기록이 영구히 읽을 수 없게 되는 것과 같습니다.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "audit" {
  name          = "alias/${var.project}-audit"
  target_key_id = aws_kms_key.audit.key_id
}
