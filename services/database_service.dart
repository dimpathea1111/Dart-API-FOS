import 'package:dart_frog/dart_frog.dart';
import 'package:mongo_dart/mongo_dart.dart';

class DatabaseService {
  // តភ្ជាប់ទៅ MongoDB localhost
  static final Db _db = Db('mongodb://localhost:27017/food_order_db');

  // បើកការតភ្ជាប់
  static Future<void> startDb() async {
    if (!_db.isConnected) {
      await _db.open();
      print('✅ Connected to MongoDB');
    }
  }

  // បិទការតភ្ជាប់
  static Future<void> closeDb() async {
    if (_db.isConnected) {
      await _db.close();
      print('🔒 Disconnected from MongoDB');
    }
  }

  // Collections
  static DbCollection get restaurants => _db.collection('restaurants');
  static DbCollection get foods => _db.collection('foods');
  static DbCollection get orders => _db.collection('orders');
  static DbCollection get users => _db.collection('users');

  // Helper: ប្រើសម្រាប់ Route ទាំងអស់
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
        body: {'error': 'Database error: $e'},
      );
    }
  }
}