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
  final status = context.request.uri.queryParameters['status'];
  final createdBy = context.request.uri.queryParameters['created_by'];

  if (id != null && id.isNotEmpty) {
    return _getHistoryById(id);
  }
  if (orderId != null && orderId.isNotEmpty) {
    return _getHistoryByOrder(orderId, status);
  }
  if (createdBy != null && createdBy.isNotEmpty) {
    return _getHistoryByUser(createdBy);
  }
  return _getAllHistory(context);
}

Future<Response> _getAllHistory(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allHistory =
        await DatabaseService.orderStatusHistory.find().toList();

    // Sort by created_at descending
    allHistory.sort((a, b) {
      final aDate = a['created_at'] as DateTime? ?? DateTime.now();
      final bDate = b['created_at'] as DateTime? ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

    final history = allHistory.skip(skip).take(limit).toList();
    final total = allHistory.length;

    final data = <Map<String, dynamic>>[];
    for (final h in history) {
      data.add(DatabaseService.cleanDocument(h));
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

Future<Response> _getHistoryById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid history ID format', statusCode: 400);
    }

    final historyMap = await DatabaseService.orderStatusHistory
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (historyMap == null) {
      return _error('Status history not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(historyMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getHistoryByOrder(String orderId, String? status) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(orderId)) {
      return _error('Invalid order ID format', statusCode: 400);
    }

    final query = <String, dynamic>{
      'order_id': ObjectId.fromHexString(orderId),
    };
    if (status != null && status.isNotEmpty) {
      query['status'] = status;
    }

    final history =
        await DatabaseService.orderStatusHistory.find(query).toList();

    // Sort by created_at ascending (chronological)
    history.sort((a, b) {
      final aDate = a['created_at'] as DateTime? ?? DateTime.now();
      final bDate = b['created_at'] as DateTime? ?? DateTime.now();
      return aDate.compareTo(bDate);
    });

    final data = <Map<String, dynamic>>[];
    for (final h in history) {
      data.add(DatabaseService.cleanDocument(h));
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

Future<Response> _getHistoryByUser(String userId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(userId)) {
      return _error('Invalid user ID format', statusCode: 400);
    }

    final history = await DatabaseService.orderStatusHistory
        .find(where.eq('created_by', ObjectId.fromHexString(userId)))
        .toList();

    // Sort by created_at descending
    history.sort((a, b) {
      final aDate = a['created_at'] as DateTime? ?? DateTime.now();
      final bDate = b['created_at'] as DateTime? ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

    final data = <Map<String, dynamic>>[];
    for (final h in history) {
      data.add(DatabaseService.cleanDocument(h));
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
    final status = (body['status'] as String?)?.trim();

    // Validation
    if (orderId == null || !ObjectId.isValidHexId(orderId)) {
      return _error('Valid order_id is required');
    }
    if (status == null || status.isEmpty) {
      return _error('status is required');
    }

    final historyData = {
      'order_id': ObjectId.fromHexString(orderId),
      'status': status,
      'notes': body['notes'] ?? '',
      'created_by': body['created_by'] != null &&
              ObjectId.isValidHexId(body['created_by'] as String)
          ? ObjectId.fromHexString(body['created_by'] as String)
          : null,
      'created_at': DateTime.now(),
    };

    final result =
        await DatabaseService.orderStatusHistory.insertOne(historyData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Status history created successfully',
      'data': {
        'id': result.id.toHexString(),
        'order_id': orderId,
        'status': status,
        'notes': historyData['notes'],
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
      return _error('Invalid history ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.orderStatusHistory
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Status history not found', statusCode: 404);
    }

    final status = (body['status'] as String?)?.trim();
    if (status == null || status.isEmpty) {
      return _error('status is required for PUT');
    }

    var modifier = modify.set('status', status);
    modifier = modifier.set('notes', body['notes'] ?? '');

    await DatabaseService.orderStatusHistory.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.orderStatusHistory
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Status history updated successfully',
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
      return _error('Invalid history ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.orderStatusHistory
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Status history not found', statusCode: 404);
    }

    var modifier = modify;
    var hasUpdate = false;

    if (body.containsKey('status')) {
      final v = (body['status'] as String?)?.trim();
      if (v == null || v.isEmpty) return _error('status cannot be empty');
      modifier = modifier.set('status', v);
      hasUpdate = true;
    }

    if (body.containsKey('notes')) {
      modifier = modifier.set('notes', body['notes']);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.orderStatusHistory.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.orderStatusHistory
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Status history partially updated',
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

    // Clear all history for an order
    if (orderId != null && orderId.isNotEmpty) {
      if (!ObjectId.isValidHexId(orderId)) {
        return _error('Invalid order ID format', statusCode: 400);
      }

      final result = await DatabaseService.orderStatusHistory
          .deleteMany({'order_id': ObjectId.fromHexString(orderId)});

      return Response.json(body: {
        'success': true,
        'message': 'All status history removed for this order',
        'deleted_count': result.nRemoved,
      });
    }

    // Delete single history
    if (id == null || id.isEmpty) {
      return _error('id or order_id is required');
    }

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid history ID format', statusCode: 400);
    }

    final existing = await DatabaseService.orderStatusHistory
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Status history not found', statusCode: 404);
    }

    await DatabaseService.orderStatusHistory
        .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Status history deleted permanently',
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