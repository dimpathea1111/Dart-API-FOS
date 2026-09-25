// import 'package:dart_frog/dart_frog.dart';
// import 'package:mongo_dart/mongo_dart.dart';
// import 'package:dotenv/dotenv.dart';

// class DatabaseService {
//   static late Db _db;
//   static bool _isConnected = false;
//   static final _env = DotEnv(includePlatformEnvironment: true)..load();

//   static Db get db => _db;
//   static bool get isConnected => _isConnected;

//   static Future<void> startDb() async {
//     if (_isConnected) return;

//     final uri = _env['MONGODB_URI'] ?? 'mongodb://localhost:27017/food_order_db';
//     _db = await Db.create(uri);
//     await _db.open();
//     _isConnected = true;

//     await users.createIndex(keys: {'email': 1}, unique: true);
//     await users.createIndex(keys: {'phone': 1}, unique: true, sparse: true);
//     await otpCodes.createIndex(keys: {'email': 1});
//     await refreshTokens.createIndex(keys: {'token': 1}, unique: true);

//     print('✅ Connected to MongoDB - food_order_db');
//   }

//   static Future<void> closeDb() async {
//     if (_isConnected) {
//       await _db.close();
//       _isConnected = false;
//       print('🔒 Disconnected from MongoDB');
//     }
//   }

//   // Collections
//   static DbCollection get users => _db.collection('users');
//   static DbCollection get restaurants => _db.collection('restaurants');
//   static DbCollection get foods => _db.collection('foods');
//   static DbCollection get menu => _db.collection('menu');
//   static DbCollection get orders => _db.collection('orders');
//   static DbCollection get reviews => _db.collection('reviews');
//   static DbCollection get addresses => _db.collection('addresses');
//   static DbCollection get categories => _db.collection('categories');
//   static DbCollection get otpCodes => _db.collection('otp_codes');
//   static DbCollection get refreshTokens => _db.collection('refresh_tokens');

//   // ⭐ Helper សម្រាប់ Routes ចាស់ៗ
//   static Future<Response> withDb(
//     RequestContext context,
//     Future<Response> Function() callback,
//   ) async {
//     try {
//       await startDb();
//       return await callback();
//     } catch (e) {
//       return Response.json(
//         statusCode: 500,
//         body: {'success': false, 'message': 'Database error: $e'},
//       );
//     }
//   }

//   static String objectIdToString(dynamic id) {
//     if (id is ObjectId) return id.toHexString();
//     return id.toString();
//   }

//   static Map<String, dynamic> cleanDocument(Map<String, dynamic> doc) {
//   final clean = <String, dynamic>{};

//   doc.forEach((key, value) {
//     // បម្លែង ObjectId ទៅ String
//     if (value is ObjectId) {
//       clean[key] = value.toHexString();
//     }
//     // បម្លែង DateTime ទៅ ISO String
//     else if (value is DateTime) {
//       clean[key] = value.toIso8601String();
//     }
//     // បម្លែង List ដែលមាន ObjectId
//     else if (value is List) {
//       clean[key] = value.map((item) {
//         if (item is ObjectId) return item.toHexString();
//         if (item is DateTime) return item.toIso8601String();
//         if (item is Map) return cleanDocument(item.cast<String, dynamic>());
//         return item;
//       }).toList();
//     }
//     // បម្លែង Map ដែលមាន ObjectId
//     else if (value is Map) {
//       clean[key] = cleanDocument(value.cast<String, dynamic>());
//     }
//     // Values ផ្សេងទៀត
//     else {
//       clean[key] = value;
//     }
//   });

//   // ប្តូរ _id ទៅ id
//   if (clean.containsKey('_id')) {
//     clean['id'] = clean['_id'];
//     clean.remove('_id');
//   }

//   return clean;
// }

// }

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

    final uri =
        _env['MONGODB_URI'] ?? 'mongodb://localhost:27017/food_order_db';
    _db = await Db.create(uri);
    await _db.open();
    _isConnected = true;

    // Create indexes
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

// ⭐ Collections ទាំងអស់
static DbCollection get users => _db.collection('users');
static DbCollection get restaurants => _db.collection('restaurants');
static DbCollection get menu => _db.collection('menu');
static DbCollection get menuOptions => _db.collection('menu_options');
static DbCollection get foods => _db.collection('foods');
static DbCollection get categories => _db.collection('categories');
static DbCollection get addresses => _db.collection('addresses');
static DbCollection get orders => _db.collection('orders');
static DbCollection get orderItems => _db.collection('order_items');              // ⭐ បន្ថែម
static DbCollection get orderStatusHistory => _db.collection('order_status_history');  // ⭐ បន្ថែម
static DbCollection get reviews => _db.collection('reviews');
static DbCollection get favorites => _db.collection('favorites');
static DbCollection get cart => _db.collection('cart');
static DbCollection get cartItems => _db.collection('cart_items');
static DbCollection get payments => _db.collection('payments');
static DbCollection get transactions => _db.collection('transactions');
static DbCollection get deliveryDrivers => _db.collection('delivery_drivers');
static DbCollection get deliveryAssignments => _db.collection('delivery_assignments');
static DbCollection get promotions => _db.collection('promotions');
static DbCollection get notifications => _db.collection('notifications');
static DbCollection get systemLogs => _db.collection('system_logs');
static DbCollection get otpCodes => _db.collection('otp_codes');
static DbCollection get cartItemOptions => _db.collection('cart_item_options');
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
  final clean = <String, dynamic>{};

  doc.forEach((key, value) {
    if (value is ObjectId) {
      clean[key] = value.toHexString();
    } else if (value is DateTime) {
      clean[key] = value.toIso8601String();
    } else if (value is List) {
      clean[key] = value.map((item) {
        if (item is ObjectId) return item.toHexString();
        if (item is DateTime) return item.toIso8601String();
        if (item is Map) return cleanDocument(item.cast<String, dynamic>());
        return item;
      }).toList();
    } else if (value is Map) {
      clean[key] = cleanDocument(value.cast<String, dynamic>());
    } else {
      clean[key] = value;
    }
  });

  if (clean.containsKey('_id')) {
    clean['id'] = clean['_id'];
    clean.remove('_id');
  }

  return clean;
}



}
