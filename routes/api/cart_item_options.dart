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
  final cartItemId = context.request.uri.queryParameters['cart_item_id'];
  final menuOptionId = context.request.uri.queryParameters['menu_option_id'];

  if (id != null && id.isNotEmpty) {
    return _getOptionById(id);
  }
  if (cartItemId != null && cartItemId.isNotEmpty) {
    return _getOptionsByCartItem(cartItemId);
  }
  if (menuOptionId != null && menuOptionId.isNotEmpty) {
    return _getOptionsByMenuOption(menuOptionId);
  }
  return _getAllOptions(context);
}

Future<Response> _getAllOptions(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allOptions =
        await DatabaseService.cartItemOptions.find().toList();
    final options = allOptions.skip(skip).take(limit).toList();
    final total = allOptions.length;

    final data = <Map<String, dynamic>>[];
    for (final o in options) {
      data.add(DatabaseService.cleanDocument(o));
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

Future<Response> _getOptionById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid option ID format', statusCode: 400);
    }

    final optionMap = await DatabaseService.cartItemOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (optionMap == null) {
      return _error('Cart item option not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(optionMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getOptionsByCartItem(String cartItemId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(cartItemId)) {
      return _error('Invalid cart item ID format', statusCode: 400);
    }

    final options = await DatabaseService.cartItemOptions
        .find(where.eq('cart_item_id', ObjectId.fromHexString(cartItemId)))
        .toList();

    // ទាញ menu option details
    final data = <Map<String, dynamic>>[];
    double totalAdjustment = 0;

    for (final o in options) {
      final cleaned = DatabaseService.cleanDocument(o);
      final menuOptionId = o['menu_option_id'];

      if (menuOptionId is ObjectId) {
        final menuOption = await DatabaseService.menuOptions
            .findOne(where.eq('_id', menuOptionId));
        if (menuOption != null) {
          cleaned['menu_option'] = DatabaseService.cleanDocument(menuOption);
        }
      }

      totalAdjustment +=
          (o['price_adjustment'] as num?)?.toDouble() ?? 0;
      data.add(cleaned);
    }

    return Response.json(body: {
      'success': true,
      'data': data,
      'count': data.length,
      'total_adjustment': totalAdjustment,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getOptionsByMenuOption(String menuOptionId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(menuOptionId)) {
      return _error('Invalid menu option ID format', statusCode: 400);
    }

    final options = await DatabaseService.cartItemOptions
        .find(where.eq(
          'menu_option_id',
          ObjectId.fromHexString(menuOptionId),
        ))
        .toList();

    final data = <Map<String, dynamic>>[];
    for (final o in options) {
      data.add(DatabaseService.cleanDocument(o));
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
    final cartItemId = body['cart_item_id'] as String?;
    final menuOptionId = body['menu_option_id'] as String?;
    final quantity = body['quantity'] ?? 1;

    // Validation
    if (cartItemId == null || !ObjectId.isValidHexId(cartItemId)) {
      return _error('Valid cart_item_id is required');
    }
    if (menuOptionId == null || !ObjectId.isValidHexId(menuOptionId)) {
      return _error('Valid menu_option_id is required');
    }

    // ទាញ menu option ដើម្បីយកតម្លៃ
    final menuOption = await DatabaseService.menuOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(menuOptionId)));
    if (menuOption == null) {
      return _error('Menu option not found', statusCode: 404);
    }

    final optionPrice =
        (menuOption['option_price'] as num?)?.toDouble() ?? 0.0;

    final optionData = {
      'cart_item_id': ObjectId.fromHexString(cartItemId),
      'menu_option_id': ObjectId.fromHexString(menuOptionId),
      'quantity': (quantity as num).toInt(),
      'price_adjustment': optionPrice,
      'created_at': DateTime.now(),
    };

    final result =
        await DatabaseService.cartItemOptions.insertOne(optionData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Cart item option added',
      'data': {
        'id': result.id.toHexString(),
        'cart_item_id': cartItemId,
        'menu_option_id': menuOptionId,
        'quantity': optionData['quantity'],
        'price_adjustment': optionPrice,
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
      return _error('Invalid option ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.cartItemOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Cart item option not found', statusCode: 404);
    }

    final quantity = body['quantity'];
    if (quantity == null) {
      return _error('quantity is required for PUT');
    }

    final qty = (quantity as num).toInt();
    if (qty <= 0) {
      return _error('quantity must be greater than 0');
    }

    var modifier = modify.set('quantity', qty);

    if (body.containsKey('price_adjustment')) {
      modifier = modifier.set(
        'price_adjustment',
        (body['price_adjustment'] as num).toDouble(),
      );
    }

    await DatabaseService.cartItemOptions.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.cartItemOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Cart item option updated successfully',
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
      return _error('Invalid option ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.cartItemOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Cart item option not found', statusCode: 404);
    }

    var modifier = modify;
    var hasUpdate = false;

    if (body.containsKey('quantity')) {
      final qty = (body['quantity'] as num).toInt();
      if (qty <= 0) {
        return _error('quantity must be greater than 0');
      }
      modifier = modifier.set('quantity', qty);
      hasUpdate = true;
    }

    if (body.containsKey('price_adjustment')) {
      modifier = modifier.set(
        'price_adjustment',
        (body['price_adjustment'] as num).toDouble(),
      );
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.cartItemOptions.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.cartItemOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Cart item option partially updated',
      'data': updated != null ? DatabaseService.cleanDocument(updated) : null,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== DELETE ====================
Future<Response> _handleDelete(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];
  final cartItemId = context.request.uri.queryParameters['cart_item_id'];

  try {
    await DatabaseService.startDb();

    // Clear all options for a cart item
    if (cartItemId != null && cartItemId.isNotEmpty) {
      if (!ObjectId.isValidHexId(cartItemId)) {
        return _error('Invalid cart item ID format', statusCode: 400);
      }

      final result = await DatabaseService.cartItemOptions
          .deleteMany({'cart_item_id': ObjectId.fromHexString(cartItemId)});

      return Response.json(body: {
        'success': true,
        'message': 'All cart item options removed',
        'deleted_count': result.nRemoved,
      });
    }

    // Delete single option
    if (id == null || id.isEmpty) {
      return _error('id or cart_item_id is required');
    }

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid option ID format', statusCode: 400);
    }

    final existing = await DatabaseService.cartItemOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Cart item option not found', statusCode: 404);
    }

    await DatabaseService.cartItemOptions
        .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Cart item option removed',
    });
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