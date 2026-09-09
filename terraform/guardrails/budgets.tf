# ---------------------------------------------------------------------------
# 비용 알림. 첫 리소스를 만들기 전에 이것부터 있어야 합니다.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "billing_alerts" {
  name = "${var.project}-billing-alerts"

  # SNS 주제 자체는 무료이고, 이메일 발송도 월 1,000건까지 무료입니다.

  # 저장 시 암호화. alias/aws/sns 는 AWS 관리형 키라 월 키 요금이 없고,
  # 이 주제는 한 달에 알림 몇 건만 처리하므로 요청 요금도 사실상 0 입니다.
  # Trivy AWS-0095 (high) 대응.
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "billing_email" {
  topic_arn = aws_sns_topic.billing_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email

  # apply 후 받은편지함에서 "Confirm subscription" 을 눌러야 실제로 도착합니다.
}

# 월 예산: 실제 비용 50% / 80%, 예측 비용 100%
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit = false # 크레딧으로 가려진 실제 사용량을 봅니다
    include_refund = false
    include_tax    = true
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  # 가장 중요한 알림입니다. 이미 나간 돈이 아니라 "이 추세면 얼마 나올지" 를 봅니다.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# 일 예산: NAT 게이트웨이를 잘못 켜면 다음 날 아침에 메일이 옵니다.
resource "aws_budgets_budget" "daily" {
  name         = "${var.project}-daily"
  budget_type  = "COST"
  limit_amount = tostring(var.daily_budget_usd)
  limit_unit   = "USD"
  time_unit    = "DAILY"

  cost_types {
    include_credit = false
    include_refund = false
    include_tax    = true
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}
