
resource "null_resource" "zip_file" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "zip exmple.zip ../example/main.js"
  }
}


resource "aws_s3_bucket_object" "object" {
  bucket = "jsp-lambda-code-bucket"
  key    = "v${var.code_version}/example.zip"
  source = "./example.zip"

  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  #etag = filemd5("example.zip")
}