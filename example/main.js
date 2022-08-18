'use strict'

exports.handler = function (event, context, callback) {
  var response = {
    statusCode: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
    },
    body: '<p>AWS Serverless Deployment Sample</p><p>Welcome.....  This is Version 2_3_3.</p>',
  }
  callback(null, response)
}
