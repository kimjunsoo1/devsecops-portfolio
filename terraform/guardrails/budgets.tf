# ---------------------------------------------------------------------------
# 비용 알림. 첫 리소스를 만들기 전에 이것부터 있어야 합니다.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "billing_alerts" {
  name = "${var.project}-billing-alerts"

  # SNS 주제 자체는 무료이고, 이메일 발송도 월 1,000건까지 무료입니다.

  # 저장 시 암호화. 전용 CMK 를 씁니다 (kms.tf 의 aws_kms_key.audit).
  #
  # 처음에는 alias/aws/sns (AWS 관리형 키) 를 썼습니다. 키 요금이 없어서
  # 비용상 유리했지만, AWS 관리형 키는 키 정책을 수정할 수 없습니다.
  # 그래서 CloudWatch 알람이 이 주제로 발행할 수 없고, 탐지 통제를 붙이는
  # 순간 막힙니다. 비용이 아니라 기능 때문에 CMK 로 옮겼습니다.
  #
  # Trivy AWS-0095(미암호화) 와 AWS-0136(CMK 아님) 을 동시에 해소합니다.
  kms_master_key_id = aws_kms_key.audit.arn
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
