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
  final orderId = context.request.uri.queryParameters['order_id'];
  final userId = context.request.uri.queryParameters['user_id'];
  final status = context.request.uri.queryParameters['status'];

  if (id != null && id.isNotEmpty) {
    return _getPaymentById(id);
  }
  if (orderId != null && orderId.isNotEmpty) {
    return _getPaymentByOrder(orderId);
  }
  if (userId != null && userId.isNotEmpty) {
    return _getPaymentsByUser(userId, status);
  }
  return _getAllPayments(context);
}

Future<Response> _getAllPayments(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allPayments = await DatabaseService.payments.find().toList();
    final payments = allPayments.skip(skip).take(limit).toList();
    final total = allPayments.length;

    final data = <Map<String, dynamic>>[];
    for (final p in payments) {
      data.add(DatabaseService.cleanDocument(p));
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

Future<Response> _getPaymentById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid payment ID format', statusCode: 400);
    }

    final paymentMap = await DatabaseService.payments
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (paymentMap == null) {
      return _error('Payment not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(paymentMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getPaymentByOrder(String orderId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(orderId)) {
      return _error('Invalid order ID format', statusCode: 400);
    }

    final paymentMap = await DatabaseService.payments
        .findOne(where.eq('order_id', ObjectId.fromHexString(orderId)));

    if (paymentMap == null) {
      return _error('Payment not found for this order', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(paymentMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getPaymentsByUser(String userId, String? status) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(userId)) {
      return _error('Invalid user ID format', statusCode: 400);
    }

    final query = <String, dynamic>{
      'user_id': ObjectId.fromHexString(userId),
    };
    if (status != null && status.isNotEmpty) {
      query['status'] = status;
    }

    final payments = await DatabaseService.payments.find(query).toList();

    final data = <Map<String, dynamic>>[];
    for (final p in payments) {
      data.add(DatabaseService.cleanDocument(p));
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
    final orderId = body['order_id'] as String?;
    final userId = body['user_id'] as String?;
    final amount = body['amount'];

    if (orderId == null || !ObjectId.isValidHexId(orderId)) {
      return _error('Valid order_id is required');
    }
    if (userId == null || !ObjectId.isValidHexId(userId)) {
      return _error('Valid user_id is required');
    }
    if (amount == null) {
      return _error('amount is required');
    }

    // Check if payment already exists for this order
    final existing = await DatabaseService.payments
        .findOne(where.eq('order_id', ObjectId.fromHexString(orderId)));
    if (existing != null) {
      return _error('Payment already exists for this order', statusCode: 409);
    }

    final transactionId = body['transaction_id'] ??
        'TXN-${DateTime.now().millisecondsSinceEpoch}';

    final paymentData = {
      'order_id': ObjectId.fromHexString(orderId),
      'user_id': ObjectId.fromHexString(userId),
      'payment_method_id': body['payment_method_id'] != null
          ? ObjectId.fromHexString(body['payment_method_id'] as String)
          : null,
      'amount': (amount as num).toDouble(),
      'currency': body['currency'] ?? 'USD',
      'payment_type': body['payment_type'] ?? 'online',
      'transaction_id': transactionId,
      'gateway_response': body['gateway_response'] ?? '',
      'status': body['status'] ?? 'pending',
      'payment_date': DateTime.now(),
      'created_at': DateTime.now(),
      'updated_at': DateTime.now(),
    };

    final result = await DatabaseService.payments.insertOne(paymentData);

    // Update order payment_status
    await DatabaseService.orders.updateOne(
      where.eq('_id', ObjectId.fromHexString(orderId)),
      modify
          .set('payment_status', paymentData['status'])
          .set('updated_at', DateTime.now()),
    );

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Payment created successfully',
      'data': {
        'id': result.id.toHexString(),
        'order_id': orderId,
        'user_id': userId,
        'amount': paymentData['amount'],
        'transaction_id': transactionId,
        'status': paymentData['status'],
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
      return _error('Invalid payment ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.payments
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Payment not found', statusCode: 404);
    }

    final status = body['status'] as String?;
    final amount = body['amount'];

    if (status == null || status.isEmpty) {
      return _error('status is required for PUT');
    }
    if (amount == null) {
      return _error('amount is required for PUT');
    }

    var modifier = modify.set('status', status);
    modifier = modifier.set('amount', (amount as num).toDouble());
    modifier = modifier.set('currency', body['currency'] ?? 'USD');
    modifier = modifier.set('payment_type', body['payment_type'] ?? 'online');
    modifier = modifier.set(
      'transaction_id',
      body['transaction_id'] ?? existing['transaction_id'],
    );
    modifier = modifier.set(
      'gateway_response',
      body['gateway_response'] ?? '',
    );
    modifier = modifier.set('updated_at', DateTime.now());

    await DatabaseService.payments.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    // Update order payment_status
    final orderId = existing['order_id'] as ObjectId;
    await DatabaseService.orders.updateOne(
      where.eq('_id', orderId),
      modify.set('payment_status', status).set('updated_at', DateTime.now()),
    );

    final updated = await DatabaseService.payments
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Payment updated successfully',
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
      return _error('Invalid payment ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.payments
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Payment not found', statusCode: 404);
    }

    var modifier = modify.set('updated_at', DateTime.now());
    var hasUpdate = false;
    String? newStatus;

    if (body.containsKey('status')) {
      newStatus = body['status'] as String?;
      modifier = modifier.set('status', newStatus);
      hasUpdate = true;
    }

    if (body.containsKey('amount')) {
      modifier = modifier.set('amount', (body['amount'] as num).toDouble());
      hasUpdate = true;
    }

    if (body.containsKey('gateway_response')) {
      modifier = modifier.set('gateway_response', body['gateway_response']);
      hasUpdate = true;
    }

    if (body.containsKey('transaction_id')) {
      modifier = modifier.set('transaction_id', body['transaction_id']);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.payments.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    // Update order if status changed
    if (newStatus != null) {
      final orderId = existing['order_id'] as ObjectId;
      await DatabaseService.orders.updateOne(
        where.eq('_id', orderId),
        modify
            .set('payment_status', newStatus)
            .set('updated_at', DateTime.now()),
      );
    }

    final updated = await DatabaseService.payments
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Payment partially updated',
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
      return _error('Invalid payment ID format', statusCode: 400);
    }

    final existing = await DatabaseService.payments
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Payment not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      await DatabaseService.payments
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));

      // Reset order payment_status
      final orderId = existing['order_id'] as ObjectId;
      await DatabaseService.orders.updateOne(
        where.eq('_id', orderId),
        modify
            .set('payment_status', 'pending')
            .set('updated_at', DateTime.now()),
      );

      return Response.json(body: {
        'success': true,
        'message': 'Payment deleted permanently',
      });
    } else {
      // Soft delete: mark as refunded
      await DatabaseService.payments.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify
            .set('status', 'refunded')
            .set('updated_at', DateTime.now()),
      );

      final orderId = existing['order_id'] as ObjectId;
      await DatabaseService.orders.updateOne(
        where.eq('_id', orderId),
        modify
            .set('payment_status', 'refunded')
            .set('updated_at', DateTime.now()),
      );

      return Response.json(body: {
        'success': true,
        'message': 'Payment marked as refunded (soft delete)',
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