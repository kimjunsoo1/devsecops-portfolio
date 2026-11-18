# 인시던트 대응 런북 — devsecops-portfolio

/ 범위: AWS 계정 170638969320 · 단독 운영(책임자 = 소유자)

위협모델(docs/threat-model.md)이 "무엇이 위험한가"라면, 이 런북은
**"알림이 울리면 무엇을 하는가"** 다. 이 계정이 실제로 보낼 수 있는 모든
알림원에 1:1 로 대응 절차를 붙였다.

## 0. 공통 트리아지 (모든 알림)

모든 알림은 **SNS `devsecops-portfolio-billing-alerts` → 이메일**로 도착한다.

1. **기록 시작** — 수신 시각, 알림 제목, 원문 보관.
2. **무엇·언제·누가** — CloudTrail 에서 해당 시점 이벤트 확인:
   ```bash
   aws cloudtrail lookup-events --max-results 20 \
     --lookup-attributes AttributeKey=EventName,AttributeValue=<이벤트명>
   ```
3. **주체 식별** — `userIdentity`(root / SSO 롤 / 배포 롤 / 알 수 없음).
   주체가 **배포 롤 또는 SSO 외의 것**이면 심각도 상향.
4. **심각도 판단** → 아래 플레이북. 확실치 않으면 **보수적으로 대응**.
5. **봉쇄 우선** — 조사보다 피해 확산 차단이 먼저(키 비활성화·세션 취소).

> 공통 원칙: "통과가 통제를 뜻하지 않듯, 알림이 없다고 안전한 것도 아니다."
> 알림은 시작점이지 결론이 아니다.

## 1. 알림원별 플레이북

### 1-1. Root 계정 사용 (`root-account-usage`)
- **의미**: 루트로 로그인/행위. 일상 운영은 SSO 로 하므로 **거의 항상 비정상**.
- **즉시**: 루트 세션 여부 확인 → 본인이 아니면 침해로 간주. 루트 MFA·비밀번호
  재설정, 루트 액세스키 존재 시 즉시 삭제.
- **조사**: 루트가 수행한 모든 이벤트 추적(IAM 변경, 키 생성 등).
- **복구/확인**: 변경된 자격증명·정책 원복, 루트 사용 재발 방지(SSO 전용).

### 1-2. 승인되지 않은 API 호출 (`unauthorized-api-call`)
- **의미**: AccessDenied/UnauthorizedOperation 급증 → **정찰·권한 탐색** 신호.
- **즉시**: 주체 식별. 배포 롤/미상 주체면 자격증명 탈취 의심 → 해당 키/롤 세션 차단.
- **조사**: 어떤 액션을 시도했나(권한 경계 더듬기 패턴?). GuardDuty 발견과 교차.
- **복구/확인**: 탈취 의심 시 로테이션, 접근 범위 재점검.

### 1-3. IAM 정책 변경 (`iam-policy-change`)
- **의미**: 권한 상승·백도어 생성 전조.
- **즉시**: 변경 내용·주체 확인. **무단 변경이면 즉시 원복**(Attach/Put/Create 되돌림).
- **조사**: 새로 부여된 권한의 범위, 연쇄 변경 여부.
- **복구/확인**: Terraform 상태와 실제 비교(drift), IaC 로 재수렴.

### 1-4. KMS 키 변경 (`audit-key-change`: DisableKey / ScheduleKeyDeletion / PutKeyPolicy / DisableKeyRotation)
- **의미**: 암호화 우회·감사 로그 무력화 전조. CMK 는 CloudTrail·SNS 암호화에 쓰임.
- **즉시**: `ScheduleKeyDeletion` 이면 **즉시 취소**:
  ```bash
  aws kms cancel-key-deletion --key-id <keyId>
  aws kms enable-key --key-id <keyId>
  ```
  `PutKeyPolicy` 면 키 정책 외부 접근 추가 여부 확인.
- **조사**: 주체·의도. 키 무력화가 다른 공격의 준비 단계인지.
- **복구/확인**: 키 정책 IaC(kms.tf) 기준으로 원복, 로테이션 재활성화.

### 1-5. CloudTrail 변경/중단 (`cloudtrail-config-change`: StopLogging / DeleteTrail / UpdateTrail / PutEventSelectors / CreateTrail / StartLogging)
- **의미**: **감사 은폐**(anti-forensics) 전조. 공격자가 흔적을 지우려는 전형.
- **즉시**: `StopLogging` 이면 로깅 재개:
  ```bash
  aws cloudtrail start-logging --name devsecops-portfolio-trail
  ```
  `DeleteTrail` 이면 Terraform(cloudtrail.tf)으로 재생성.
- **조사**: 중단 ~ 재개 사이 **로그 공백 구간** 식별 → 그 구간 다른 증거(S3/CF 로그)로 보완.
- **복구/확인**: 트레일 상태·S3 전달·CWL 수신 정상 확인.

### 1-6. GuardDuty 발견 (sev ≥ 4 → EventBridge → SNS)
- **의미**: 관리형 위협 탐지. 유형이 성격을 말해준다.
- **즉시(유형별)**:
  - `UnauthorizedAccess:*` → 관련 자격증명/인스턴스 격리.
  - `CryptoCurrency:*` / `Backdoor:*` → 관련 리소스 즉시 격리·스냅샷.
  - `Recon:*` → 정찰 단계, 공격 표면 점검.
- **조사**: GuardDuty 콘솔에서 전체 상세(관련 주체·IP·리소스).
- **복구/확인**: 봉쇄 후 해당 finding 조치, 재발 시 자동대응 검토.
- 주: 저심각도(<4.0)는 설계상 메일로 안 온다(노이즈 억제) — 주기적으로 콘솔 확인.

### 1-7. 예산 초과 (Budgets 일/월)
- **의미**: 비용성 남용(암호화폐 채굴 등) 또는 오설정.
- **즉시**: 비용 급증 서비스/리전 식별(Cost Explorer). GuardDuty CryptoCurrency 와 교차.
- **조사**: 급증 리소스가 내가 만든 것인지, 무단 생성인지.
- **복구/확인**: 무단 리소스 제거, 원인 통제(예: SCP/예산 액션) 추가 검토.

## 2. 특수 시나리오

### 2-1. 배포/OIDC 침해 의심
- GitHub Actions 비정상 실행·배포 롤의 예상 밖 행위.
- **조치**: 배포 롤 신뢰정책(repo·ref 스코프) 점검, GitHub 리포 시크릿·토큰 로테이션,
  최근 배포 산출물 **서명 재검증**(cosign verify-blob), 사이트 콘텐츠 diff.
- 필요 시 배포 롤 일시 비활성화(trust 정책 축소)로 봉쇄.

### 2-2. 비밀 유출
- gitleaks/Trivy/CodeQL 탐지 또는 외부 제보.
- **조치**: 해당 크리덴셜 **즉시 무효화·로테이션**(노출=침해 가정), git 이력 범위 확인,
  영향 받는 리소스 점검. 사후 히스토리 정리.

### 2-3. tfstate 무결성 의심
- 상태파일 예상 밖 변경.
- **조치**: S3 버전 비교, 정상 버전 복원, 접근 주체 추적.

## 3. 사후 (공통)

- **타임라인**: 탐지 → 봉쇄 → 복구 시각 기록.
- **근본원인**: 왜 가능했나 + 왜 더 일찍 못 막았나.
- **재발방지**: 통제 추가/수정 → **위협모델·런북 갱신**(이 문서 포함).
- **증거 보관**: 관련 CloudTrail/GuardDuty export → docs/evidence/.

## 4. 참고

- 위협모델: docs/threat-model.md (잔여위험 R1–R6)
- 탐지 구성: terraform/guardrails/{detection,cloudwatch,guardduty,kms}.tf
- 알림 경로 검증: docs/security-testing.md Case 13(KMS 키정책 → SNS 실배달)
