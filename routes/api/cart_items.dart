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
  final cartId = context.request.uri.queryParameters['cart_id'];
  final menuId = context.request.uri.queryParameters['menu_id'];

  if (id != null && id.isNotEmpty) {
    return _getCartItemById(id);
  }
  if (cartId != null && cartId.isNotEmpty) {
    return _getCartItemsByCart(cartId);
  }
  if (menuId != null && menuId.isNotEmpty) {
    return _getCartItemsByMenu(menuId);
  }
  return _getAllCartItems(context);
}

Future<Response> _getAllCartItems(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allItems = await DatabaseService.cartItems.find().toList();
    final items = allItems.skip(skip).take(limit).toList();
    final total = allItems.length;

    final data = <Map<String, dynamic>>[];
    for (final item in items) {
      data.add(DatabaseService.cleanDocument(item));
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

Future<Response> _getCartItemById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid cart item ID format', statusCode: 400);
    }

    final itemMap = await DatabaseService.cartItems
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (itemMap == null) {
      return _error('Cart item not found', statusCode: 404);
    }

    // ទាញ menu details
    final menuId = itemMap['menu_id'];
    Map<String, dynamic>? menuData;
    if (menuId is ObjectId) {
      final menu = await DatabaseService.menu
          .findOne(where.eq('_id', menuId));
      if (menu != null) {
        menuData = DatabaseService.cleanDocument(menu);
      }
    }

    return Response.json(body: {
      'success': true,
      'data': {
        ...DatabaseService.cleanDocument(itemMap),
        if (menuData != null) 'menu': menuData,
      },
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getCartItemsByCart(String cartId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(cartId)) {
      return _error('Invalid cart ID format', statusCode: 400);
    }

    final items = await DatabaseService.cartItems
        .find(where.eq('cart_id', ObjectId.fromHexString(cartId)))
        .toList();

    // ទាញ menu details សម្រាប់ item នីមួយៗ
    final data = <Map<String, dynamic>>[];
    double totalAmount = 0;

    for (final item in items) {
      final cleaned = DatabaseService.cleanDocument(item);
      final menuId = item['menu_id'];

      if (menuId is ObjectId) {
        final menu = await DatabaseService.menu
            .findOne(where.eq('_id', menuId));
        if (menu != null) {
          cleaned['menu'] = DatabaseService.cleanDocument(menu);
        }
      }

      totalAmount += (item['subtotal'] as num?)?.toDouble() ?? 0;
      data.add(cleaned);
    }

    return Response.json(body: {
      'success': true,
      'data': data,
      'count': data.length,
      'total_amount': totalAmount,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getCartItemsByMenu(String menuId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(menuId)) {
      return _error('Invalid menu ID format', statusCode: 400);
    }

    final items = await DatabaseService.cartItems
        .find(where.eq('menu_id', ObjectId.fromHexString(menuId)))
        .toList();

    final data = <Map<String, dynamic>>[];
    for (final item in items) {
      data.add(DatabaseService.cleanDocument(item));
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
    final cartId = body['cart_id'] as String?;
    final menuId = body['menu_id'] as String?;
    final quantity = body['quantity'] ?? 1;

    // Validation
    if (cartId == null || !ObjectId.isValidHexId(cartId)) {
      return _error('Valid cart_id is required');
    }
    if (menuId == null || !ObjectId.isValidHexId(menuId)) {
      return _error('Valid menu_id is required');
    }

    // ទាញ menu ដើម្បីយកតម្លៃ
    final menu = await DatabaseService.menu
        .findOne(where.eq('_id', ObjectId.fromHexString(menuId)));
    if (menu == null) {
      return _error('Menu item not found', statusCode: 404);
    }

    final unitPrice = (menu['discount_price'] ?? menu['price'] as num)
        .toDouble();
    final subtotal = unitPrice * (quantity as num).toInt();

    // ពិនិត្យថាតើ item មានរួចហើយឬនៅ
    final existing = await DatabaseService.cartItems.findOne({
      'cart_id': ObjectId.fromHexString(cartId),
      'menu_id': ObjectId.fromHexString(menuId),
    });

    if (existing != null) {
      // Update quantity
      final newQuantity = (existing['quantity'] as num).toInt() +
          (quantity as num).toInt();
      final newSubtotal = unitPrice * newQuantity;

      await DatabaseService.cartItems.updateOne(
        where.eq('_id', existing['_id']),
        modify
            .set('quantity', newQuantity)
            .set('subtotal', newSubtotal),
      );

      return Response.json(statusCode: 200, body: {
        'success': true,
        'message': 'Cart item quantity updated',
        'data': {
          'id': existing['_id'].toHexString(),
          'cart_id': cartId,
          'menu_id': menuId,
          'quantity': newQuantity,
          'unit_price': unitPrice,
          'subtotal': newSubtotal,
        },
      });
    }

    final itemData = {
      'cart_id': ObjectId.fromHexString(cartId),
      'menu_id': ObjectId.fromHexString(menuId),
      'quantity': (quantity as num).toInt(),
      'unit_price': unitPrice,
      'subtotal': subtotal,
      'special_notes': body['special_notes'] ?? '',
      'added_at': DateTime.now(),
    };

    final result = await DatabaseService.cartItems.insertOne(itemData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Item added to cart',
      'data': {
        'id': result.id.toHexString(),
        'cart_id': cartId,
        'menu_id': menuId,
        'quantity': itemData['quantity'],
        'unit_price': unitPrice,
        'subtotal': subtotal,
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
      return _error('Invalid cart item ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.cartItems
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Cart item not found', statusCode: 404);
    }

    final quantity = body['quantity'];
    if (quantity == null) {
      return _error('quantity is required for PUT');
    }

    final newQuantity = (quantity as num).toInt();
    if (newQuantity <= 0) {
      return _error('quantity must be greater than 0');
    }

    final unitPrice = (existing['unit_price'] as num).toDouble();
    final subtotal = unitPrice * newQuantity;

    var modifier = modify.set('quantity', newQuantity);
    modifier = modifier.set('subtotal', subtotal);
    modifier = modifier.set('special_notes', body['special_notes'] ?? '');

    await DatabaseService.cartItems.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.cartItems
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Cart item updated successfully',
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
      return _error('Invalid cart item ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.cartItems
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Cart item not found', statusCode: 404);
    }

    var modifier = modify;
    var hasUpdate = false;

    if (body.containsKey('quantity')) {
      final newQuantity = (body['quantity'] as num).toInt();
      if (newQuantity <= 0) {
        return _error('quantity must be greater than 0');
      }
      final unitPrice = (existing['unit_price'] as num).toDouble();
      modifier = modifier.set('quantity', newQuantity);
      modifier = modifier.set('subtotal', unitPrice * newQuantity);
      hasUpdate = true;
    }

    if (body.containsKey('special_notes')) {
      modifier = modifier.set('special_notes', body['special_notes']);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.cartItems.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.cartItems
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Cart item partially updated',
      'data': updated != null ? DatabaseService.cleanDocument(updated) : null,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== DELETE ====================
Future<Response> _handleDelete(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];
  final cartId = context.request.uri.queryParameters['cart_id'];

  try {
    await DatabaseService.startDb();

    // Clear all items in cart
    if (cartId != null && cartId.isNotEmpty) {
      if (!ObjectId.isValidHexId(cartId)) {
        return _error('Invalid cart ID format', statusCode: 400);
      }

      final result = await DatabaseService.cartItems
          .deleteMany({'cart_id': ObjectId.fromHexString(cartId)});

      return Response.json(body: {
        'success': true,
        'message': 'All cart items removed',
        'deleted_count': result.nRemoved,
      });
    }

    // Delete single item
    if (id == null || id.isEmpty) {
      return _error('id or cart_id is required');
    }

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid cart item ID format', statusCode: 400);
    }

    final existing = await DatabaseService.cartItems
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Cart item not found', statusCode: 404);
    }

    await DatabaseService.cartItems
        .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Cart item removed',
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