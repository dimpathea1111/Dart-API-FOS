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
  final restaurantId = context.request.uri.queryParameters['restaurant_id'];
  final status = context.request.uri.queryParameters['status'];
  final orderNumber = context.request.uri.queryParameters['order_number'];

  if (id != null && id.isNotEmpty) {
    return _getOrderById(id);
  }
  if (orderNumber != null && orderNumber.isNotEmpty) {
    return _getOrderByNumber(orderNumber);
  }
  if (userId != null && userId.isNotEmpty) {
    return _getOrdersByUser(userId, status);
  }
  if (restaurantId != null && restaurantId.isNotEmpty) {
    return _getOrdersByRestaurant(restaurantId, status);
  }
  return _getAllOrders(context);
}

Future<Response> _getAllOrders(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allOrders = await DatabaseService.orders.find().toList();
    final orders = allOrders.skip(skip).take(limit).toList();
    final total = allOrders.length;

    final data = <Map<String, dynamic>>[];
    for (final o in orders) {
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

Future<Response> _getOrderById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid order ID format', statusCode: 400);
    }

    final orderMap = await DatabaseService.orders
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (orderMap == null) {
      return _error('Order not found', statusCode: 404);
    }

    final items = await DatabaseService.orderItems
        .find(where.eq('order_id', ObjectId.fromHexString(id)))
        .toList();

    final itemsData = <Map<String, dynamic>>[];
    for (final item in items) {
      itemsData.add(DatabaseService.cleanDocument(item));
    }

    return Response.json(body: {
      'success': true,
      'data': {
        ...DatabaseService.cleanDocument(orderMap),
        'items': itemsData,
      },
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getOrderByNumber(String orderNumber) async {
  try {
    await DatabaseService.startDb();

    final orderMap = await DatabaseService.orders
        .findOne(where.eq('order_number', orderNumber));

    if (orderMap == null) {
      return _error('Order not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(orderMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getOrdersByUser(String userId, String? status) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(userId)) {
      return _error('Invalid user ID format', statusCode: 400);
    }

    final query = <String, dynamic>{
      'user_id': ObjectId.fromHexString(userId),
    };
    if (status != null && status.isNotEmpty) {
      query['order_status'] = status;
    }

    final orders = await DatabaseService.orders.find(query).toList();

    final data = <Map<String, dynamic>>[];
    for (final o in orders) {
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

Future<Response> _getOrdersByRestaurant(
  String restaurantId,
  String? status,
) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(restaurantId)) {
      return _error('Invalid restaurant ID format', statusCode: 400);
    }

    final query = <String, dynamic>{
      'restaurant_id': ObjectId.fromHexString(restaurantId),
    };
    if (status != null && status.isNotEmpty) {
      query['order_status'] = status;
    }

    final orders = await DatabaseService.orders.find(query).toList();

    final data = <Map<String, dynamic>>[];
    for (final o in orders) {
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
    final userId = body['user_id'] as String?;
    final restaurantId = body['restaurant_id'] as String?;
    final addressId = body['address_id'] as String?;

    // Validation
    if (userId == null || !ObjectId.isValidHexId(userId)) {
      return _error('Valid user_id is required');
    }
    if (restaurantId == null || !ObjectId.isValidHexId(restaurantId)) {
      return _error('Valid restaurant_id is required');
    }
    if (addressId == null || !ObjectId.isValidHexId(addressId)) {
      return _error('Valid address_id is required');
    }

    final orderNumber =
        'ORD-${DateTime.now().millisecondsSinceEpoch}';

    final orderData = {
      'user_id': ObjectId.fromHexString(userId),
      'restaurant_id': ObjectId.fromHexString(restaurantId),
      'address_id': ObjectId.fromHexString(addressId),
      'order_number': orderNumber,
      'order_type': body['order_type'] ?? 'delivery',
      'subtotal': (body['subtotal'] as num?)?.toDouble() ?? 0.0,
      'tax': (body['tax'] as num?)?.toDouble() ?? 0.0,
      'delivery_fee': (body['delivery_fee'] as num?)?.toDouble() ?? 0.0,
      'service_charge': (body['service_charge'] as num?)?.toDouble() ?? 0.0,
      'discount': (body['discount'] as num?)?.toDouble() ?? 0.0,
      'total_amount': (body['total_amount'] as num?)?.toDouble() ?? 0.0,
      'payment_status': body['payment_status'] ?? 'pending',
      'order_status': body['order_status'] ?? 'placed',
      'delivery_instructions': body['delivery_instructions'],
      'scheduled_time': body['scheduled_time'],
      'estimated_delivery_time': body['estimated_delivery_time'],
      'actual_delivery_time': null,
      'created_at': DateTime.now(),
      'updated_at': DateTime.now(),
    };

    final result = await DatabaseService.orders.insertOne(orderData);
    final orderId = result.id;

    // Insert order items if provided
    if (body['items'] != null && body['items'] is List) {
      for (final item in body['items']) {
        final itemData = {
          'order_id': orderId,
          'menu_id': ObjectId.fromHexString(item['menu_id'] as String),
          'quantity': item['quantity'] ?? 1,
          'unit_price': (item['unit_price'] as num).toDouble(),
          'subtotal': (item['subtotal'] as num).toDouble(),
          'special_notes': item['special_notes'] ?? '',
          'item_status': 'confirmed',
          'created_at': DateTime.now(),
        };
        await DatabaseService.orderItems.insertOne(itemData);
      }
    }

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Order created successfully',
      'data': {
        'id': orderId.toHexString(),
        'order_number': orderNumber,
        'user_id': userId,
        'restaurant_id': restaurantId,
        'total_amount': orderData['total_amount'],
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
      return _error('Invalid order ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.orders
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Order not found', statusCode: 404);
    }

    final orderStatus = body['order_status'] as String?;
    final paymentStatus = body['payment_status'] as String?;

    if (orderStatus == null || orderStatus.isEmpty) {
      return _error('order_status is required for PUT');
    }
    if (paymentStatus == null || paymentStatus.isEmpty) {
      return _error('payment_status is required for PUT');
    }

    var modifier = modify.set('order_status', orderStatus);
    modifier = modifier.set('payment_status', paymentStatus);
    modifier = modifier.set(
      'subtotal',
      (body['subtotal'] as num?)?.toDouble() ?? existing['subtotal'],
    );
    modifier = modifier.set(
      'tax',
      (body['tax'] as num?)?.toDouble() ?? existing['tax'],
    );
    modifier = modifier.set(
      'delivery_fee',
      (body['delivery_fee'] as num?)?.toDouble() ?? existing['delivery_fee'],
    );
    modifier = modifier.set(
      'total_amount',
      (body['total_amount'] as num?)?.toDouble() ?? existing['total_amount'],
    );
    modifier = modifier.set(
      'delivery_instructions',
      body['delivery_instructions'] ?? '',
    );
    modifier = modifier.set('updated_at', DateTime.now());

    await DatabaseService.orders.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.orders
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Order updated successfully',
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
      return _error('Invalid order ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.orders
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Order not found', statusCode: 404);
    }

    var modifier = modify.set('updated_at', DateTime.now());
    var hasUpdate = false;

    if (body.containsKey('order_status')) {
      modifier = modifier.set('order_status', body['order_status']);
      hasUpdate = true;
    }

    if (body.containsKey('payment_status')) {
      modifier = modifier.set('payment_status', body['payment_status']);
      hasUpdate = true;
    }

    if (body.containsKey('delivery_instructions')) {
      modifier = modifier.set(
        'delivery_instructions',
        body['delivery_instructions'],
      );
      hasUpdate = true;
    }

    if (body.containsKey('actual_delivery_time')) {
      modifier = modifier.set(
        'actual_delivery_time',
        body['actual_delivery_time'],
      );
      hasUpdate = true;
    }

    if (body.containsKey('estimated_delivery_time')) {
      modifier = modifier.set(
        'estimated_delivery_time',
        body['estimated_delivery_time'],
      );
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.orders.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.orders
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Order partially updated',
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
      return _error('Invalid order ID format', statusCode: 400);
    }

    final existing = await DatabaseService.orders
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Order not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      // Delete order items first
      await DatabaseService.orderItems
          .deleteMany({'order_id': ObjectId.fromHexString(id)});

      // Delete order
      await DatabaseService.orders
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));

      return Response.json(body: {
        'success': true,
        'message': 'Order deleted permanently',
      });
    } else {
      // Soft delete: cancel order
      await DatabaseService.orders.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify
            .set('order_status', 'cancelled')
            .set('updated_at', DateTime.now()),
      );

      return Response.json(body: {
        'success': true,
        'message': 'Order cancelled (soft delete)',
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
