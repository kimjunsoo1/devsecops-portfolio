output "site_bucket" {
  description = "정적 사이트 원본 버킷"
  value       = aws_s3_bucket.site.id
}

output "distribution_id" {
  description = "CloudFront 배포 ID. 캐시 무효화에 씁니다."
  value       = aws_cloudfront_distribution.site.id
}

output "site_url" {
  description = "사이트 주소"
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}
