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
  final driverId = context.request.uri.queryParameters['driver_id'];
  final status = context.request.uri.queryParameters['status'];

  if (id != null && id.isNotEmpty) {
    return _getAssignmentById(id);
  }
  if (orderId != null && orderId.isNotEmpty) {
    return _getAssignmentByOrder(orderId);
  }
  if (driverId != null && driverId.isNotEmpty) {
    return _getAssignmentsByDriver(driverId, status);
  }
  return _getAllAssignments(context, status);
}

Future<Response> _getAllAssignments(
  RequestContext context,
  String? status,
) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    var allAssignments =
        await DatabaseService.deliveryAssignments.find().toList();

    if (status != null && status.isNotEmpty) {
      allAssignments =
          allAssignments.where((a) => a['status'] == status).toList();
    }

    final assignments = allAssignments.skip(skip).take(limit).toList();
    final total = allAssignments.length;

    final data = <Map<String, dynamic>>[];
    for (final a in assignments) {
      data.add(DatabaseService.cleanDocument(a));
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

Future<Response> _getAssignmentById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid assignment ID format', statusCode: 400);
    }

    final assignmentMap = await DatabaseService.deliveryAssignments
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (assignmentMap == null) {
      return _error('Assignment not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(assignmentMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getAssignmentByOrder(String orderId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(orderId)) {
      return _error('Invalid order ID format', statusCode: 400);
    }

    final assignmentMap = await DatabaseService.deliveryAssignments
        .findOne(where.eq('order_id', ObjectId.fromHexString(orderId)));

    if (assignmentMap == null) {
      return _error('Assignment not found for this order', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(assignmentMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getAssignmentsByDriver(
  String driverId,
  String? status,
) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(driverId)) {
      return _error('Invalid driver ID format', statusCode: 400);
    }

    final query = <String, dynamic>{
      'driver_id': ObjectId.fromHexString(driverId),
    };
    if (status != null && status.isNotEmpty) {
      query['status'] = status;
    }

    final assignments =
        await DatabaseService.deliveryAssignments.find(query).toList();

    final data = <Map<String, dynamic>>[];
    for (final a in assignments) {
      data.add(DatabaseService.cleanDocument(a));
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
    final driverId = body['driver_id'] as String?;

    // Validation
    if (orderId == null || !ObjectId.isValidHexId(orderId)) {
      return _error('Valid order_id is required');
    }
    if (driverId == null || !ObjectId.isValidHexId(driverId)) {
      return _error('Valid driver_id is required');
    }

    // Check if order already has an assignment
    final existing = await DatabaseService.deliveryAssignments
        .findOne(where.eq('order_id', ObjectId.fromHexString(orderId)));
    if (existing != null) {
      return _error('Order already has a driver assigned', statusCode: 409);
    }

    final assignmentData = {
      'order_id': ObjectId.fromHexString(orderId),
      'driver_id': ObjectId.fromHexString(driverId),
      'pickup_time': body['pickup_time'] != null
          ? DateTime.parse(body['pickup_time'] as String)
          : null,
      'delivered_time': null,
      'status': body['status'] ?? 'assigned',
      'delivery_notes': body['delivery_notes'] ?? '',
      'distance_km': (body['distance_km'] as num?)?.toDouble() ?? 0.0,
      'delivery_duration': body['delivery_duration'] ?? 0,
      'created_at': DateTime.now(),
      'updated_at': DateTime.now(),
    };

    final result =
        await DatabaseService.deliveryAssignments.insertOne(assignmentData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Driver assigned successfully',
      'data': {
        'id': result.id.toHexString(),
        'order_id': orderId,
        'driver_id': driverId,
        'status': assignmentData['status'],
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
      return _error('Invalid assignment ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.deliveryAssignments
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Assignment not found', statusCode: 404);
    }

    final status = body['status'] as String?;
    if (status == null || status.isEmpty) {
      return _error('status is required for PUT');
    }

    var modifier = modify.set('status', status);
    modifier = modifier.set('delivery_notes', body['delivery_notes'] ?? '');
    modifier = modifier.set(
      'distance_km',
      (body['distance_km'] as num?)?.toDouble() ?? 0.0,
    );
    modifier = modifier.set(
      'delivery_duration',
      body['delivery_duration'] ?? 0,
    );
    modifier = modifier.set('updated_at', DateTime.now());

    if (body['pickup_time'] != null) {
      modifier = modifier.set(
        'pickup_time',
        DateTime.parse(body['pickup_time'] as String),
      );
    }
    if (body['delivered_time'] != null) {
      modifier = modifier.set(
        'delivered_time',
        DateTime.parse(body['delivered_time'] as String),
      );
    }

    await DatabaseService.deliveryAssignments.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    // Update order status if delivered
    if (status == 'delivered') {
      final orderId = existing['order_id'] as ObjectId;
      await DatabaseService.orders.updateOne(
        where.eq('_id', orderId),
        modify
            .set('order_status', 'delivered')
            .set('actual_delivery_time', DateTime.now())
            .set('updated_at', DateTime.now()),
      );
    }

    final updated = await DatabaseService.deliveryAssignments
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Assignment updated successfully',
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
      return _error('Invalid assignment ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.deliveryAssignments
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Assignment not found', statusCode: 404);
    }

    var modifier = modify.set('updated_at', DateTime.now());
    var hasUpdate = false;
    String? newStatus;

    if (body.containsKey('status')) {
      newStatus = body['status'] as String?;
      modifier = modifier.set('status', newStatus);
      hasUpdate = true;
    }

    if (body.containsKey('delivery_notes')) {
      modifier = modifier.set('delivery_notes', body['delivery_notes']);
      hasUpdate = true;
    }

    if (body.containsKey('pickup_time')) {
      modifier = modifier.set(
        'pickup_time',
        DateTime.parse(body['pickup_time'] as String),
      );
      hasUpdate = true;
    }

    if (body.containsKey('delivered_time')) {
      modifier = modifier.set(
        'delivered_time',
        DateTime.parse(body['delivered_time'] as String),
      );
      hasUpdate = true;
    }

    if (body.containsKey('distance_km')) {
      modifier = modifier.set(
        'distance_km',
        (body['distance_km'] as num).toDouble(),
      );
      hasUpdate = true;
    }

    if (body.containsKey('delivery_duration')) {
      modifier = modifier.set('delivery_duration', body['delivery_duration']);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.deliveryAssignments.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    // Update order if delivered
    if (newStatus == 'delivered') {
      final orderId = existing['order_id'] as ObjectId;
      await DatabaseService.orders.updateOne(
        where.eq('_id', orderId),
        modify
            .set('order_status', 'delivered')
            .set('actual_delivery_time', DateTime.now())
            .set('updated_at', DateTime.now()),
      );
    }

    final updated = await DatabaseService.deliveryAssignments
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Assignment partially updated',
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
      return _error('Invalid assignment ID format', statusCode: 400);
    }

    final existing = await DatabaseService.deliveryAssignments
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Assignment not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      await DatabaseService.deliveryAssignments
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));
      return Response.json(body: {
        'success': true,
        'message': 'Assignment deleted permanently',
      });
    } else {
      await DatabaseService.deliveryAssignments.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify
            .set('status', 'failed')
            .set('updated_at', DateTime.now()),
      );
      return Response.json(body: {
        'success': true,
        'message': 'Assignment marked as failed (soft delete)',
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