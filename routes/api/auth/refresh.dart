import 'package:dart_frog/dart_frog.dart';
import '../../../services/database_service.dart';
import '../../../utils/jwt_utils.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method.value != 'POST') {
    return _error('Method not allowed', statusCode: 405);
  }

  try {
    await DatabaseService.startDb();

    final body = await context.request.json() as Map<String, dynamic>;
    final refreshToken = body['refresh_token'] as String?;

    if (refreshToken == null || refreshToken.isEmpty) {
      return _error('Refresh token is required');
    }

    final payload = JwtUtils.verifyRefreshToken(refreshToken);
    if (payload == null) {
      return _error('Invalid or expired refresh token', statusCode: 401);
    }

    final stored = await DatabaseService.refreshTokens
        .findOne({'token': refreshToken});
    if (stored == null) {
      return _error('Refresh token not found', statusCode: 401);
    }

    final userId = payload['user_id'] as String;
    final newAccessToken = JwtUtils.generateAccessToken(userId);

    return Response.json(
      body: {
        'success': true,
        'message': 'Token refreshed',
        'data': {'access_token': newAccessToken},
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