terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# CLOUDFRONT 스코프 WAF Web ACL 은 us-east-1 에만 만들 수 있습니다.
# ACM 인증서도 같은 제약을 받으므로 도메인을 붙일 때 다시 쓰게 됩니다.
#
# 4주차 모듈 1 에서 tflint 가 미사용이라고 지적해 지웠던 블록입니다.
# "나중에 쓸지도 모른다" 는 이유로 남기지 않고 지웠고, 실제로 필요해진
# 지금 히스토리에서 되살렸습니다. 죽은 코드를 지우는 판단은 유효했습니다.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}
