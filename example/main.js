'use strict'

exports.handler = function (event, context, callback) {
  var response = {
    statusCode: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
    },
    body: '<p>안녕하세요..... 버전은 1_0_7입니다.</p>',
  }
  callback(null, response)
}