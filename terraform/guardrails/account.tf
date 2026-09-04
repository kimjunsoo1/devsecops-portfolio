# ---------------------------------------------------------------------------
# 계정 수준 기본값. 앞으로 만들 모든 리소스가 이 위에서 만들어집니다.
# ---------------------------------------------------------------------------

# 계정 전체에서 S3 퍼블릭 액세스를 차단합니다.
# 개별 버킷 설정을 실수해도 계정 차원에서 한 번 더 막힙니다.
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 앞으로 만들어지는 모든 EBS 볼륨을 기본 암호화합니다.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

# IAM 사용자를 쓰지 않더라도, 계정 기본 비밀번호 정책은 CIS 벤치마크 항목입니다.
resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 5
}
