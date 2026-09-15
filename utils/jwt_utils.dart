import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

class JwtUtils {
  static const String _accessSecret = 'tastygo_super_secret_key_2024';
  static const String _refreshSecret = 'tastygo_refresh_secret_key_2024';

  static String generateAccessToken(String userId) {
    final jwt = JWT({
      'user_id': userId,
      'type': 'access',
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    return jwt.sign(SecretKey(_accessSecret), expiresIn: Duration(minutes: 15));
  }

  static String generateRefreshToken(String userId) {
    final jwt = JWT({
      'user_id': userId,
      'type': 'refresh',
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    return jwt.sign(SecretKey(_refreshSecret), expiresIn: Duration(days: 7));
  }

  static Map<String, dynamic>? verifyAccessToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_accessSecret));
      return jwt.payload as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? verifyRefreshToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_refreshSecret));
      return jwt.payload as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}