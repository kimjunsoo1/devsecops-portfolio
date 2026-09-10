# 보안 백로그

차단하지는 않지만 해결되지 않은 항목. Security 탭에 계속 보이게 두어
"잊혀서 사라지는" 일이 없게 합니다.

| ID | 내용 | 등급 | 처리 시점 | 메모 |
|---|---|---|---|---|
| AWS-0010 | CloudFront 액세스 로깅 미설정 | medium | 7주차 | 아래 참조 |
| AWS-0089 | S3 버킷 액세스 로깅 미설정 (3개 버킷) | low | 미정 | CloudTrail 관리 이벤트가 버킷 수준 API 호출을 이미 기록. 중복 대비 스토리지 비용이 커서 보류 |
| AWS-0162 | CloudTrail 을 CloudWatch Logs 로도 전송 | low | 6주차 | 메트릭 필터로 루트 로그인·IAM 변경 알람을 걸 때 함께 구성 |
| semgrep aws-insecure-cloudfront-distribution-tls-version | CloudFront 최소 TLS 버전이 TLSv1 | warning | 도메인 구입 시 | 아래 참조 |

## AWS-0010 — CloudFront 액세스 로깅

고치려다 제약을 발견해서 미룬 항목입니다.

CloudFront 표준 로깅(v1)은 대상 S3 버킷에 **ACL 이 활성화되어 있을 것**을
요구합니다. 그런데 우리는 모든 버킷을 ACL 비활성(BucketOwnerEnforced) 기본값으로
두고 있고, 계정 수준 퍼블릭 액세스 차단도 켜져 있습니다.
로깅을 켜려고 ACL 을 되살리는 것은 더 큰 통제를 약화시키는 교환입니다.

표준 로깅 v2 는 ACL 없이 CloudWatch Logs 로 보낼 수 있지만 수집 비용이 붙습니다.
7주차 관측 작업에서 대시보드·알람과 함께 한 번에 설계하는 것이 맞다고 판단했습니다.

## CloudFront 최소 TLS 버전

CloudFront 기본 인증서를 쓰는 동안에는 `minimum_protocol_version` 을 설정할 수
없습니다. AWS 가 그 값을 `TLSv1` 로 고정합니다.

이 값을 올리려면 사용자 지정 도메인과 ACM 인증서(us-east-1)가 필요합니다.
도메인을 구입하는 시점에 `viewer_certificate` 블록을 교체하면서
`minimum_protocol_version = "TLSv1.2_2021"` 을 함께 넣습니다.

실제 노출은 제한적입니다. CloudFront 기본 인증서도 TLS 1.2/1.3 을 지원하며,
`TLSv1` 은 그보다 낮은 버전으로도 접속할 수 있다는 뜻입니다.
현대 브라우저는 모두 1.2 이상을 씁니다.

## SNS 암호화와 CloudWatch 알람의 충돌 (6주차에 결정)

AWS-0095 대응으로 SNS 주제에 `alias/aws/sns` 암호화를 걸었다.
그런데 이 키는 AWS 관리형이라 키 정책을 수정할 수 없고,
CloudWatch 알람이 발행하려면 `cloudwatch.amazonaws.com` 에
`kms:GenerateDataKey*` 가 필요하다. 알람은 에러 없이 조용히 실패한다.

현재는 예산 알림이 SNS 를 거치지 않고 이메일로 직접 가므로 영향이 없다.
6주차에 알람을 배선할 때 셋 중 하나를 고른다.

- 고객 관리 KMS 키 (월 $1 + 요청 과금)
- 암호화 해제 후 AWS-0095 를 사유와 함께 억제
- SNS 없이 이메일 직접 전송
