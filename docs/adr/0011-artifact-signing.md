# 0011. 배포 산출물을 서명하고 검증을 게이트로 건다

- 상태: 채택
- 날짜: 2026-11-13
- 관련: `.github/workflows/deploy.yml`, `.github/workflows/signing-tamper-test.yml`,
  `docs/evidence/week6-*.txt`

## 맥락

5주차까지의 통제는 "배포되는 코드가 안전한가"(스캐너)와 "배포 경로가 안전한가"
(OIDC, OAC)를 봤다. 안 본 것이 하나 있었다 — **배포되는 산출물이 우리 CI 가
만든 바로 그것인가.** 빌드와 S3 업로드 사이에서 dist 가 바뀌어도 아무도 몰랐다.

정적 사이트라 런타임 컨테이너가 없으므로, 공급망 통제는 산출물 자체의 무결성과
출처를 겨냥한다. SBOM(모듈 1)이 "무엇이 들어갔나"를 기록하고, 서명(모듈 2)이
"누가 만들었나"를 보증하며, 검증 게이트가 그것을 강제한다.

## 결정

배포 워크플로를 두 잡으로 나눈다.

```
build:   빌드 → dist 압축 → SBOM → cosign sign-blob (keyless)
                                         ↓ artifact (tarball + 서명 번들)
deploy:  검증 게이트 → 통과해야만 S3 sync
```

**왜 두 잡인가.** 서명과 검증이 같은 잡 안에 있으면 중간에 바뀔 틈이 없어 검증이
통과할 수밖에 없다. artifact 가 잡 경계를 건너야, 검증이 "build 가 서명한 그
산출물이 변조 없이 왔는지"를 실제로 확인한다.

**keyless 서명.** cosign 이 GitHub OIDC 토큰으로 서명한다. 관리할 개인키가 없다.
Fulcio 가 발급한 단명 인증서에 워크플로 신원이 박히고, 서명은 Rekor 투명성 로그에
기록된다. 검증은 그 신원이 기대값과 일치하는지 본다.

**신원 경계.** 검증은 서명 인증서의 SAN 이 다음과 일치해야만 통과한다.

```
https://github.com/kimjunsoo1/devsecops-portfolio/.github/workflows/deploy.yml@refs/heads/main
issuer: https://token.actions.githubusercontent.com
```

즉 "main 브랜치의 이 워크플로가 서명한 것만" 배포한다. 다른 브랜치, 다른
워크플로, 외부자가 서명하면 URI 가 달라 거부된다. 5주차 OIDC trust policy 와 같은
완전 일치 경계를 서명 계층에 세운 것이다. regexp 는 실제 인증서 SAN 을 번들에서
추출해 눈으로 확인한 뒤 확정했다 - 추측으로 박지 않았다.

## 검증 — 서명이 실제로 막는가

"정상 서명이 통과한다"만으로는 통제가 증명되지 않는다. 변조된 산출물이 거부되는
것을 봐야 한다. tarball 의 한 바이트를 바꿔 검증이 거부(exit 비0)하는지 확인했다.

| 대상 | exit | 결과 |
|---|---|---|
| 정상 산출물 | 0 | Verified OK |
| 변조 산출물(1바이트) | 1 | invalid signature, 거부 |

이 변조 테스트를 `signing-tamper-test.yml` 로 남겨, 서명 로직을 바꿀 때(cosign
업그레이드 등) 회귀를 잡는다. 5주차 침투 검증과 같은 패턴 - 통제를 공격으로
검증하고 그 테스트를 남긴다. 거부가 성공이므로, 이 워크플로가 초록이면 "서명이
변조를 막는다"는 뜻이다.

## 직접 구현에서 공식 액션으로

모듈 1 에서 syft 를 curl 로 직접 받아 체크섬 검증 후 설치했으나, CI 에서 재현
불가한 다운로드 실패가 났다(로컬은 http 200 으로 31MB 정상 수신). 직접 구현한
설치 스크립트는 유지보수 부담이자 공격면이므로, 공식 액션(anchore/sbom-action,
sigstore/cosign-installer)을 SHA 로 고정해 쓰는 쪽으로 바꿨다. 신뢰 범위를 좁히고
고정하는 것이 공급망 원칙에 맞는다.

## 받아들인 것

- 서명 대상은 dist tarball 이다. SBOM 자체는 서명하지 않는다(리포트 전용 유지).
  SBOM attestation 은 이후 확장 대상이다.
- Rekor 공개 로그에 dist 해시가 올라간다. 콘텐츠가 아니라 해시이므로 정적 사이트에
  문제없다. 비공개가 필요하면 번들만 쓰는 방식으로 바꿀 수 있으나, 비가역
  (non-repudiation) 증거가 공개 로그에 남는 쪽을 택했다.
- upload-artifact v7 과 download-artifact v7 로 메이저를 맞췄다. v8 download 가
  있었으나 섞지 않았다 - artifact 포맷 호환은 사람이 맞춰야 한다.
