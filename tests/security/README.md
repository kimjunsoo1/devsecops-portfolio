# 보안 게이트 침투 테스트

**이 디렉터리의 코드는 의도적으로 취약합니다. 절대 apply 하거나 배포하지 마세요.**

파이프라인의 각 게이트가 실제로 차단하는지 확인하기 위한 시험 대상입니다.
main 에 머지되지 않습니다 — PR 이 빨간불인 것을 확인한 뒤 닫습니다.

## 무엇을 시험하는가

| 파일 | 심는 취약점 | 잡아야 할 게이트 |
|---|---|---|
| `vulnerable.tf` | 퍼블릭 S3 버킷, 0.0.0.0/0 에 열린 22번 포트, 암호화 없음 | Trivy misconfig (HIGH/CRITICAL) |
| `package-lock.json` | 알려진 취약점이 있는 lodash 4.17.20 | Trivy vuln (HIGH) |
| `vulnerable-app.js` | 명령 주입, eval, 하드코딩된 자격증명 | Semgrep |

## 실행 방법

`docs/security-testing.md` 참조.
