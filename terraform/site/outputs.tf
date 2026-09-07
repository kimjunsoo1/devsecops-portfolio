output "oidc_provider_arn" {
  description = "GitHub Actions OIDC 제공자 ARN"
  value       = aws_iam_openid_connect_provider.github.arn
  sensitive   = true
}

output "deploy_role_arn" {
  description = "워크플로가 assume 할 역할 ARN. GitHub 시크릿에 넣습니다."
  value       = aws_iam_role.deploy.arn
  sensitive   = true
}

output "trusted_subject" {
  description = "이 역할이 신뢰하는 정확한 sub 클레임. 워크플로 로그의 값과 일치해야 합니다."
  value       = local.github_subject
}
