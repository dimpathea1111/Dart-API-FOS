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
      case 'PUT':
        return _handlePut(context);
      case 'PATCH':
        return _handlePatch(context);
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

  if (id != null && id.isNotEmpty) {
    return _getCartById(id);
  }
  if (userId != null && userId.isNotEmpty) {
    return _getCartByUser(userId);
  }
  return _getAllCarts(context);
}

Future<Response> _getAllCarts(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final allCarts = await DatabaseService.cart.find().toList();

    final data = <Map<String, dynamic>>[];
    for (final c in allCarts) {
      data.add(DatabaseService.cleanDocument(c));
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

Future<Response> _getCartById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid cart ID format', statusCode: 400);
    }

    final cartMap = await DatabaseService.cart
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (cartMap == null) {
      return _error('Cart not found', statusCode: 404);
    }

    final items = await DatabaseService.cartItems
        .find(where.eq('cart_id', ObjectId.fromHexString(id)))
        .toList();

    final itemsData = <Map<String, dynamic>>[];
    for (final item in items) {
      itemsData.add(DatabaseService.cleanDocument(item));
    }

    return Response.json(body: {
      'success': true,
      'data': {
        ...DatabaseService.cleanDocument(cartMap),
        'items': itemsData,
      },
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getCartByUser(String userId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(userId)) {
      return _error('Invalid user ID format', statusCode: 400);
    }

    final cartMap = await DatabaseService.cart
        .findOne(where.eq('user_id', ObjectId.fromHexString(userId)));

    if (cartMap == null) {
      return Response.json(body: {
        'success': true,
        'data': null,
        'message': 'No cart found for this user',
      });
    }

    final cartId = cartMap['_id'] as ObjectId;
    final items = await DatabaseService.cartItems
        .find(where.eq('cart_id', cartId))
        .toList();

    final itemsData = <Map<String, dynamic>>[];
    for (final item in items) {
      itemsData.add(DatabaseService.cleanDocument(item));
    }

    return Response.json(body: {
      'success': true,
      'data': {
        ...DatabaseService.cleanDocument(cartMap),
        'items': itemsData,
      },
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

    if (userId == null || userId.isEmpty) {
      return _error('user_id is required');
    }
    if (!ObjectId.isValidHexId(userId)) {
      return _error('Invalid user ID format');
    }
    if (restaurantId == null || restaurantId.isEmpty) {
      return _error('restaurant_id is required');
    }
    if (!ObjectId.isValidHexId(restaurantId)) {
      return _error('Invalid restaurant ID format');
    }

    final existing = await DatabaseService.cart.findOne({
      'user_id': ObjectId.fromHexString(userId),
    });

    if (existing != null) {
      return _error('User already has a cart', statusCode: 409);
    }

    final cartData = {
      'user_id': ObjectId.fromHexString(userId),
      'restaurant_id': ObjectId.fromHexString(restaurantId),
      'created_at': DateTime.now(),
      'updated_at': DateTime.now(),
      'expires_at': DateTime.now().add(const Duration(days: 7)),
    };

    final result = await DatabaseService.cart.insertOne(cartData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Cart created successfully',
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

// ==================== PUT ====================
Future<Response> _handlePut(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];

  if (id == null || id.isEmpty) {
    return _error('id is required for PUT', statusCode: 400);
  }

  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid cart ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.cart
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Cart not found', statusCode: 404);
    }

    final restaurantId = body['restaurant_id'] as String?;
    if (restaurantId == null || restaurantId.isEmpty) {
      return _error('restaurant_id is required for PUT');
    }
    if (!ObjectId.isValidHexId(restaurantId)) {
      return _error('Invalid restaurant ID format');
    }

    var modifier = modify.set(
      'restaurant_id',
      ObjectId.fromHexString(restaurantId),
    );
    modifier = modifier.set('updated_at', DateTime.now());

    await DatabaseService.cart.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.cart
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Cart updated successfully',
      'data': updated != null ? DatabaseService.cleanDocument(updated) : null,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== PATCH ====================
Future<Response> _handlePatch(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];

  if (id == null || id.isEmpty) {
    return _error('id is required for PATCH', statusCode: 400);
  }

  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid cart ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.cart
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Cart not found', statusCode: 404);
    }

    var modifier = modify.set('updated_at', DateTime.now());
    var hasUpdate = false;

    if (body.containsKey('restaurant_id')) {
      final v = body['restaurant_id'] as String?;
      if (v == null || !ObjectId.isValidHexId(v)) {
        return _error('Invalid restaurant ID format');
      }
      modifier = modifier.set('restaurant_id', ObjectId.fromHexString(v));
      hasUpdate = true;
    }

    if (body.containsKey('expires_at')) {
      modifier = modifier.set('expires_at', body['expires_at']);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.cart.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.cart
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Cart partially updated',
      'data': updated != null ? DatabaseService.cleanDocument(updated) : null,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== DELETE ====================
Future<Response> _handleDelete(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];

  if (id == null || id.isEmpty) {
    return _error('id is required for DELETE', statusCode: 400);
  }

  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid cart ID format', statusCode: 400);
    }

    final existing = await DatabaseService.cart
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Cart not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      await DatabaseService.cartItems
          .deleteMany({'cart_id': ObjectId.fromHexString(id)});

      await DatabaseService.cart
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));

      return Response.json(body: {
        'success': true,
        'message': 'Cart and items deleted permanently',
      });
    } else {
      await DatabaseService.cartItems
          .deleteMany({'cart_id': ObjectId.fromHexString(id)});

      await DatabaseService.cart.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify.set('updated_at', DateTime.now()),
      );

      return Response.json(body: {
        'success': true,
        'message': 'Cart cleared (items removed)',
      });
    }
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