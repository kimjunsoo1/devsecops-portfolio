# devsecops-portfolio

개인 포트폴리오/블로그 사이트를 AWS 에 올리면서, 그 과정 전체를 코드와 보안 게이트로
만드는 프로젝트입니다. 목표는 사이트가 아니라 **사이트가 배포되기까지의 파이프라인**
입니다.

사이트: https://d3jnlp3megsao6.cloudfront.net

## 지금 동작하는 것

```
GitHub (main)
  │
  ├─ PR 게이트 8종 ─── 하나라도 걸리면 머지 불가
  │
  └─ 머지 ──> GitHub Actions (OIDC, 장기 키 없음)
                  │
                  └─> S3 (비공개) ──OAC──> CloudFront ──> WAF
                                                            │
AWS 계정                                                     └─> 방문자
  ├─ CloudTrail (멀티리전, CMK 암호화, 로그 파일 검증)
  │     ├─> S3 (90일 보관, 버전 관리)
  │     └─> CloudWatch Logs ──> 메트릭 필터 5 ──> 알람 5 ──> SNS ──> 메일
  └─ 예산 알림 (월 50/80%, 예측 100%, 일 $3)
```

예방 통제(왼쪽)와 탐지 통제(아래)가 모두 있고, **둘 다 실제로 작동하는 것을 확인**
했습니다. [`docs/security-testing.md`](docs/security-testing.md) 에 검증 절차와
걸려 넘어진 사례 7건이 있습니다.

## PR 게이트

| 게이트 | 차단 기준 | 도입 |
|---|---|---|
| gitleaks | 시크릿 발견 시 무조건 | 1주차 |
| Semgrep | ERROR 등급 | 3주차 |
| CodeQL | JS/TS 데이터플로 | 3주차 |
| Trivy (취약점·시크릿) | HIGH/CRITICAL, 전체 경로 | 3주차 |
| Trivy (오설정) | HIGH/CRITICAL, terraform 제외 | 4주차 |
| Checkov | terraform 발견사항 1건 | 4주차 |
| tflint | 경고 1건 (all preset + aws 룰셋) | 4주차 |
| 억제 주석 검사 | 근거 30자 미만 또는 기한 표기 누락·만료 | 4주차 |
| 액션 고정 검사 | SHA 미고정 또는 액션별 SHA 불일치 | 4주차 |

게이트가 많은 것이 목적이 아닙니다. **도구마다 책임 영역을 하나씩 정해서** 같은 판단을
두 군데서 관리하지 않게 했습니다 — Terraform 오설정은 Checkov 단독, 그 외 오설정은
Trivy, 취약점과 시크릿은 Trivy, 코드 패턴은 Semgrep 과 CodeQL. 근거는
[ADR 0007](docs/adr/0007-scanner-responsibility-split.md) 에 있습니다.

### 억제에는 기한이 있습니다

발견사항을 수용할 때는 근거를 코드 옆에 적고, `permanent` 또는 `revisit=YYYY-MM-DD`
를 붙입니다. `scripts/check-suppressions.py` 가 CI 에서 그것을 강제하고, 기한이 지난
항목을 **실패로 만듭니다.**

```bash
$ python3 scripts/check-suppressions.py --list
terraform/site/cloudfront.tf:64  CKV_AWS_86       revisit=2027-02-01
terraform/site/s3.tf:14          CKV_AWS_145      permanent
...
총 24건
```

이 장치가 왜 필요한지는 2026-11-03 에 확인했습니다. 2주간 손을 대지 않는 사이
CloudFront WAF 유예의 기한이 만료되어 게이트가 막혔고, 그래서 WAF 적용 결정을 더
미루지 못했습니다. 사람의 기억이 아니라 기계가 약속을 지킨 사례입니다.

## 탐지 통제

CloudTrail 이벤트에 메트릭 필터와 알람을 걸었습니다.

| 탐지 | 왜 |
|---|---|
| 루트 계정 사용 | 루트를 쓰지 않기로 했으니 쓰였다면 사고 |
| IAM 정책 변경 (16개 이벤트) | 권한 상승의 첫 단계 |
| CloudTrail 설정 변경 | `StopLogging`/`DeleteTrail` — 공격자가 가장 먼저 지우는 것 |
| KMS 키 비활성·삭제 예약 | 감사 로그가 이 키에 의존 |
| 권한 없는 API 호출 (임계값 5) | 1인 계정이라 평소 0 — 조용한 채널이 좋은 신호 |

CIS AWS Foundations Benchmark 를 참고했지만 그대로 베끼지 않았습니다. CIS 3.2(MFA
없는 콘솔 로그인)는 **제외했습니다** — 이 계정은 IAM Identity Center 를 쓰고 SSO
로그인은 `userIdentity.type` 이 `AssumedRole` 이며 MFA 는 Identity Center 계층에서
처리됩니다. 표준 필터는 영원히 안 울리거나 매번 울립니다. 대신 CIS 3.5/3.7 을 넣었습니다.

알림 경로와 탐지 경로를 **따로** 시험했습니다. 한 번에 시험하면 실패했을 때 어느
쪽인지 알 수 없습니다. 근거는 [ADR 0008](docs/adr/0008-cmk-as-detection-prerequisite.md).

## WAF 검증

적용 후 본인 사이트를 공격해 차단을 확인했습니다.

| 룰 | 요청 | 결과 |
|---|---|---|
| `GenericLFI_QUERYARGUMENTS` | 경로 탐색 쿼리 | BLOCK |
| `CrossSiteScripting_QUERYARGUMENTS` | XSS 쿼리 | BLOCK |
| `Log4JRCE_HEADER` | `jndi:ldap` User-Agent | BLOCK |
| — | 정상 요청 | 200 |

클라이언트에는 403 이 아니라 404 가 돌아옵니다. CloudFront 의
`custom_error_response` 가 S3 의 403(없는 키)을 404 로 바꾸면서 WAF 차단까지 덮기
때문입니다. 공격자에게 WAF 의 존재를 알려주지 않으므로 그대로 두되, 레이트 제한만
429 로 분리했습니다 — 요청이 많아 막힌 클라이언트에게 404 는 "없다" 는 뜻이어서
재시도를 멈출 이유가 없습니다.

## 파이프라인 침투 검증

지금까지의 통제가 **막아야 할 것을 실제로 막는지**를 공격으로 확인했다. 전부 본인
계정·본인 리포지토리 대상이고, 각 검증은 거부가 성공 결과다. 증적은
[`docs/evidence/week5-*.txt`](docs/evidence/).

| 검증 | 공격 가정 | 결과 |
|---|---|---|
| OIDC trust policy | 다른 브랜치 토큰으로 역할 탈취 | 거부 — ref 만 달라도 막힘 |
| S3 OAC + 버킷 정책 | CloudFront 우회 직접 접근 | 거부 — 직접·리스팅·평문 전부 403, CloudFront 만 200 |
| 배포 역할 권한 경계 | CI 장악 후 측면이동·권한상승 | 거부 — 자기 권한 확대 포함 전부 AccessDenied |

세 검증이 각각 다른 공격 단계를 막는다 — 들어오기(OIDC), 돌아가기(OAC),
퍼지기(권한 경계). 가장 중요한 것은 배포 역할이 **스스로 관리자 정책을 붙이지
못하는 것**이다. 이것이 막혀야 CI 가 완전히 장악되어도 피해가 세 리소스(site
버킷, 그 객체, 배포 1개)에 갇힌다. 근거와 설계 원칙은
[ADR 0010](docs/adr/0010-pipeline-penetration-testing.md).

검증 중에 Semgrep 게이트가 검증 워크플로 자신의 `curl | python3` 를 막았다.
방어를 검증하는 코드가 방어에 걸린 것이고, 억제하지 않고 고쳤다 - 자세한 내용은
[`docs/security-testing.md`](docs/security-testing.md)의 사례 8.

## 설계 원칙

비용이 제약이었고, 그 제약이 아키텍처를 정했습니다.

| 결정 | 이유 |
|---|---|
| 액세스 키 대신 OIDC | CI 에 장기 자격증명을 두지 않음. `sub` 클레임을 리포지토리·브랜치까지 완전 일치로 제한 |
| S3 퍼블릭 대신 OAC | 버킷은 완전 비공개. CloudFront 서비스 주체 + `AWS:SourceArn` 조건으로만 읽기 |
| 액션을 커밋 SHA 로 고정 | 태그는 옮길 수 있음. 고정과 Dependabot 자동 갱신은 반대가 아니라 한 쌍 |
| NAT 게이트웨이 미사용 | 트래픽 0 에도 월 $35+. 정적 사이트에 VPC 가 필요 없음 |
| EKS 미사용 | 컨트롤 플레인만 월 $73. 개인 프로젝트 예산을 혼자 다 씀 |
| 감사·알림 전용 CMK 1개 | 키당 월 $1. CloudTrail·버킷·로그 그룹·SNS 가 한 신뢰 경계라 쪼갤 실익 없음 |

자세한 근거는 [`docs/adr/`](docs/adr/) 에 있습니다.

| ADR | 내용 |
|---|---|
| [0001](docs/adr/0001-record-decisions.md) | 결정을 기록한다 |
| [0002](docs/adr/0002-no-nat-gateway.md) | NAT 게이트웨이를 쓰지 않는다 |
| [0005](docs/adr/0005-actions-commit-sha-pinning.md) | 액션을 커밋 SHA 로 고정한다 |
| [0006](docs/adr/0006-sast-tool-split.md) | SAST 를 Semgrep 과 CodeQL 로 나눈다 |
| [0007](docs/adr/0007-scanner-responsibility-split.md) | 스캐너별 책임 범위를 하나로 분리한다 |
| [0008](docs/adr/0008-cmk-as-detection-prerequisite.md) | CMK 는 탐지 통제의 전제조건이었다 |
| [0009](docs/adr/0009-dependency-gate-deadlock.md) | 의존성 게이트 교착은 통합 브랜치로 푼다 |
| [0010](docs/adr/0010-pipeline-penetration-testing.md) | 방어를 공격으로 검증한다 |

## 비용

1주차에 월 3~7만원으로 설계했습니다. 4주차 시점 실측은 **월 약 $10(1.5만원)** 입니다.

| 항목 | 월 |
|---|---|
| WAF (Web ACL $5 + 룰 3개 $3) | $8.00 |
| KMS 고객 관리 키 1개 | $1.00 |
| S3 · CloudFront · CloudWatch Logs · CloudTrail | $1 미만 |

**보안 통제 하나가 인프라 전체보다 비쌉니다.** WAF 가 전체의 80% 입니다. NAT 와 EKS 를
쓰지 않기로 한 1주차 결정이 그 예산을 만들어 주었습니다 — 둘 중 하나만 켰어도 WAF 를
붙일 여유가 없었습니다.

예산 알림이 월 상한의 50% / 80% / 예측 100%, 그리고 일 $3 초과 시 메일을 보냅니다.

## 진행 상황

- [x] **1주차** — 계정 가드레일, Terraform 백엔드, 예산 알림, CloudTrail
- [x] **2주차** — 정적 사이트 배포 (S3 + CloudFront + OAC + OIDC)
- [x] **3주차** — 코드 보안 게이트 (gitleaks / Semgrep / Trivy / CodeQL → SARIF)
- [x] **4주차** — IaC 게이트 (Checkov / tflint), 탐지 통제, WAF, 억제 기한 강제
- [x] **5주차** — 파이프라인 침투 검증 (OIDC / OAC / 배포 역할 경계)
- [ ] 6주차 — 빌드 공급망 (distroless 빌드 이미지 / SBOM / Cosign 서명·검증)
- [ ] 7주차 — 계정 전역 탐지 (GuardDuty / Prowler)
- [ ] 8주차 — 위협 모델 · 런북 · 데모

7주차의 ECS 전환은 범위에서 뺐다. 잘 동작하는 월 $10 아키텍처를 컨테이너 학습을
위해 바꾸는 것은 거꾸로다. 대신 빌드 도구를 컨테이너화해 런타임 비용 없이 공급망
통제를 만든다(6주차).

## 디렉터리

```
terraform/
  bootstrap/      state 버킷만 만드는 1회성 스택 (로컬 state)
  guardrails/     계정 가드레일, CloudTrail, CMK, 탐지 알람
  site/           S3 + CloudFront + OAC + WAF + OIDC 배포 역할
site/             Astro 정적 사이트
scripts/
  preflight.sh            로컬 도구 점검
  status.sh               현재 배포 상태 요약
  pin-actions.py          액션 SHA 고정·일관성 검사 (--check / --write / --align)
  check-suppressions.py   억제 주석의 근거와 기한 검사
docs/
  adr/                    설계 결정 기록
  evidence/               주차별 검증 증적 (자격증명 보고서, 배포 로그, WAF 차단 기록)
  security-policy.md      차단 기준
  security-backlog.md     수용한 위험과 재검토 시점
  security-testing.md     스캐너 검증 런북
  week-01-checklist.md    1주차 완료 체크리스트
.github/workflows/
  ci.yml        시크릿 스캔, Terraform 정적 검사, 액션 고정 검사
  security.yml  Semgrep, Trivy
  codeql.yml    CodeQL
  iac.yml       Checkov, tflint, 억제 주석 검사
  deploy.yml    main 머지 시 S3 동기화 + CloudFront 무효화
```

## 시작하기

```bash
# 0. 도구 점검
bash scripts/preflight.sh

# 1. state 버킷 생성 (딱 한 번)
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # owner 채우기
terraform init && terraform apply
terraform output -raw backend_hcl > ../guardrails/backend.hcl

# 2. 가드레일 배포
cd ../guardrails
cp terraform.tfvars.example terraform.tfvars   # owner, alert_email 채우기
terraform init -backend-config=backend.hcl
terraform plan && terraform apply

# 3. 받은편지함에서 SNS 구독 확인 메일의 "Confirm subscription" 클릭
#    누르지 않으면 알람이 울려도 메일이 오지 않습니다

# 4. 사이트 스택 배포
cd ../site
cp terraform.tfvars.example terraform.tfvars   # github_owner_id, github_repo_id 등
terraform init -backend-config=backend.hcl
terraform plan && terraform apply
```

로컬에서 게이트를 미리 돌려보려면:

```bash
pip install -r requirements-ci.txt
checkov --directory . --framework terraform --compact --quiet
TFLINT_CONFIG_FILE=$PWD/.tflint.hcl tflint --recursive --format compact
python3 scripts/check-suppressions.py
python3 scripts/pin-actions.py --check
```

게이트를 추가하거나 고칠 때는 [`docs/security-testing.md`](docs/security-testing.md)
의 체크리스트를 먼저 보십시오. **스캐너의 "통과" 는 깨끗함과 안 봄을 구분하지 못합니다.**
