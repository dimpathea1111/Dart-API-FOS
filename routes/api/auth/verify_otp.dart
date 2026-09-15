import 'package:dart_frog/dart_frog.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../../../services/database_service.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method.value != 'POST') {
    return _error('Method not allowed', statusCode: 405);
  }

  try {
    await DatabaseService.startDb();

    final body = await context.request.json() as Map<String, dynamic>;
    final email = (body['email'] as String?)?.trim().toLowerCase();
    final otp = (body['otp'] as String?)?.trim();

    if (email == null || email.isEmpty) {
      return _error('Email is required');
    }
    if (otp == null || otp.isEmpty) {
      return _error('OTP is required');
    }

    // ស្វែងរក OTP
    final otpDoc = await DatabaseService.otpCodes.findOne({
      'email': email,
      'otp': otp,
      'is_used': false,
    });

    if (otpDoc == null) {
      return _error('Invalid OTP');
    }

    // ⭐ ពិនិត្យ expiration (កែហើយ)
    final expiresAtValue = otpDoc['expires_at'];
    DateTime expiresAt;

    if (expiresAtValue is DateTime) {
      expiresAt = expiresAtValue;
    } else if (expiresAtValue is String) {
      expiresAt = DateTime.parse(expiresAtValue);
    } else {
      return _error('Invalid expiration date');
    }

    if (DateTime.now().isAfter(expiresAt)) {
      return _error('OTP expired');
    }

    // Mark as used
    await DatabaseService.otpCodes.updateOne(
      where.eq('_id', otpDoc['_id']),
      modify.set('is_used', true),
    );

    return Response.json(
      body: {
        'success': true,
        'message': 'OTP verified successfully',
        'data': {
          'email': email,
          'can_reset_password': true,
        },
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


// import 'package:dart_frog/dart_frog.dart';
// import 'package:mongo_dart/mongo_dart.dart';
// import '../../../services/database_service.dart';

// Future<Response> onRequest(RequestContext context) async {
//   if (context.request.method.value != 'POST') {
//     return _error('Method not allowed', statusCode: 405);
//   }

//   try {
//     await DatabaseService.startDb();

//     final body = await context.request.json() as Map<String, dynamic>;
//     final email = (body['email'] as String?)?.trim().toLowerCase();
//     final otp = (body['otp'] as String?)?.trim();

//     if (email == null || email.isEmpty) return _error('Email is required');
//     if (otp == null || otp.isEmpty) return _error('OTP is required');

//     final otpDoc = await DatabaseService.otpCodes.findOne({
//       'email': email,
//       'otp': otp,
//       'is_used': false,
//     });

//     if (otpDoc == null) return _error('Invalid OTP');

//     final expiresAt = otpDoc['expires_at'] as DateTime?;
//     if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
//       return _error('OTP expired');
//     }

//     await DatabaseService.otpCodes.updateOne(
//       where.eq('_id', otpDoc['_id']),
//       modify.set('is_used', true),
//     );

//     return Response.json(
//       body: {
//         'success': true,
//         'message': 'OTP verified successfully',
//         'data': {'email': email, 'can_reset_password': true},
//       },
//     );
//   } catch (e) {
//     return _error('Server error: $e', statusCode: 500);
//   }
// }

// Response _error(String message, {int statusCode = 400}) {
//   return Response.json(
//     statusCode: statusCode,
//     body: {'success': false, 'message': message},
//   );
// }