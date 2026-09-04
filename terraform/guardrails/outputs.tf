output "account_id" {
  description = "AWS 계정 ID"
  value       = local.account_id
  sensitive   = true
}

output "region" {
  description = "기본 리전"
  value       = local.region
}

output "billing_alerts_topic_arn" {
  description = "비용 알림 SNS 주제 ARN"
  value       = aws_sns_topic.billing_alerts.arn
}

output "cloudtrail_bucket" {
  description = "CloudTrail 로그 버킷"
  value       = aws_s3_bucket.trail.id
}

output "next_step" {
  description = "1주차 완료 후 할 일"
  value       = "받은편지함에서 SNS 구독 확인 메일의 'Confirm subscription' 을 누르세요. 그 전까지는 알림이 오지 않습니다."
}
