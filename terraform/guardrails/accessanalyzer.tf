# IAM Access Analyzer — 계정 범위 외부 접근 분석기 (과금 없음)
# 리소스/롤이 계정 외부(다른 계정/공개/외부 IdP)에서 접근 가능한 경우를 탐지한다.
# Prowler accessanalyzer_enabled 백로그 해소. 태그는 provider default_tags 로 자동 부여.
resource "aws_accessanalyzer_analyzer" "account" {
  analyzer_name = "devsecops-portfolio-account"
  type          = "ACCOUNT"
}

# 아카이브 룰 — "확인했고 의도된 외부 접근"을 코드로 선언한다.
# 룰은 이후(미래) 동일 findings 를 자동 아카이브한다. 생성 시점에 이미 존재하던
# findings 는 자동 아카이브되지 않으므로, 최초 1회
#   aws accessanalyzer apply-archive-rule --analyzer-arn <arn> --rule-name <name>
# 로 소급 적용한다. 이렇게 "검토됨"을 IaC(룰)+1회 적용으로 남겨 Prowler 의
# accessanalyzer_enabled_without_findings(LOW)를 정당하게 해소한다.
#
# 주의: 외부 접근 분석기는 "누가 assume 할 수 있나(신뢰정책)"만 본다.
# 롤의 권한 과다(예: AdministratorAccess)는 별개 findings 이며 여기서 덮지 않는다.

# SSO(IAM Identity Center) 관리 롤 — 신뢰 주체가 Identity Center 라 항상 '외부'로 잡힌다.
# 로그인에 필요한 설계상 접근이므로 의도됨.
resource "aws_accessanalyzer_archive_rule" "intended_sso_roles" {
  analyzer_name = aws_accessanalyzer_analyzer.account.analyzer_name
  rule_name     = "intended-sso-roles"

  filter {
    criteria = "resource"
    contains = ["AWSReservedSSO_"]
  }
}

# GitHub OIDC 배포 롤 — 외부 IdP(GitHub)가 assume 한다. repo 스코프 sub 조건은
# 주5 침투검증에서 확인 완료. 의도된 federated 배포 접근.
resource "aws_accessanalyzer_archive_rule" "intended_github_oidc_deploy" {
  analyzer_name = aws_accessanalyzer_analyzer.account.analyzer_name
  rule_name     = "intended-github-oidc-deploy"

  filter {
    criteria = "resource"
    contains = ["devsecops-portfolio-github-deploy"]
  }
}
