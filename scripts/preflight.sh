#!/usr/bin/env bash
# 1주차 Day 2 — 필요한 도구가 다 깔렸는지 확인합니다.
# 사용법: bash scripts/preflight.sh

set -uo pipefail

ok=0
ng=0

check() {
  local cmd="$1" hint="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '  \033[32m✓\033[0m %-12s %s\n' "$cmd" "$("$cmd" --version 2>&1 | head -n1)"
    ok=$((ok + 1))
  else
    printf '  \033[31m✗\033[0m %-12s 없음 — %s\n' "$cmd" "$hint"
    ng=$((ng + 1))
  fi
}

echo
echo "필수 도구"
check git        "https://git-scm.com"
check aws        "AWS CLI v2 — https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
check terraform  "https://developer.hashicorp.com/terraform/install"
check gh         "GitHub CLI — https://cli.github.com"
check pre-commit "pipx install pre-commit"

echo
echo "보안 도구 (3~5주차에 사용, 지금 깔아두면 편함)"
check gitleaks "https://github.com/gitleaks/gitleaks/releases"
check trivy    "https://trivy.dev/latest/getting-started/installation/"
check tflint   "https://github.com/terraform-linters/tflint"
check checkov  "pipx install checkov"
check docker   "https://docs.docker.com/get-docker/"

echo
echo "AWS 자격증명"
if aws sts get-caller-identity >/dev/null 2>&1; then
  acct=$(aws sts get-caller-identity --query Account --output text)
  arn=$(aws sts get-caller-identity --query Arn --output text)
  printf '  \033[32m✓\033[0m 계정 %s\n    %s\n' "$acct" "$arn"
  case "$arn" in
    *":root") printf '  \033[31m✗\033[0m 루트 자격증명입니다. 절대 이걸로 작업하지 마세요.\n'; ng=$((ng + 1)) ;;
  esac
else
  printf '  \033[31m✗\033[0m aws sts get-caller-identity 실패 — aws configure sso 를 먼저 하세요\n'
  ng=$((ng + 1))
fi

echo
echo "리전: ${AWS_REGION:-${AWS_DEFAULT_REGION:-(미설정 — ap-northeast-2 권장)}}"
echo
if [ "$ng" -eq 0 ]; then
  echo "준비 완료. Day 3 으로 넘어가세요."
else
  echo "$ng 개 항목이 남았습니다."
  exit 1
fi
