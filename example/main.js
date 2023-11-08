'use strict'

exports.handler = function (event, context, callback) {
  var response = {
    statusCode: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
    },
    body: '<h1>AWS Serverless Deployment Sample</h1><hr><h2>안녕하세요, 현재 버전은 2_4_13입니다.</h2>',
  }
  callback(null, response)
}
