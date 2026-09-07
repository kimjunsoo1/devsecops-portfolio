# ---------------------------------------------------------------------------
# CloudFront 배포.
#
# 도메인이 아직 없으므로 CloudFront 기본 인증서와 기본 도메인
# (xxxxxxxx.cloudfront.net)을 씁니다.
# 도메인을 사면 ACM 인증서(us-east-1)와 aliases 두 줄만 추가하면 됩니다.
# ---------------------------------------------------------------------------

# OAC(Origin Access Control)는 CloudFront 가 S3 에 SigV4 로 서명해 요청하게 합니다.
# 구식인 OAI 를 대체한 방식이고, KMS 암호화 버킷도 지원합니다.
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.project}-oac"
  description                       = "OAC for ${var.project} site bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------------------------------------------------------------------------
# 디렉터리 인덱스 처리.
#
# Astro 는 /blog/ 를 /blog/index.html 로 빌드합니다.
# S3 웹사이트 엔드포인트라면 알아서 index.html 을 찾아주지만,
# OAC 로 붙는 REST 엔드포인트는 그런 기능이 없어서 /blog/ 요청이 그대로
# 존재하지 않는 키가 되어 403 이 납니다.
#
# 뷰어 요청 단계에서 URI 를 다시 써줍니다.
# CloudFront Functions 는 월 200만 호출까지 무료입니다.
# ---------------------------------------------------------------------------
resource "aws_cloudfront_function" "rewrite_index" {
  name    = "${var.project}-rewrite-index"
  runtime = "cloudfront-js-2.0"
  comment = "Append index.html to directory-style URIs"
  publish = true

  code = <<-JS
    function handler(event) {
        var request = event.request;
        var uri = request.uri;

        if (uri.charAt(uri.length - 1) === '/') {
            request.uri = uri + 'index.html';
        } else if (uri.lastIndexOf('.') < uri.lastIndexOf('/')) {
            request.uri = uri + '/index.html';
        }

        return request;
    }
  JS
}

# AWS 관리형 정책을 이름으로 참조합니다. ID 를 하드코딩하는 것보다 읽기 좋습니다.
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

# HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy 등을
# 응답에 자동으로 붙입니다. 7주차 ZAP 스캔에서 바로 점수로 돌아옵니다.
data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = "${var.project} static site"
  default_root_object = "index.html"

  # 아시아·북미·유럽 엣지만 사용합니다. 전체(PriceClass_All)보다 쌉니다.
  price_class = "PriceClass_200"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id = "s3-site"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    # HTTP 로 와도 HTTPS 로 넘깁니다.
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite_index.arn
    }
  }

  # 없는 키에 대해 S3 는 403 을 돌려줍니다(404 가 아닙니다).
  # 버킷에 무엇이 있는지 알려주지 않기 위한 동작이라, 우리가 404 로 바꿔줍니다.
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # 도메인을 붙이면 이 블록이 ACM 인증서 참조로 바뀝니다.
    cloudfront_default_certificate = true
  }
}
