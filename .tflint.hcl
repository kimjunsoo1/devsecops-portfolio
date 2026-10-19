# tflint 설정. --recursive 로 하위 디렉터리를 돌 때도 이 설정이 적용됩니다.
# CI 는 TFLINT_CONFIG_FILE 로 이 파일을 가리킵니다.
#
# 주의: 이 파일이 없으면 tflint 는 에러 없이 bundled 룰만 돌립니다.
# "통과"가 "검사함"을 뜻하지 않으므로 파일 존재 자체가 검사 범위의 전제입니다.

plugin "terraform" {
  enabled = true
  preset  = "all"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
