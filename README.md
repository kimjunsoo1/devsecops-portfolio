# devsecops-portfolio

개인 포트폴리오/블로그 사이트를 AWS에 올리면서, 그 과정 전체를 코드와 보안 게이트로 만드는 프로젝트입니다.
목표는 사이트가 아니라 **사이트가 배포되기까지의 파이프라인**입니다.

## 설계 원칙

| 결정 | 이유 |
|---|---|
| EKS 대신 ECS Fargate | 컨트롤 플레인만 월 $73. 개인 프로젝트 예산을 혼자 다 씀 |
| NAT 게이트웨이 미사용 | 트래픽 0에도 월 $35+. 퍼블릭 서브넷 + 보안그룹 최소화로 대체 |
| RDS 대신 DynamoDB | 상시 과금 없음. 관계형이 필요 없는 워크로드 |
| Secrets Manager 대신 SSM Parameter Store | 표준 파라미터는 무료 |
| AWS Config 대신 Prowler | CIS 점검을 CI에서 무료로. 증적은 리포지토리에 남음 |
| 액세스 키 대신 OIDC | CI에 장기 자격증명을 두지 않음 |

자세한 근거는 [`docs/adr/`](docs/adr/) 에 있습니다.

## 진행 상황

- [x] **1주차** — 계정 가드레일, Terraform 백엔드, 예산 알림, CloudTrail
- [ ] 2주차 — 정적 블로그 배포 (S3 + CloudFront + OIDC)
- [ ] 3주차 — 코드 보안 게이트 (gitleaks / Semgrep / Trivy → SARIF)
- [ ] 4주차 — IaC 게이트 (Checkov / tflint / Conftest 자체 정책)
- [ ] 5주차 — 컨테이너와 공급망 (distroless / Trivy / SBOM / Cosign)
- [ ] 6주차 — 런타임 보안 (WAF / GuardDuty / Prowler)
- [ ] 7주차 — ECS 전환과 관측 (Fargate / 롤백 / 대시보드 / ZAP)
- [ ] 8주차 — 위협 모델 · 런북 · 데모

## 디렉터리

```
terraform/
  bootstrap/    state 버킷만 만드는 1회성 스택 (로컬 state)
  guardrails/   계정 수준 가드레일 (원격 state)
scripts/
  preflight.sh  로컬 도구 점검
docs/adr/       설계 결정 기록
.github/workflows/ci.yml
```

## 시작하기

```bash
# 0. 도구 점검
bash scripts/preflight.sh

# 1. state 버킷 생성 (딱 한 번)
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # owner 채우기
terraform init
terraform apply
terraform output -raw backend_hcl > ../guardrails/backend.hcl

# 2. 가드레일 배포
cd ../guardrails
cp terraform.tfvars.example terraform.tfvars   # owner, alert_email 채우기
terraform init -backend-config=backend.hcl
terraform plan
terraform apply

# 3. 받은편지함에서 SNS 구독 확인 메일의 "Confirm subscription" 클릭
```

## 비용

권장 구성 기준 월 약 $32(≈4.5만원). 1~4주차 구간은 월 $3 이하입니다.
`terraform/guardrails` 의 예산 알림이 월 상한의 50% / 80% / 예측 100%, 그리고 일 $3 초과 시 메일을 보냅니다.
