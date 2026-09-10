# 보안 게이트 침투 테스트

파이프라인에 게이트를 만들어 두는 것과 그 게이트가 실제로 막는 것은 다릅니다.
설정이 틀렸거나, 심각도 기준이 어긋났거나, 억제 목록이 너무 넓으면
게이트는 조용히 통과만 시킵니다. 그래서 주기적으로 시험합니다.

## 원칙

- 취약한 코드는 **main 에 도달하지 않습니다.** PR 이 빨간불인 것을 확인하고 닫습니다.
- `tests/security/` 는 어떤 Terraform 스택에도 속하지 않습니다. apply 대상이 아닙니다.
- 결과는 `docs/evidence/` 에 남깁니다.

## 1단계 — 로컬 훅 (푸시하지 않음)

가장 앞단 방어선입니다. 시크릿이 커밋 자체에서 막히는지 봅니다.

```bash
cat > /tmp/leak-test.tf <<'EOF'
provider "aws" {
  access_key = "AKIAIOSFODNN7EXAMPLE"
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}
EOF
cp /tmp/leak-test.tf ./leak-test.tf
git add leak-test.tf
git commit -m "test: 시크릿 커밋 시도"    # 여기서 막혀야 정상
```

`Detect hardcoded secrets ... Failed` 가 나오면 통과입니다.
화면을 캡처하고 정리합니다.

```bash
git reset HEAD leak-test.tf
rm -f leak-test.tf /tmp/leak-test.tf
```

## 2단계 — CI 게이트

로컬 훅은 `--no-verify` 로 우회할 수 있습니다. 실제로 그렇게 하는 개발자가 있고,
그래서 CI 에 같은 검사를 다시 두는 것입니다. 이번 단계가 그 이중화를 시험합니다.

```bash
git switch main && git pull
git switch -c test/security-gate-penetration

# tests/security/ 배치 후
cd tests/security && npm install --package-lock-only --no-audit --no-fund && cd ../..

# 로컬 훅을 일부러 우회합니다 - 우회하는 개발자를 흉내내는 것이 시험의 목적입니다
git add -A
git commit --no-verify -m "test: 보안 게이트 침투 테스트 (머지하지 않음)"
git push -u origin test/security-gate-penetration
gh pr create --fill --title "test: 보안 게이트 침투 테스트 (머지 금지)"
gh pr checks --watch
```

## 기대 결과

| 게이트 | 기대 | 실제 |
|---|---|---|
| `ci/시크릿 스캔` (gitleaks) | 실패 | |
| `security/의존성·설정 (Trivy)` | 실패 | |
| `security/코드 (Semgrep)` | 실패 또는 통과 | |

Semgrep 게이트는 `ERROR` 등급만 차단하므로, 심은 패턴이 `WARNING` 으로
분류되면 통과할 수 있습니다. **통과해도 실패가 아닙니다** —
"우리 정책이 이 패턴을 차단 대상으로 보지 않는다"는 사실을 확인한 것이고,
그 판단이 맞는지 다시 볼 계기가 됩니다.

## 정리

```bash
gh pr close <번호> --delete-branch
git switch main
```

**절대 머지하지 마세요.** 취약한 코드가 main 에 남으면 이후 모든 PR 의
게이트가 빨간불이 되고, 그걸 피하려고 억제 목록을 넓히게 됩니다.
그 순간 게이트는 의미를 잃습니다.
