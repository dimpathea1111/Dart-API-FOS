import 'package:dart_frog/dart_frog.dart';
import 'package:bcrypt/bcrypt.dart';
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
    final newPassword = body['new_password'] as String?;

    if (email == null || email.isEmpty) return _error('Email is required');
    if (newPassword == null || newPassword.length < 6) {
      return _error('Password must be at least 6 characters');
    }

    final userMap = await DatabaseService.users.findOne({'email': email});
    if (userMap == null) return _error('User not found', statusCode: 404);

    final passwordHash = BCrypt.hashpw(newPassword, BCrypt.gensalt());

    await DatabaseService.users.updateOne(
      where.eq('_id', userMap['_id']),
      modify
          .set('password_hash', passwordHash)
          .set('updated_at', DateTime.now()),
    );

    await DatabaseService.refreshTokens
        .deleteMany({'user_id': userMap['_id']});

    return Response.json(
      body: {'success': true, 'message': 'Password reset successfully'},
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