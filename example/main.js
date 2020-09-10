'use strict'

exports.handler = function (event, context, callback) {
  var response = {
    statusCode: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
    },
    body: '<p>안녕하세요..... 버전은 2_0_2입니다.</p>',
  }
  callback(null, response)
}