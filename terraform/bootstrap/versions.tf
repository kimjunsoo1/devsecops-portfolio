terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # 부트스트랩만 예외적으로 로컬 state 를 씁니다.
  # (state 를 담을 버킷 자체를 만드는 단계라 원격 백엔드를 쓸 수 없음)
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      Component = "bootstrap"
      ManagedBy = "terraform"
      Owner     = var.owner
    }
  }
}
