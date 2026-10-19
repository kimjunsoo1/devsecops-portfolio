terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # 부분 설정(partial configuration).
  # 나머지 값은 backend.hcl 에서 주입합니다:
  #   terraform init -backend-config=backend.hcl
  # 버킷 이름에 계정 ID 가 들어가므로 퍼블릭 리포지토리에 커밋하지 않습니다.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
