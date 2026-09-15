// import 'package:dart_frog/dart_frog.dart';

// Response onRequest(RequestContext context) {
//   return Response(body: 'Welcome to Dart Frog!');
// }
import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) {
  return Response.json(body: {
    'name': 'TastyGo API',
    'version': '1.0.0',
    'status': 'running',
    'timestamp': DateTime.now().toIso8601String(),
    'endpoints': {
      'auth': '/api/auth',
      'users': '/api/users',
      'restaurants': '/api/restaurants',
      'foods': '/api/foods',
      'orders': '/api/orders',
      'addresses': '/api/addresses',
      'reviews': '/api/reviews',
    },
  });
}