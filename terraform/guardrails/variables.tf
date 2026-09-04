variable "project" {
  description = "리소스 이름 접두사로 쓰이는 프로젝트 슬러그"
  type        = string
  default     = "devsecops-portfolio"
}

variable "aws_region" {
  description = "기본 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "owner" {
  description = "Owner 태그 값"
  type        = string
}

variable "alert_email" {
  description = "예산/보안 알림을 받을 이메일 주소"
  type        = string

  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.alert_email))
    error_message = "올바른 이메일 주소를 입력하세요."
  }
}

variable "monthly_budget_usd" {
  description = "월 예산 상한(USD). 이 값의 50%/80% 에서 실제 비용 알림, 100% 에서 예측 비용 알림이 옵니다."
  type        = number
  default     = 50

  validation {
    condition     = var.monthly_budget_usd > 0 && var.monthly_budget_usd <= 500
    error_message = "개인 프로젝트 예산은 1~500 USD 사이로 잡으세요."
  }
}

variable "daily_budget_usd" {
  description = "일 예산 상한(USD). NAT 게이트웨이 같은 실수를 다음 날 아침에 잡아냅니다."
  type        = number
  default     = 3
}

variable "cloudtrail_retention_days" {
  description = "CloudTrail 로그 보관 일수"
  type        = number
  default     = 90
}
