provider "aws" {
  version = "~> 3.0"
  region  = "ap-northeast-2"
}

resource "aws_s3_bucket" "lambda-bucket" {
  bucket = "jsp-lambda-code-bucket"
  acl    = "private"


  tags = {
    Name        = "jsp@hashicorp.com"
    Environment = "Dev"
  }
}
