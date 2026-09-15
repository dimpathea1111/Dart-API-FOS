import 'dart:math';
import 'package:dart_frog/dart_frog.dart';
import '../../../services/database_service.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method.value != 'POST') {
    return _error('Method not allowed', statusCode: 405);
  }

  try {
    await DatabaseService.startDb();

    final body = await context.request.json() as Map<String, dynamic>;
    final email = (body['email'] as String?)?.trim().toLowerCase();

    if (email == null || email.isEmpty) return _error('Email is required');

    final userMap = await DatabaseService.users.findOne({'email': email});
    if (userMap == null) {
      return _error('Email not found', statusCode: 404);
    }

    final otp = (Random().nextInt(900000) + 100000).toString();

    await DatabaseService.otpCodes.deleteMany({'email': email});
    await DatabaseService.otpCodes.insertOne({
      'email': email,
      'otp': otp,
      'created_at': DateTime.now(),
      'expires_at': DateTime.now().add(const Duration(minutes: 5)),
      'is_used': false,
    });

    print('📧 OTP for $email: $otp');

    return Response.json(
      body: {
        'success': true,
        'message': 'OTP sent successfully',
        'data': {'email': email, 'otp_debug': otp},
      },
    );
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Response _error(String message, {int statusCode = 400}) {
  return Response.json(
    statusCode: statusCode,
    body: {'success': false, 'message': message},
  );
}