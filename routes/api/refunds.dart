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
  final paymentId = context.request.uri.queryParameters['payment_id'];
  final status = context.request.uri.queryParameters['status'];

  if (id != null && id.isNotEmpty) {
    return _getRefundById(id);
  }
  if (orderId != null && orderId.isNotEmpty) {
    return _getRefundsByOrder(orderId);
  }
  if (paymentId != null && paymentId.isNotEmpty) {
    return _getRefundsByPayment(paymentId);
  }
  return _getAllRefunds(context, status);
}

Future<Response> _getAllRefunds(RequestContext context, String? status) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    var allRefunds = await DatabaseService.refunds.find().toList();

    if (status != null && status.isNotEmpty) {
      allRefunds = allRefunds.where((r) => r['status'] == status).toList();
    }

    // Sort by created_at descending
    allRefunds.sort((a, b) {
      final aDate = a['created_at'] as DateTime? ?? DateTime.now();
      final bDate = b['created_at'] as DateTime? ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

    final refunds = allRefunds.skip(skip).take(limit).toList();
    final total = allRefunds.length;

    final data = <Map<String, dynamic>>[];
    for (final r in refunds) {
      data.add(DatabaseService.cleanDocument(r));
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

Future<Response> _getRefundById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid refund ID format', statusCode: 400);
    }

    final refundMap = await DatabaseService.refunds
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (refundMap == null) {
      return _error('Refund not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(refundMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getRefundsByOrder(String orderId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(orderId)) {
      return _error('Invalid order ID format', statusCode: 400);
    }

    final refunds = await DatabaseService.refunds
        .find(where.eq('order_id', ObjectId.fromHexString(orderId)))
        .toList();

    final data = <Map<String, dynamic>>[];
    for (final r in refunds) {
      data.add(DatabaseService.cleanDocument(r));
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

Future<Response> _getRefundsByPayment(String paymentId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(paymentId)) {
      return _error('Invalid payment ID format', statusCode: 400);
    }

    final refunds = await DatabaseService.refunds
        .find(where.eq('payment_id', ObjectId.fromHexString(paymentId)))
        .toList();

    final data = <Map<String, dynamic>>[];
    for (final r in refunds) {
      data.add(DatabaseService.cleanDocument(r));
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
    final paymentId = body['payment_id'] as String?;
    final amount = body['amount'];
    final reason = (body['reason'] as String?)?.trim();

    // Validation
    if (orderId == null || !ObjectId.isValidHexId(orderId)) {
      return _error('Valid order_id is required');
    }
    if (paymentId == null || !ObjectId.isValidHexId(paymentId)) {
      return _error('Valid payment_id is required');
    }
    if (amount == null) {
      return _error('amount is required');
    }
    if (reason == null || reason.isEmpty) {
      return _error('reason is required');
    }

    final amountValue = (amount as num).toDouble();
    if (amountValue <= 0) {
      return _error('amount must be greater than 0');
    }

    final refundData = {
      'order_id': ObjectId.fromHexString(orderId),
      'payment_id': ObjectId.fromHexString(paymentId),
      'amount': amountValue,
      'reason': reason,
      'refund_method': body['refund_method'] ?? 'original_payment',
      'status': body['status'] ?? 'pending',
      'approved_by': body['approved_by'] != null &&
              ObjectId.isValidHexId(body['approved_by'] as String)
          ? ObjectId.fromHexString(body['approved_by'] as String)
          : null,
      'created_at': DateTime.now(),
      'processed_at': null,
    };

    final result = await DatabaseService.refunds.insertOne(refundData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Refund request created successfully',
      'data': {
        'id': result.id.toHexString(),
        'order_id': orderId,
        'payment_id': paymentId,
        'amount': amountValue,
        'reason': reason,
        'status': refundData['status'],
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
      return _error('Invalid refund ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.refunds
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Refund not found', statusCode: 404);
    }

    final amount = body['amount'];
    final reason = (body['reason'] as String?)?.trim();
    final status = (body['status'] as String?)?.trim();

    if (amount == null) {
      return _error('amount is required for PUT');
    }
    if (reason == null || reason.isEmpty) {
      return _error('reason is required for PUT');
    }
    if (status == null || status.isEmpty) {
      return _error('status is required for PUT');
    }

    var modifier = modify.set('amount', (amount as num).toDouble());
    modifier = modifier.set('reason', reason);
    modifier = modifier.set('refund_method', body['refund_method'] ?? 'original_payment');
    modifier = modifier.set('status', status);

    if (body['approved_by'] != null &&
        ObjectId.isValidHexId(body['approved_by'] as String)) {
      modifier = modifier.set(
        'approved_by',
        ObjectId.fromHexString(body['approved_by'] as String),
      );
    }

    if (status == 'processed') {
      modifier = modifier.set('processed_at', DateTime.now());
    }

    await DatabaseService.refunds.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.refunds
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Refund updated successfully',
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
      return _error('Invalid refund ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.refunds
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Refund not found', statusCode: 404);
    }

    var modifier = modify;
    var hasUpdate = false;

    if (body.containsKey('amount')) {
      final amountValue = (body['amount'] as num).toDouble();
      if (amountValue <= 0) {
        return _error('amount must be greater than 0');
      }
      modifier = modifier.set('amount', amountValue);
      hasUpdate = true;
    }

    if (body.containsKey('reason')) {
      modifier = modifier.set('reason', body['reason']);
      hasUpdate = true;
    }

    if (body.containsKey('refund_method')) {
      modifier = modifier.set('refund_method', body['refund_method']);
      hasUpdate = true;
    }

    if (body.containsKey('status')) {
      final status = body['status'] as String;
      modifier = modifier.set('status', status);

      if (status == 'processed') {
        modifier = modifier.set('processed_at', DateTime.now());
      }
      hasUpdate = true;
    }

    if (body.containsKey('approved_by')) {
      final approvedBy = body['approved_by'] as String?;
      if (approvedBy != null && ObjectId.isValidHexId(approvedBy)) {
        modifier = modifier.set(
          'approved_by',
          ObjectId.fromHexString(approvedBy),
        );
      }
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.refunds.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.refunds
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Refund partially updated',
      'data': updated != null ? DatabaseService.cleanDocument(updated) : null,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== DELETE ====================
Future<Response> _handleDelete(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];
  final orderId = context.request.uri.queryParameters['order_id'];

  try {
    await DatabaseService.startDb();

    // Delete all refunds for an order
    if (orderId != null && orderId.isNotEmpty) {
      if (!ObjectId.isValidHexId(orderId)) {
        return _error('Invalid order ID format', statusCode: 400);
      }

      final result = await DatabaseService.refunds
          .deleteMany({'order_id': ObjectId.fromHexString(orderId)});

      return Response.json(body: {
        'success': true,
        'message': 'All refunds deleted for this order',
        'deleted_count': result.nRemoved,
      });
    }

    // Delete single refund
    if (id == null || id.isEmpty) {
      return _error('id or order_id is required');
    }

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid refund ID format', statusCode: 400);
    }

    final existing = await DatabaseService.refunds
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Refund not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      await DatabaseService.refunds
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));
      return Response.json(body: {
        'success': true,
        'message': 'Refund deleted permanently',
      });
    } else {
      await DatabaseService.refunds.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify
            .set('status', 'rejected')
            .set('processed_at', DateTime.now()),
      );
      return Response.json(body: {
        'success': true,
        'message': 'Refund rejected (soft delete)',
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