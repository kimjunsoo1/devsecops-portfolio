# 0007. 스캐너별 책임 범위를 하나로 분리한다

- 상태: 채택
- 날짜: 2026-11-03
- 관련: [0006](0006-sast-tool-split.md), `scripts/check-suppressions.py`, `.github/workflows/security.yml`

## 맥락

4주차에 Checkov 와 tflint 를 도입하면서, Terraform 파일을 보는 도구가 셋이 되었습니다.

| 도구 | Terraform 을 보는가 | 어떻게 |
|---|---|---|
| Trivy | 예 | `--scanners misconfig` |
| Checkov | 예 | 전용 IaC 정책 엔진 |
| Semgrep | 예 | `--config=p/terraform` |

겹치는 지적이 나오면 "둘 다 잡으니 확실하다" 고 볼 수도 있습니다. 모듈 1 작업 중
`iac.yml` 머리말에도 그렇게 적었습니다. 실제로 세어 보니 그 판단이 틀렸습니다.

Trivy 가 Terraform 에서 내는 고유 룰 7개 중 **6개가 Checkov 와 1:1 대응**이었습니다.

| Trivy | Checkov | 내용 |
|---|---|---|
| AWS-0010 | CKV_AWS_86 | CloudFront 액세스 로깅 |
| AWS-0011 | CKV_AWS_68 | CloudFront WAF |
| AWS-0015 | CKV_AWS_35 | CloudTrail CMK 암호화 |
| AWS-0089 | CKV_AWS_18 | S3 버킷 로깅 |
| AWS-0132 | CKV_AWS_145 | S3 CMK 암호화 |
| AWS-0162 | CKV2_AWS_10 | CloudTrail → CloudWatch Logs |
| **AWS-0136** | **대응 없음** | **SNS 토픽 CMK** |

문제는 확실성이 아니라 **같은 판단을 두 군데서 관리해야 한다는 것**입니다.
한쪽에서 수용하고 다른 쪽을 잊으면 PR 이 빨개지고, 왜 빨간지 추적하는 데 시간을
씁니다. 실제로 그 상태를 겪었습니다. 그리고 Semgrep 의 Terraform 룰이 CloudFront
TLS 버전 하나를 더 지적해서, 같은 사안에 대한 세 번째 기록이 쌓이고 있었습니다.

## 결정

도구마다 책임 영역을 하나씩 정하고, 그 영역에서는 그 도구만 **게이트**합니다.

```
Terraform 오설정   →  Checkov 단독
그 외 오설정       →  Trivy  (워크플로, Dockerfile 등 Checkov 가 약한 영역)
취약점·시크릿      →  Trivy
코드 패턴          →  Semgrep (ERROR 등급) + CodeQL (데이터플로)
Terraform 코드 결함 →  tflint
```

구체적으로:

- `security.yml` 의 Trivy 게이트를 두 단계로 나눕니다. `trivy fs --scanners vuln,secret`
  은 전체를, `trivy config --skip-dirs terraform` 은 Terraform 을 제외한 오설정을 봅니다.
  `--skip-dirs` 를 `trivy fs` 에 그냥 붙이면 Terraform 디렉터리의 **시크릿 검사까지
  함께 꺼지므로** 단계를 쪼개야 합니다.
- Semgrep 설정에서 `--config=p/terraform` 을 뺍니다.
- **리포트는 그대로 전부 올립니다.** Trivy 의 `스캔 (리포트)` 단계는 계속
  `vuln,secret,misconfig` 로 전체를 보고 SARIF 를 업로드합니다. 게이트만 좁히는 것이고
  가시성은 좁히지 않습니다. Security 탭에서 두 도구의 판정을 비교할 수 있는 상태를
  유지합니다.
- `.trivyignore.yaml` 을 삭제합니다. Terraform 억제가 전부였으므로 남는 항목이 없습니다.

## 포기한 것

Trivy 고유 룰 **AWS-0136(SNS 토픽 CMK)** 의 검사가 사라집니다. Checkov 에 대응 룰이
없고(CKV_AWS_26 은 AWS 관리형 키도 암호화로 인정해 통과시킵니다), 따라서 이 결정은
커버리지를 1건 줄입니다.

받아들일 수 있다고 판단한 근거는 두 가지입니다.

1. 해당 항목은 이미 판단이 끝났습니다. 모듈 2a 에서 전용 CMK 를 도입해 **실제로
   해결**했으므로, 검사가 사라져도 현재 상태가 후퇴하지 않습니다.
2. 1건이라는 숫자를 **세어 보고** 받아들였습니다. 중복을 제거할 때 교집합만 보고
   차집합을 세지 않으면 커버리지가 조용히 줄어듭니다. 이 ADR 의 실질적인 내용은
   "6:1 이었고, 그 1 은 이미 고친 항목이었다" 는 숫자입니다.

## 전제조건이었던 것

`.trivyignore.yaml` 에는 `expired_at` 이 있었습니다. 기한이 지나면 항목이 다시
발견사항으로 올라옵니다. Checkov 인라인 억제에는 그 장치가 없어서, 그대로 이관하면
**"영구 면제가 아니라 이 시점에 다시 판단한다는 약속" 이 사라집니다.**

이것이 가설이 아니라는 것을 작업 중에 확인했습니다. 2026-11-03, AWS-0011(CloudFront
WAF)의 `expired_at: 2026-11-01` 이 만료되어 게이트가 막혔습니다. 2주간 손을 대지
않았는데 기한 장치가 "다시 판단하라" 고 물어왔고, 그 결과 WAF 적용 결정을 더 미루지
못했습니다. 사람의 기억이 아니라 기계가 약속을 지킨 사례입니다.

그래서 역할 분리보다 `scripts/check-suppressions.py` 를 먼저 만들었습니다. 이 도구가
Checkov 억제 주석에 근거(30자 이상)와 기한 표기(`permanent` 또는
`revisit=YYYY-MM-DD`)를 요구하고, 기한이 지난 항목을 CI 실패로 만듭니다. 그 장치가
생긴 뒤에야 이관이 손실 없는 작업이 되었습니다.

**순서가 결론의 일부입니다.** 기한 강제력 없이 이관하면 중복은 사라지지만 규율도
사라집니다.

## 결과

- Terraform 억제의 근거가 코드 바로 옆 한 곳에만 존재합니다
- 억제마다 기한 또는 영구 표기가 강제되고, 만료는 기계가 잡습니다
- 같은 사안이 Security 탭에 두세 번 올라오지만, **게이트는 한 번만** 걸립니다
- AWS-0136 에 해당하는 검사는 없습니다. 이미 고친 항목이라는 전제가 깨지면
  (예: SNS 토픽을 AWS 관리형 키로 되돌리면) 아무도 지적하지 않습니다
