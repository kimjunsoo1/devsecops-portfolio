# ---------------------------------------------------------------------------
# 탐지 통제 — CloudTrail 이벤트에 메트릭 필터와 알람을 붙입니다.
#
# 여기까지의 모든 장치는 예방이었습니다. OIDC 로 키를 없애고, OAC 로
# 버킷을 닫고, 스캐너로 PR 을 막고, CMK 로 로그를 암호화했습니다.
# 전부 "나쁜 일이 일어나지 않게" 하는 쪽입니다.
#
# 이 파일은 "일어났을 때 알아채는" 쪽입니다. 예방은 언젠가 뚫리고,
# 뚫린 걸 모르는 시간이 피해 규모를 정합니다.
#
# 비용: 알람은 표준 해상도 10개까지 무료입니다. 메트릭 필터 자체는
# 무료이고, 커스텀 메트릭은 10개까지 무료입니다. 즉 이 파일은 공짜입니다.
#
# CIS AWS Foundations Benchmark 를 참고했지만 그대로 베끼지 않았습니다.
# CIS 3.2(MFA 없는 콘솔 로그인)는 제외했습니다 - 이 계정은 IAM Identity
# Center 를 쓰고, SSO 로그인은 userIdentity.type 이 AssumedRole 이며 MFA 는
# IAM 이 아니라 Identity Center 계층에서 처리됩니다. 표준 필터는 영원히
# 안 울리거나 매번 울립니다. 둘 다 없는 것보다 나쁩니다.
# 대신 CIS 3.5(트레일 변경)와 3.7(키 삭제)을 넣었습니다. 우리 감사 체인이
# 트레일 하나와 키 하나에 매달려 있기 때문입니다.
# ---------------------------------------------------------------------------

locals {
  metric_namespace = "${var.project}/CloudTrail"

  # IAM 정책을 바꿀 수 있는 모든 이벤트. 하나라도 빠지면 그 경로로
  # 권한 상승이 조용히 지나갑니다.
  iam_change_events = [
    "CreatePolicy", "CreatePolicyVersion", "DeletePolicy", "DeletePolicyVersion",
    "PutUserPolicy", "PutRolePolicy", "PutGroupPolicy",
    "DeleteUserPolicy", "DeleteRolePolicy", "DeleteGroupPolicy",
    "AttachUserPolicy", "AttachRolePolicy", "AttachGroupPolicy",
    "DetachUserPolicy", "DetachRolePolicy", "DetachGroupPolicy",
  ]

  # 트레일을 끄거나 지우거나 범위를 줄이는 이벤트.
  trail_change_events = [
    "StopLogging", "DeleteTrail", "UpdateTrail", "PutEventSelectors",
  ]

  # 키를 쓸 수 없게 만드는 이벤트. 이 키가 죽으면 감사 로그를
  # 복호화할 수 없습니다.
  kms_change_events = [
    "DisableKey", "ScheduleKeyDeletion", "PutKeyPolicy", "DisableKeyRotation",
  ]

  # eventName 목록을 CloudWatch Logs 필터 패턴으로 변환합니다.
  event_name_pattern = {
    for key, events in {
      iam   = local.iam_change_events
      trail = local.trail_change_events
      kms   = local.kms_change_events
      } : key => format(
      "{ %s }",
      join(" || ", [for e in events : "($.eventName = \"${e}\")"])
    )
  }

  # 탐지 정의. 필터와 알람이 이 맵을 공유하므로 항목을 추가하면
  # 양쪽이 같이 생깁니다. 이름이 어긋날 여지를 없앱니다.
  detections = {
    root-account-usage = {
      metric      = "RootAccountUsage"
      description = "Root account credentials were used. Investigate immediately."
      threshold   = 1

      # invokedBy NOT EXISTS 는 AWS 서비스가 루트 자격으로 대행한 호출을
      # 걸러냅니다. 그게 없으면 정상 서비스 동작에 알람이 울립니다.
      pattern = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
    }

    iam-policy-change = {
      metric      = "IamPolicyChange"
      description = "An IAM policy was created, modified, attached or detached."
      threshold   = 1
      pattern     = local.event_name_pattern["iam"]
    }

    cloudtrail-config-change = {
      metric      = "CloudTrailConfigChange"
      description = "CloudTrail was stopped, deleted or reconfigured. The audit chain depends on this trail."
      threshold   = 1
      pattern     = local.event_name_pattern["trail"]
    }

    audit-key-change = {
      metric      = "AuditKeyChange"
      description = "A KMS key was disabled or scheduled for deletion. Audit logs depend on the audit key."
      threshold   = 1
      pattern     = local.event_name_pattern["kms"]
    }

    unauthorized-api-call = {
      metric      = "UnauthorizedApiCall"
      description = "Repeated unauthorized API calls - possible reconnaissance or stolen credentials."

      # 다른 탐지는 1건이면 알립니다. 이것만 5건입니다.
      # 권한 없는 호출은 오타나 서비스의 정상 탐색으로도 발생하므로,
      # 1건으로 잡으면 알람이 울리는 게 일상이 되고 사람이 무시합니다.
      # 1인 계정에서는 평소 거의 0 이라 5건은 충분히 민감합니다.
      # 실제로 울려본 뒤 조정해야 하는 값입니다.
      threshold = 5
      pattern   = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "detect" {
  for_each = local.detections

  name           = "${var.project}-${each.key}"
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = each.value.pattern

  metric_transformation {
    name      = each.value.metric
    namespace = local.metric_namespace
    value     = "1"

    # default_value 가 없으면 일치하는 이벤트가 없는 기간에 데이터가
    # 아예 없어서 알람이 INSUFFICIENT_DATA 에 머뭅니다. 0 을 넣어
    # "확인했고 없었다" 와 "확인하지 않았다" 를 구분합니다.
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "detect" {
  for_each = local.detections

  alarm_name        = "${var.project}-${each.key}"
  alarm_description = each.value.description

  namespace   = local.metric_namespace
  metric_name = aws_cloudwatch_log_metric_filter.detect[each.key].metric_transformation[0].name

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"

  # default_value 를 넣었으니 결측은 정상 상태로 봅니다.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.billing_alerts.arn]
  ok_actions    = []
}

# ---------------------------------------------------------------------------
# SNS 토픽 정책
#
# 키 정책(kms.tf)은 "CloudWatch 가 이 키로 암호화해도 되는가" 를 정합니다.
# 토픽 정책은 "CloudWatch 가 이 토픽에 발행해도 되는가" 를 정합니다.
# 둘은 별개이고 하나만 있으면 알람이 ALARM 상태로 바뀌는데 메일은
# 오지 않습니다. 가장 찾기 어려운 고장입니다.
#
# 주의: 토픽 정책을 설정하면 AWS 기본 정책을 대체합니다. 계정 소유자
# 문장을 빼면 접근이 좁아집니다. KMS 키 정책과 같은 성질입니다.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "billing_topic" {
  statement {
    sid    = "AllowAccountOwner"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [local.account_root_arn]
    }

    actions = [
      "SNS:Publish",
      "SNS:Subscribe",
      "SNS:GetTopicAttributes",
      "SNS:SetTopicAttributes",
      "SNS:ListSubscriptionsByTopic",
      "SNS:DeleteTopic",
      "SNS:AddPermission",
      "SNS:RemovePermission",
    ]

    resources = [aws_sns_topic.billing_alerts.arn]
  }

  statement {
    sid    = "AllowCloudWatchAlarms"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.billing_alerts.arn]

    # 다른 계정의 알람이 이 토픽으로 발행하지 못하게 합니다.
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "AllowBudgets"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.billing_alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "billing_alerts" {
  arn    = aws_sns_topic.billing_alerts.arn
  policy = data.aws_iam_policy_document.billing_topic.json
}
