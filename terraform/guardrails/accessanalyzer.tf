# IAM Access Analyzer — 계정 범위 외부 접근 분석기 (과금 없음)
# 리소스 정책이 계정 외부(다른 계정/공개)로 접근을 허용하는 경우를 탐지한다.
# Prowler accessanalyzer_enabled 백로그 해소. 태그는 provider default_tags 로 자동 부여.
resource "aws_accessanalyzer_analyzer" "account" {
  analyzer_name = "devsecops-portfolio-account"
  type          = "ACCOUNT"
}
