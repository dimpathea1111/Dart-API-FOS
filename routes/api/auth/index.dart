import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) {
  return Response.json(body: {
    'success': true,
    'message': 'TastyGo Authentication API',
    'version': '1.0.0',
    'endpoints': {
      'register': 'POST /api/auth/register',
      'login': 'POST /api/auth/login',
      'logout': 'POST /api/auth/logout',
      'refresh': 'POST /api/auth/refresh',
      'forgot_password': 'POST /api/auth/forgot-password',
      'verify_otp': 'POST /api/auth/verify-otp',
      'reset_password': 'POST /api/auth/reset-password',
    },
  });
}