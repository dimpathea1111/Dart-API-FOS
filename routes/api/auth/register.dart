import 'package:dart_frog/dart_frog.dart';
import 'package:bcrypt/bcrypt.dart';
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
    final name = (body['name'] as String?)?.trim();
    final email = (body['email'] as String?)?.trim().toLowerCase();
    final phone = (body['phone'] as String?)?.trim();
    final password = body['password'] as String?;

    if (name == null || name.isEmpty) return _error('Name is required');
    if (email == null || email.isEmpty || !_isValidEmail(email)) {
      return _error('Valid email is required');
    }
    if (password == null || password.length < 6) {
      return _error('Password must be at least 6 characters');
    }

    final existing = await DatabaseService.users.findOne({'email': email});
    if (existing != null) {
      return _error('Email already registered', statusCode: 409);
    }

    if (phone != null && phone.isNotEmpty) {
      final existingPhone =
          await DatabaseService.users.findOne({'phone': phone});
      if (existingPhone != null) {
        return _error('Phone already registered', statusCode: 409);
      }
    }

    final passwordHash = BCrypt.hashpw(password, BCrypt.gensalt());

    final user = User(
      name: name,
      email: email,
      phone: phone,
      passwordHash: passwordHash,
    );

    final result = await DatabaseService.users.insertOne(user.toMap());
    final String userId = result.id.toHexString() as String;

    final String accessToken = JwtUtils.generateAccessToken(userId);
    final String refreshToken = JwtUtils.generateRefreshToken(userId);

    await DatabaseService.refreshTokens.insertOne({
      'token': refreshToken,
      'user_id': result.id,
      'created_at': DateTime.now(),
      'expires_at': DateTime.now().add(const Duration(days: 7)),
    });

    return Response.json(
      statusCode: 201,
      body: {
        'success': true,
        'message': 'Registration successful',
        'data': {
          'user': {
            'id': userId,
            'name': name,
            'email': email,
            'phone': phone,
          },
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

bool _isValidEmail(String email) {
  return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
}