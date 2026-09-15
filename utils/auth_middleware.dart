import 'package:dart_frog/dart_frog.dart';
import 'jwt_utils.dart';

// ⭐ Syntax ថ្មី (សម្រាប់ Auth Routes)
Middleware authMiddleware() {
  return (handler) {
    return (context) async {
      final authHeader = context.request.headers['Authorization'];

      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response.json(
          statusCode: 401,
          body: {
            'success': false,
            'message': 'Missing or invalid Authorization header',
          },
        );
      }

      final token = authHeader.substring(7);
      final payload = JwtUtils.verifyAccessToken(token);

      if (payload == null) {
        return Response.json(
          statusCode: 401,
          body: {
            'success': false,
            'message': 'Invalid or expired token',
          },
        );
      }

      return handler(
        context.provide<String>(() => payload['user_id'] as String),
      );
    };
  };
}

// ⭐ Syntax ចាស់ (សម្រាប់ Routes ចាស់ៗ)
Handler authMiddlewareHandler(Handler handler) {
  return (context) {
    return Future<Response>(() async {
      final authHeader = context.request.headers['Authorization'];

      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response.json(
          statusCode: 401,
          body: {
            'success': false,
            'message': 'Missing or invalid authorization header',
          },
        );
      }

      final token = authHeader.substring(7);
      final payload = JwtUtils.verifyAccessToken(token);

      if (payload == null) {
        return Response.json(
          statusCode: 401,
          body: {
            'success': false,
            'message': 'Invalid or expired token',
          },
        );
      }

      final updatedContext = context.provide<String>(
        () => payload['user_id'] as String,
      );
      return handler(updatedContext);
    });
  };
}

String? getUserId(RequestContext context) {
  try {
    return context.read<String>();
  } catch (_) {
    return null;
  }
}