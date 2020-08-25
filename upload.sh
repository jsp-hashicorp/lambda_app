version=$TF_VAR_code_version

cd example
zip ../example.zip main.js
cd ..
aws s3 cp example.zip s3://dk-lambda-code-bucket/v${TF_VAR_code_version}/example.zip