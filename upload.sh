cd example
zip ../example.zip main.js
cd ..
aws s3 cp example.zip s3://dk-lambda-code-bucket/v1.0.0/example.zip