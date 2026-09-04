# 1주차 완료 체크리스트

전부 체크되면 2주차로 넘어갑니다. 하나라도 비어 있으면 넘어가지 마세요.

## 계정
- [ ] 루트 계정에 MFA 등록, 루트 액세스 키는 존재하지 않음
- [ ] Billing preferences 에서 "결제 알림 받기" 활성화
- [ ] IAM Identity Center(또는 관리자 IAM 사용자)에 MFA 설정
- [ ] `aws sts get-caller-identity` 가 루트가 아닌 신원을 반환
- [ ] 기본 리전이 ap-northeast-2

## 도구
- [ ] `bash scripts/preflight.sh` 가 전부 통과
- [ ] `terraform version` 이 1.10 이상

## 리포지토리
- [ ] GitHub 퍼블릭 리포지토리 생성, main 브랜치 보호 규칙 활성화
- [ ] `pre-commit install` 완료, `pre-commit run --all-files` 통과
- [ ] `.terraform.lock.hcl` 이 커밋되어 있음
- [ ] `terraform.tfvars` 와 `backend.hcl` 이 커밋되어 있지 **않음**
- [ ] Actions 탭에서 ci 워크플로가 초록불

## 인프라
- [ ] state 버킷 존재, 버전 관리 + 암호화 + 퍼블릭 차단 확인
- [ ] `terraform/guardrails` 의 state 가 S3 에 있음 (`terraform state list` 로 확인)
- [ ] 월 예산 + 일 예산 두 개가 Budgets 콘솔에 보임
- [ ] SNS 구독 상태가 "Confirmed"
- [ ] CloudTrail 이 활성 상태이고 이벤트가 조회됨
- [ ] 계정 수준 S3 퍼블릭 액세스 차단이 켜짐

## 증적 (포트폴리오용)
- [ ] Budgets 콘솔 스크린샷
- [ ] `terraform apply` 출력 스크린샷
- [ ] CloudTrail 이벤트 히스토리 스크린샷
- [ ] ADR 2개 작성 완료
