import 'package:dart_frog/dart_frog.dart';
import '../services/database_service.dart';

bool _initialized = false;

Handler middleware(Handler handler) {
  return handler.use(requestLogger()).use(initMiddleware());
}

Middleware initMiddleware() {
  return (handler) {
    return (context) async {
      if (!_initialized) {
        await DatabaseService.startDb();
        _initialized = true;
      }
      return handler(context);
    };
  };
}

Middleware requestLogger() {
  return (handler) {
    return (context) async {
      final stopwatch = Stopwatch()..start();
      final response = await handler(context);
      stopwatch.stop();

      print(
        '[${context.request.method.value}] '
        '${context.request.uri.path} → ${response.statusCode} '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
      return response;
    };
  };
}