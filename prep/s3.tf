provider "aws" {
  version = "~> 3.0"
  region  = "ap-northeast-2"
}

provider "archive" {}

resource "aws_s3_bucket" "lambda-bucket" {
  bucket = "jsp-lambda-code-bucket"
  acl    = "private"


  tags = {
    Name        = "jsp@hashicorp.com"
    Environment = "Dev"
  }
}

# Archive a single file.

data "archive_file" "init" {
  type        = "zip"
  source_file = "../example/main.js"
  output_path = "./example.zip"
}

/*
resource "null_resource" "zip_file" {
  depends_on = [aws_s3_bucket.lambda-bucket]
 triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "zip example.zip ../example/main.js"
  }
}
*/

resource "aws_s3_bucket_object" "object" {
 # depends_on = [archive_file.init]
  bucket = aws_s3_bucket.lambda-bucket.bucket
  key    = "v${var.code_version}/example.zip"
  source = "./example.zip"

  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
 # etag = filemd5("./example.zip")
}
