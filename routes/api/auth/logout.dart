import 'package:dart_frog/dart_frog.dart';
import '../../../services/database_service.dart';

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

    await DatabaseService.refreshTokens.deleteOne({'token': refreshToken});

    return Response.json(
      body: {'success': true, 'message': 'Logout successful'},
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