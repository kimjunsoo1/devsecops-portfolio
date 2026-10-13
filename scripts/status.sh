#!/usr/bin/env bash
# 프로젝트 복귀 점검.
#   bash scripts/status.sh
#
# 오랜만에 돌아왔을 때 "어디까지 했고 그동안 뭐가 변했는지"를 한 화면에 모읍니다.
# 읽기만 합니다. 아무것도 바꾸지 않습니다.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

b() { printf '\n\033[1m── %s\033[0m\n' "$1"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
ng() { printf '  \033[31m✗\033[0m %s\n' "$1"; }
info() { printf '    %s\n' "$1"; }

# ---------------------------------------------------------------- 리포지토리
b "리포지토리"
git fetch --all --prune --quiet 2>/dev/null
printf '  브랜치: %s\n' "$(git branch --show-current)"
dirty=$(git status --porcelain | wc -l)
[ "$dirty" -eq 0 ] && ok "작업 트리 깨끗함" || ng "커밋 안 된 변경 $dirty 건 (git status)"
behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
[ "$behind" -eq 0 ] && ok "원격과 동기화됨" || ng "원격이 $behind 커밋 앞섬 (git pull)"
printf '\n  최근 커밋:\n'
git log --oneline -8 | sed 's/^/    /'

local_only=$(git branch --format='%(refname:short)' | grep -v '^main$' || true)
[ -n "$local_only" ] && { printf '\n  남아 있는 로컬 브랜치:\n'; echo "$local_only" | sed 's/^/    /'; }

# ---------------------------------------------------------------- GitHub
b "GitHub"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  open_prs=$(gh pr list --state open --json number --jq 'length' 2>/dev/null || echo "?")
  printf '  열린 PR: %s\n' "$open_prs"
  gh pr list --state open --limit 10 2>/dev/null | sed 's/^/    /'

  printf '\n  최근 워크플로 실행:\n'
  gh run list --limit 8 2>/dev/null | sed 's/^/    /'

  printf '\n  열린 코드 스캐닝 알림:\n'
  gh api "/repos/{owner}/{repo}/code-scanning/alerts?per_page=100&state=open" \
    --jq 'group_by(.tool.name)[] | "    \(.[0].tool.name): \(length)건"' 2>/dev/null \
    || info "(없음 또는 조회 실패)"

  printf '\n  설치된 워크플로:\n'
  ls .github/workflows/ 2>/dev/null | sed 's/^/    /'
else
  ng "gh 인증 안 됨 — gh auth login"
fi

# ---------------------------------------------------------------- AWS
b "AWS"
if aws sts get-caller-identity >/dev/null 2>&1; then
  arn=$(aws sts get-caller-identity --query Arn --output text)
  acct=$(aws sts get-caller-identity --query Account --output text)
  ok "로그인됨 ($acct)"
  case "$arn" in
    *":root") ng "루트 자격증명입니다" ;;
    *AWSReservedSSO*) info "SSO 임시 자격증명" ;;
  esac

  printf '\n  예산 집행 현황:\n'
  aws budgets describe-budgets --account-id "$acct" \
    --query 'Budgets[].{budget:BudgetName,limit:BudgetLimit.Amount,spent:CalculatedSpend.ActualSpend.Amount,forecast:CalculatedSpend.ForecastedSpend.Amount}' \
    --output table 2>/dev/null | sed 's/^/    /' || info "(조회 실패 — 결제 정보 IAM 액세스 확인)"

  printf '\n  장기 자격증명 점검:\n'
  users=$(aws iam list-users --query 'length(Users)' --output text 2>/dev/null || echo "?")
  rootkeys=$(aws iam get-account-summary --query 'SummaryMap.AccountAccessKeysPresent' --output text 2>/dev/null || echo "?")
  [ "$users" = "0" ] && ok "IAM 사용자 0명" || ng "IAM 사용자 $users 명"
  [ "$rootkeys" = "0" ] && ok "루트 액세스 키 없음" || ng "루트 액세스 키 있음"
else
  ng "AWS 세션 만료 — aws sso login"
fi

# ---------------------------------------------------------------- 사이트
b "사이트"
if [ -d terraform/site/.terraform ] && aws sts get-caller-identity >/dev/null 2>&1; then
  url=$(cd terraform/site && terraform output -raw site_url 2>/dev/null)
  if [ -n "${url:-}" ]; then
    for path in "" "/blog/" "/nope"; do
      code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" "$url$path")
      printf '    %-8s %s\n' "${path:-/}" "$code"
    done
    info "$url"
  else
    info "(terraform output 없음)"
  fi
else
  info "(terraform/site 미초기화 또는 AWS 미로그인)"
fi

# ---------------------------------------------------------------- 드리프트
b "인프라 드리프트"
if aws sts get-caller-identity >/dev/null 2>&1; then
  for d in bootstrap guardrails site; do
    [ -d "terraform/$d/.terraform" ] || { info "$d: 미초기화 (terraform init 필요)"; continue; }
    (cd "terraform/$d" && terraform plan -detailed-exitcode -lock=false -input=false > /dev/null 2>&1)
    case $? in
      0) ok "$d: 코드와 실제가 일치" ;;
      2) ng "$d: 차이 있음 — terraform plan 으로 확인" ;;
      *) ng "$d: plan 실패" ;;
    esac
  done
else
  info "(AWS 미로그인)"
fi

printf '\n'
