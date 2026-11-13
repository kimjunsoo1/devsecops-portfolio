# 스캐너 검증 런북

## 왜 이 문서가 있는가

스캐너가 "통과" 를 반환했을 때, 그것이 **깨끗해서인지 안 봐서인지는 구분되지
않습니다.** 두 상태의 출력이 똑같기 때문입니다.

```
발견사항 0건  ←  정말 깨끗함
발견사항 0건  ←  룰셋이 로드되지 않음
발견사항 0건  ←  스캔 경로가 비어 있음
발견사항 0건  ←  억제가 의도보다 넓게 적용됨
```

후자 셋은 보안 장치가 있다는 착각을 만듭니다. 장치가 없는 것보다 나쁩니다 - 없으면
적어도 없다는 것을 압니다.

그래서 이 프로젝트는 **게이트를 추가할 때마다 일부러 깨뜨려서 막히는 것을 확인**
합니다. 아래는 그 절차와, 실제로 걸려 넘어진 사례들입니다.

---

## 절차

### 1. 게이트를 추가하면 탐침을 만든다

일회용 위반 파일을 만들어 해당 룰이 실제로 걸리는지 봅니다. **레포 안에 두지
않습니다** - 두면 CI 가 그 파일을 스캔해 고의로 만든 위반이 실제 발견사항으로
올라옵니다.

```bash
mkdir -p /tmp/probe && cd /tmp/probe
# 룰이 반드시 잡아야 하는 최소 위반을 작성
# 스캐너를 레포 설정으로 실행
# 결과 확인 후 디렉터리 삭제
```

### 2. 억제를 하나 지워 게이트가 막는지 본다

```bash
cp <파일> /tmp/backup
sed -i '/#checkov:skip=<룰ID>/d' <파일>
checkov --directory . --framework terraform --compact --quiet >/dev/null 2>&1; echo "exit=$?"
cp /tmp/backup <파일>
```

`1` 다음 `0` 이 나와야 합니다.

> **미커밋 작업이 있을 때 `git checkout --` 로 되돌리지 마십시오.** 파일 전체를
> HEAD 로 되돌리므로, 탐침이 바꾼 한 줄만이 아니라 아직 커밋하지 않은 작업까지
> 함께 날아갑니다. 실제로 그렇게 억제 4건을 잃었습니다(사례 6).

### 3. 통과 건수를 지표로 쓰지 않는다

Checkov 의 `Passed checks` 는 리소스 수에 따라 움직입니다. 코드를 지워도 줄고,
리소스를 늘리면 아무 개선 없이 늘어납니다.

```
provider 블록 2개 삭제 → 통과 2건 감소 (CKV_AWS_41 이 provider 를 보기 때문)
```

게이트는 **실패 건수**로만 걸어야 합니다.

### 4. 설정이 적용됐는지 따로 확인한다

도구가 설정 파일을 못 읽어도 대개 에러를 내지 않습니다. 설정 적용 여부는 **결과가
아니라 동작**으로 확인합니다.

---

## 사례

### 1. tflint 가 설정 파일 없이 조용히 기본 룰만 돌았다

`iac.yml` 이 `TFLINT_CONFIG_FILE` 을 `.tflint.hcl` 로 가리켰지만 그 파일이
없었습니다. tflint 는 **에러 없이 bundled 룰만** 실행했습니다. exit 0, 출력 없음.
워크플로를 읽으면 설정이 적용되는 것처럼 보였습니다.

`--recursive` 는 각 디렉터리로 들어가므로, 루트의 `.tflint.hcl` 은 루트 모듈에만
적용됩니다. 하위 모듈까지 적용하려면 `TFLINT_CONFIG_FILE` 에 **절대 경로**를 줘야
합니다.

검증:

```bash
mkdir -p /tmp/tflint-probe && cd /tmp/tflint-probe
cat > main.tf <<'EOF'
variable "undocumented" { type = string }
resource "aws_instance" "bad" {
  ami           = "ami-0123456789abcdef0"
  instance_type = "t9.mega"
}
EOF
TFLINT_CONFIG_FILE=$HOME/devsecops-portfolio/.tflint.hcl tflint --format compact
```

`aws_instance_invalid_type` 이 떠야 aws 룰셋이 살아 있는 것입니다. 이것이 안 뜨면
플러그인이 붙지 않은 것입니다.

### 2. checkov 의 `--output-file-path` 는 디렉터리로만 해석된다

SARIF 업로드가 `Path does not exist: .../results.sarif` 로 실패했습니다. 스캔은
정상이었고 파일명이 달랐습니다. 세 변형을 측정해 가렸습니다.

| 호출 | 결과 |
|---|---|
| `--output-file-path <디렉터리>` | `<디렉터리>/results_sarif.sarif` |
| `--output-file-path <파일경로>` | 그 이름의 **디렉터리**를 만들고 그 안에 `results_sarif.sarif` |
| stdout 리다이렉트 | ASCII 배너가 먼저 찍혀 **유효한 JSON 이 아님** |

추측하지 말고 측정합니다.

### 3. 남겨둔 `tfplan` 파일을 Trivy 가 스캔해 억제를 우회했다

`terraform plan -out=tfplan` 의 산출물이 모듈 디렉터리에 남아 있었습니다. `.gitignore`
에는 있었지만 **Trivy 는 gitignore 를 보지 않습니다.**

결과가 둘이었습니다. 같은 룰이 두 번 뜨고, 더 중요하게는 **경로 기반 억제가
빠져나갔습니다.** 억제 파일은 `terraform/site/s3.tf` 로 적혀 있는데 plan 스냅샷은
`s3.tf` 로 보고하기 때문입니다.

`.gitignore` 는 레포를 지키지만 스캐너는 지켜주지 않습니다. plan 파일은 레포 밖에
씁니다.

```bash
terraform plan -out=/tmp/<스택>.tfplan
```

### 4. 묵은 체크 결과를 현재 판정으로 오독했다

오래 열려 있던 PR 의 체크는 생성 당시 상태로 남습니다. `main` 을 고쳐도 다시 돌지
않습니다. `gh pr checks` 의 실패 3건 중 2건이 8일·2일 전 결과였고 실제 실패는
하나였습니다.

런 생성 시각으로 가립니다.

```bash
gh run view <id> --json createdAt,headBranch
```

`@dependabot rebase` 가 듣지 않으면 `@dependabot recreate`.

### 5. WAF 차단이 404 로 가려 보였다

WAF 적용 후 공격 요청에 **403 이 아니라 404** 가 돌아왔습니다. 경로가 같고
User-Agent 만 다른 요청이 200 과 404 로 갈린 것이 단서였습니다.

원인은 CloudFront 의 `custom_error_response` 입니다. S3 가 없는 키에 돌려주는 403 을
404 로 바꾸도록 설정했는데, **WAF 차단의 403 까지 함께 덮였습니다.**

클라이언트 응답 코드로는 판정할 수 없습니다. WAF 샘플 기록이 결정적입니다.

```bash
aws wafv2 get-sampled-requests --region us-east-1 --scope CLOUDFRONT \
  --web-acl-arn <ARN> --rule-metric-name <룰> \
  --time-window StartTime=$(date -u -d '40 minutes ago' +%s),EndTime=$(date -u +%s) \
  --max-items 10 \
  --query 'SampledRequests[].{Action:Action,Rule:RuleNameWithinRuleGroup,URI:Request.URI}'
```

확인된 차단 기록:

| 룰 | 요청 | 결과 |
|---|---|---|
| `GenericLFI_QUERYARGUMENTS` | 경로 탐색 쿼리 | BLOCK |
| `CrossSiteScripting_QUERYARGUMENTS` | XSS 쿼리 | BLOCK |
| `Log4JRCE_HEADER` | `jndi:ldap` User-Agent | BLOCK |

응답 코드를 그대로 둔 것은 의도입니다 - 공격자에게 WAF 의 존재를 알려주지 않고,
방어 측은 샘플과 메트릭으로 봅니다. 단 레이트 제한만 429 로 분리했습니다. 요청이
많아 막힌 클라이언트에게 404 는 "없다" 는 뜻이어서 재시도를 멈출 이유가 없습니다.

### 6. 게이트 승격 첫 실행이 직전 PR 의 누락을 잡았다

모듈 3 에서 억제 24건을 넣고, 기한 장치를 탐침으로 시험한 뒤 커밋했습니다. 탐침
정리에 `git checkout -- terraform/guardrails/cloudtrail.tf` 를 썼는데, 그 파일의
변경은 **아직 커밋되지 않은 상태**였습니다. 억제 4건이 함께 날아갔고 PR 은 그 상태로
머지되었습니다.

`--soft-fail` 이었을 때는 실패 4건이 리포트로 흘러가 아무도 몰랐습니다. 모듈 4 에서
게이트를 켜자 **첫 실행에서 드러났습니다.**

두 가지가 남습니다. 미커밋 작업에 `git checkout --` 를 쓰지 않을 것. 그리고 게이트가
없는 동안의 리포트는 사람이 읽어야 하는데, 사람은 읽지 않는다는 것.

### 7. gitleaks 테스트가 아무것도 증명하지 않았다 (3주차)

시크릿 탐지를 시험하려고 AWS 문서의 예제 액세스 키를 커밋했습니다. 막혔습니다.
그런데 **gitleaks 는 그 예제 키를 allowlist 에 두고 있어서** 실제로는 탐지하지
않았고, 막은 것은 `no-commit-to-branch` 훅이었습니다.

무작위로 생성한 키를 별도 브랜치에서 커밋해 다시 시험했습니다. 이번에는 세 층이
차례로 걸렸습니다.

```
0층  GitHub push protection  (Stripe 패턴 - 푸시 자체를 거부)
1층  pre-commit gitleaks     (로컬 커밋 차단)
2층  CI gitleaks             (PR 차단)
```

테스트 데이터가 allowlist 에 있으면 통과가 통과를 의미하지 않습니다.

---

### 8. 게이트가 자기 테스트 코드를 잡았다 — 억제하기 전에 측정하라

5주차 침투 검증 워크플로를 작성하던 중 Semgrep 게이트가 PR 을 막았다. 공격을
검증하는 코드가 공격 패턴을 담고 있으니 방어 스캐너가 반응한 것이다. 3주차
gitleaks 예제 키, 오늘 오전 tfplan 스캔과 같은 계열의, 한 단계 더 미묘한 경우다.

처음에는 범인을 잘못 짚었다. 워크플로에 권한 상승 시도용 `"Action":"*",
"Resource":"*"` 문자열이 있어서 IAM 와일드카드 룰이 잡았으리라 추정했다. 로컬에서
해당 파일만 스캔하니 0 findings - 추정이 틀렸다. 전체를 스캔하니 실제 범인은
다른 파일의 `curl | python3` 이고 룰은 gha-curl-pipe-shell 이었다.

측정하지 않고 추정대로 억제했다면 실제 안티패턴을 덮었을 것이다.

처리 기준:

```
이 패턴이 여기 정당하게 있어야 하는가?
  예 → 인라인 억제 + 근거 (예: 거부를 유도하는 공격 페이로드 문자열)
  아니오 → 고친다 (curl|shell 은 토큰을 파일로 받아 처리하면 된다)
```

가르는 것은 "테스트 코드인가"가 아니라 "이 패턴이 여기 있어야 하는가"다.
curl|shell 은 테스트 코드라도 더 나은 방법이 있으므로 고쳤다.

### 9. 빈 결과를 "확인됨"으로 읽지 마라

침투 검증 증적을 로그에서 뽑을 때, grep 패턴이 로그의 실제 포맷과 맞지 않아
**출력이 비었다.** 그 빈 출력을 보고도 다음 단계(증적 파일 작성)로 넘어갈 뻔했다.
빈 grep 결과는 "일치가 없음"이지 "확인됨"이 아니다.

이것은 이 런북 전체의 주제가 증적 수집에도 적용된다는 뜻이다. 스캐너의 "통과"가
"깨끗함"을 뜻하지 않듯, 대조 명령의 "에러 없음"이 "대조됨"을 뜻하지 않는다.
증적은 손으로 쓰는 순간 관측이 아니라 주장이 된다 - 원본 로그와 한 줄씩 대조하는
그 단계가 증적을 증적으로 만든다.

실제로 한 대조:

```bash
# 포맷을 안 가리도록 매칭 부분만 뽑는다
gh run view "$RUN" --log | grep -aoE "(PASS|FINDING) .*(거부됨|성공.*)"
```

이렇게 뽑은 8줄을 증적 파일과 한 줄씩 맞춘 뒤에야 커밋했다.

---

### 10. curl 이 bash -e 아래서 조용히 실패하고 다음 줄로 밀린다

모듈 1 에서 syft 를 curl 로 받아 설치하는 CI 스텝이 깨졌다. 로그는 sha256sum 이
"No such file" 로 실패했다고 했지만, 로컬에서 같은 URL 을 받으면 http 200 으로
31MB 가 정상 수신됐다. URL 도 자산명도 맞았다.

원인은 러너 환경에서 curl 이 실패했는데 그 실패가 한 단계 뒤(sha256sum)로 밀려
나타난 것이었다. GitHub Actions 의 기본 셸은 `bash -e` 지만, curl 의 실패 처리와
파이프 동작이 겹치면 실패 지점이 흐려진다.

결론은 원인 추적이 아니라 선택이었다 - 직접 구현한 curl 설치를 공식 액션으로
바꿨다(사례의 교훈: 재현 불가한 CI 실패를 세 번 추측해 못 잡으면, 그 코드를
유지하는 비용을 의심하라). 추측을 세 번 빗나간 뒤에야 측정(로컬 재현)으로
"다운로드는 정상"을 확인했고, 그제서야 방향을 바꿨다.

### 11. cosign 거부가 파이프에 가려 exit 0 으로 읽힌다

서명 변조 테스트의 증적을 수집하며 `cosign verify-blob ... | tail -3` 으로
출력을 받았다. 변조본에 cosign 은 "invalid signature" 를 출력하며 거부했는데,
바로 뒤 `echo "exit=$?"` 가 **0** 을 찍었다.

`$?` 가 cosign 이 아니라 파이프라인 끝(`tail`)의 exit 을 잡았기 때문이다. tail 은
성공하므로 0 이다. 거부 메시지가 눈에 보여도 자동화는 exit 0 을 통과로 읽는다.

이 런북 전체의 주제("통과가 통제를 뜻하지 않는다")의 거울상이다 - **거부가
보여도 exit 이 0 이면 통제가 아니다.** CI 게이트가 검증을 파이프로 받으면 변조를
놓친다. exit 코드는 파이프 없이 직접 받아야 한다.

```bash
cosign verify-blob ... "$f" >/dev/null 2>&1; RESULT=$?   # 맞다
cosign verify-blob ... "$f" | tail -3; echo $?           # 틀리다 (tail 의 exit)
```

### 12. 기대된 비0 이 bash -e 에 걸려 판정 전에 죽는다

변조 테스트 워크플로가 CI 에서 실패했다. 로그는 "정상 산출물 검증 exit=0" 까지
찍고 바로 `##[error]` 로 끝났다 - 변조 검증 줄도, PASS/FINDING 판정도 없었다.

변조본을 검증하는 `verify tampered.bin` 이 의도대로 비0 을 반환했는데, GitHub
Actions 의 기본 `bash -e` 가 그 비0 을 스텝 실패로 보고 `TAMPER=$?` 를 받기 전에
스크립트를 죽였다. **실패를 기대하는 명령은 `-e` 아래서 그 자리에서 죽는다.**

역설적으로 이 실패가 "변조가 거부된다" 를 간접 증명했다 - `-e` 가 죽었다는 건
cosign 이 비0 을 냈다는 뜻이다. 하지만 워크플로는 판정까지 가서 PASS 로 끝나야
증적이 되므로, 실패를 기대하는 구간을 `set +e` 로 감쌌다(5주차 권한 경계
테스트에서 쓴 패턴).

사례 10·11·12 는 하나다. **검증 코드도 검증이 필요하다.** 공급망 테스트를 짜면서
셸의 함정(실패 전파, 파이프의 exit, -e 의 조기 종료)에 세 번 걸렸다. 통제가
거짓 신호를 내지 않게 하려면, exit 코드와 셸 동작을 정확히 다뤄야 한다.

---

## 체크리스트

게이트를 추가할 때:

- [ ] 룰셋이 로드됐는지 탐침으로 확인했는가
- [ ] 게이트 명령을 로컬에서 실행해 exit 코드를 봤는가
- [ ] 억제를 하나 지워 `exit=1` 이 되는지 확인했는가
- [ ] 리포트 파일이 워크스페이스 밖(`$RUNNER_TEMP`)에 쓰이는가
- [ ] 스캔 경로에 우리가 만든 산출물(plan, SARIF, 캐시)이 없는가
- [ ] 실패 건수로 판정하는가 (통과 건수가 아니라)
- [ ] 억제에 근거와 기한이 있는가 (`scripts/check-suppressions.py`)
