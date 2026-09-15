import 'package:dart_frog/dart_frog.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../../../models/user.dart';
import '../../../services/database_service.dart';
import '../../../utils/jwt_utils.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method.value != 'POST') {
    return _error('Method not allowed', statusCode: 405);
  }

  try {
    await DatabaseService.startDb();

    final body = await context.request.json() as Map<String, dynamic>;
    final email = (body['email'] as String?)?.trim().toLowerCase();
    final password = body['password'] as String?;

    if (email == null || email.isEmpty) return _error('Email is required');
    if (password == null || password.isEmpty) {
      return _error('Password is required');
    }

    final userMap = await DatabaseService.users.findOne({'email': email});
    if (userMap == null) {
      return _error('Invalid email or password', statusCode: 401);
    }

    final user = User.fromMap(userMap);

    if (!BCrypt.checkpw(password, user.passwordHash)) {
      return _error('Invalid email or password', statusCode: 401);
    }

    await DatabaseService.users.updateOne(
      where.eq('_id', user.id),
      modify.set('last_login', DateTime.now()),
    );

    final userId = user.id!.toHexString();
    final accessToken = JwtUtils.generateAccessToken(userId);
    final refreshToken = JwtUtils.generateRefreshToken(userId);

    await DatabaseService.refreshTokens.insertOne({
      'token': refreshToken,
      'user_id': user.id,
      'created_at': DateTime.now(),
      'expires_at': DateTime.now().add(const Duration(days: 7)),
    });

    return Response.json(
      body: {
        'success': true,
        'message': 'Login successful',
        'data': {
          'user': user.toJson(),
          'access_token': accessToken,
          'refresh_token': refreshToken,
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