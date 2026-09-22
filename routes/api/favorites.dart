import 'package:dart_frog/dart_frog.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../../services/database_service.dart';
import '../../utils/auth_middleware.dart';

Handler middleware(Handler handler) => authMiddlewareHandler(handler);

Future<Response> onRequest(RequestContext context) async {
  try {
    final method = context.request.method.value;

    switch (method) {
      case 'GET':
        return _handleGet(context);
      case 'POST':
        return _handlePost(context);
      case 'DELETE':
        return _handleDelete(context);
      default:
        return _error('Method not allowed', statusCode: 405);
    }
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== GET ====================
Future<Response> _handleGet(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];
  final userId = context.request.uri.queryParameters['user_id'];
  final restaurantId = context.request.uri.queryParameters['restaurant_id'];

  if (id != null && id.isNotEmpty) {
    return _getFavoriteById(id);
  }
  if (userId != null && userId.isNotEmpty) {
    return _getFavoritesByUser(userId);
  }
  if (restaurantId != null && restaurantId.isNotEmpty) {
    return _getFavoritesByRestaurant(restaurantId);
  }
  return _getAllFavorites(context);
}

Future<Response> _getAllFavorites(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allFavorites = await DatabaseService.favorites.find().toList();
    final favorites = allFavorites.skip(skip).take(limit).toList();
    final total = allFavorites.length;

    final data = <Map<String, dynamic>>[];
    for (final f in favorites) {
      data.add(DatabaseService.cleanDocument(f));
    }

    return Response.json(body: {
      'success': true,
      'data': data,
      'pagination': {
        'page': page,
        'limit': limit,
        'total': total,
        'total_pages': (total / limit).ceil(),
      },
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getFavoriteById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid favorite ID format', statusCode: 400);
    }

    final favoriteMap = await DatabaseService.favorites
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (favoriteMap == null) {
      return _error('Favorite not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(favoriteMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getFavoritesByUser(String userId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(userId)) {
      return _error('Invalid user ID format', statusCode: 400);
    }

    final favorites = await DatabaseService.favorites
        .find(where.eq('user_id', ObjectId.fromHexString(userId)))
        .toList();

    // ទាញ restaurant details សម្រាប់ favorite នីមួយៗ
    final data = <Map<String, dynamic>>[];
    for (final f in favorites) {
      final cleaned = DatabaseService.cleanDocument(f);
      final restaurantId = f['restaurant_id'];

      if (restaurantId is ObjectId) {
        final restaurant = await DatabaseService.restaurants
            .findOne(where.eq('_id', restaurantId));
        if (restaurant != null) {
          cleaned['restaurant'] = DatabaseService.cleanDocument(restaurant);
        }
      }
      data.add(cleaned);
    }

    return Response.json(body: {
      'success': true,
      'data': data,
      'count': data.length,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getFavoritesByRestaurant(String restaurantId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(restaurantId)) {
      return _error('Invalid restaurant ID format', statusCode: 400);
    }

    final favorites = await DatabaseService.favorites
        .find(where.eq(
          'restaurant_id',
          ObjectId.fromHexString(restaurantId),
        ))
        .toList();

    final data = <Map<String, dynamic>>[];
    for (final f in favorites) {
      data.add(DatabaseService.cleanDocument(f));
    }

    return Response.json(body: {
      'success': true,
      'data': data,
      'count': data.length,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== POST ====================
Future<Response> _handlePost(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final body = await context.request.json() as Map<String, dynamic>;
    final userId = body['user_id'] as String?;
    final restaurantId = body['restaurant_id'] as String?;

    if (userId == null || !ObjectId.isValidHexId(userId)) {
      return _error('Valid user_id is required');
    }
    if (restaurantId == null || !ObjectId.isValidHexId(restaurantId)) {
      return _error('Valid restaurant_id is required');
    }

    // Check if already favorited
    final existing = await DatabaseService.favorites.findOne({
      'user_id': ObjectId.fromHexString(userId),
      'restaurant_id': ObjectId.fromHexString(restaurantId),
    });

    if (existing != null) {
      return _error('Restaurant already in favorites', statusCode: 409);
    }

    final favoriteData = {
      'user_id': ObjectId.fromHexString(userId),
      'restaurant_id': ObjectId.fromHexString(restaurantId),
      'created_at': DateTime.now(),
    };

    final result = await DatabaseService.favorites.insertOne(favoriteData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Added to favorites',
      'data': {
        'id': result.id.toHexString(),
        'user_id': userId,
        'restaurant_id': restaurantId,
      },
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== DELETE ====================
Future<Response> _handleDelete(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];
  final userId = context.request.uri.queryParameters['user_id'];
  final restaurantId = context.request.uri.queryParameters['restaurant_id'];

  try {
    await DatabaseService.startDb();

    // Delete by ID
    if (id != null && id.isNotEmpty) {
      if (!ObjectId.isValidHexId(id)) {
        return _error('Invalid favorite ID format', statusCode: 400);
      }

      final existing = await DatabaseService.favorites
          .findOne(where.eq('_id', ObjectId.fromHexString(id)));
      if (existing == null) {
        return _error('Favorite not found', statusCode: 404);
      }

      await DatabaseService.favorites
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));

      return Response.json(body: {
        'success': true,
        'message': 'Removed from favorites',
      });
    }

    // Delete by user_id + restaurant_id
    if (userId != null && restaurantId != null) {
      if (!ObjectId.isValidHexId(userId)) {
        return _error('Invalid user ID format', statusCode: 400);
      }
      if (!ObjectId.isValidHexId(restaurantId)) {
        return _error('Invalid restaurant ID format', statusCode: 400);
      }

      final result = await DatabaseService.favorites.deleteOne({
        'user_id': ObjectId.fromHexString(userId),
        'restaurant_id': ObjectId.fromHexString(restaurantId),
      });

      if (result.nRemoved == 0) {
        return _error('Favorite not found', statusCode: 404);
      }

      return Response.json(body: {
        'success': true,
        'message': 'Removed from favorites',
      });
    }

    return _error('id OR (user_id + restaurant_id) is required');
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== HELPERS ====================
Response _error(String message, {int statusCode = 400}) {
  return Response.json(
    statusCode: statusCode,
    body: {'success': false, 'message': message},
  );
}