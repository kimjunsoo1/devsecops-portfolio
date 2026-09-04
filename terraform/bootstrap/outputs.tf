output "account_id" {
  description = "현재 AWS 계정 ID"
  value       = data.aws_caller_identity.current.account_id
}

output "state_bucket" {
  description = "guardrails 스택의 backend.hcl 에 넣을 버킷 이름"
  value       = aws_s3_bucket.tfstate.id
}

output "backend_hcl" {
  description = "그대로 복사해서 terraform/guardrails/backend.hcl 로 저장하세요"
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.tfstate.id}"
    key          = "guardrails/terraform.tfstate"
    region       = "${var.aws_region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
