import 'package:dart_frog/dart_frog.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:dotenv/dotenv.dart';

class DatabaseService {
  static late Db _db;
  static bool _isConnected = false;
  static final _env = DotEnv(includePlatformEnvironment: true)..load();

  static Db get db => _db;
  static bool get isConnected => _isConnected;

  static Future<void> startDb() async {
    if (_isConnected) return;

    final uri = _env['MONGODB_URI'] ?? 'mongodb://localhost:27017/food_order_db';
    _db = await Db.create(uri);
    await _db.open();
    _isConnected = true;

    await users.createIndex(keys: {'email': 1}, unique: true);
    await users.createIndex(keys: {'phone': 1}, unique: true, sparse: true);
    await otpCodes.createIndex(keys: {'email': 1});
    await refreshTokens.createIndex(keys: {'token': 1}, unique: true);

    print('✅ Connected to MongoDB - food_order_db');
  }

  static Future<void> closeDb() async {
    if (_isConnected) {
      await _db.close();
      _isConnected = false;
      print('🔒 Disconnected from MongoDB');
    }
  }

  // Collections
  static DbCollection get users => _db.collection('users');
  static DbCollection get restaurants => _db.collection('restaurants');
  static DbCollection get foods => _db.collection('foods');
  static DbCollection get orders => _db.collection('orders');
  static DbCollection get reviews => _db.collection('reviews');
  static DbCollection get addresses => _db.collection('addresses');
  static DbCollection get categories => _db.collection('categories');
  static DbCollection get otpCodes => _db.collection('otp_codes');
  static DbCollection get refreshTokens => _db.collection('refresh_tokens');

  // ⭐ Helper សម្រាប់ Routes ចាស់ៗ
  static Future<Response> withDb(
    RequestContext context,
    Future<Response> Function() callback,
  ) async {
    try {
      await startDb();
      return await callback();
    } catch (e) {
      return Response.json(
        statusCode: 500,
        body: {'success': false, 'message': 'Database error: $e'},
      );
    }
  }

  static String objectIdToString(dynamic id) {
    if (id is ObjectId) return id.toHexString();
    return id.toString();
  }

  static Map<String, dynamic> cleanDocument(Map<String, dynamic> doc) {
    final clean = Map<String, dynamic>.from(doc);
    if (clean['_id'] is ObjectId) {
      clean['id'] = clean['_id'].toHexString();
      clean.remove('_id');
    }
    return clean;
  }
}