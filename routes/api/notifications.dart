
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
  final type = context.request.uri.queryParameters['type'];
  final isRead = context.request.uri.queryParameters['is_read'];

  if (id != null && id.isNotEmpty) {
    return _getNotificationById(id);
  }
  if (userId != null && userId.isNotEmpty) {
    return _getNotificationsByUser(userId, type, isRead);
  }
  return _getAllNotifications(context);
}

Future<Response> _getAllNotifications(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allNotifications =
        await DatabaseService.notifications.find().toList();
    final notifications = allNotifications.skip(skip).take(limit).toList();
    final total = allNotifications.length;

    final data = <Map<String, dynamic>>[];
    for (final n in notifications) {
      data.add(DatabaseService.cleanDocument(n));
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

Future<Response> _getNotificationById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid notification ID format', statusCode: 400);
    }

    final notifMap = await DatabaseService.notifications
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (notifMap == null) {
      return _error('Notification not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(notifMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getNotificationsByUser(
  String userId,
  String? type,
  String? isRead,
) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(userId)) {
      return _error('Invalid user ID format', statusCode: 400);
    }

    final query = <String, dynamic>{
      'user_id': ObjectId.fromHexString(userId),
    };
    if (type != null && type.isNotEmpty) {
      query['type'] = type;
    }
    if (isRead != null && isRead.isNotEmpty) {
      query['is_read'] = isRead.toLowerCase() == 'true';
    }

    final notifications =
        await DatabaseService.notifications.find(query).toList();

    // Sort by created_at descending
    notifications.sort((a, b) {
      final aDate = a['created_at'] as DateTime? ?? DateTime.now();
      final bDate = b['created_at'] as DateTime? ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

    final data = <Map<String, dynamic>>[];
    for (final n in notifications) {
      data.add(DatabaseService.cleanDocument(n));
    }

    final unreadCount =
        notifications.where((n) => n['is_read'] == false).length;

    return Response.json(body: {
      'success': true,
      'data': data,
      'count': data.length,
      'unread_count': unreadCount,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _handlePost(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final body = await context.request.json() as Map<String, dynamic>;
    final userId = body['user_id'] as String?;
    final title = (body['title'] as String?)?.trim();
    final message = (body['message'] as String?)?.trim();
    final type = (body['type'] as String?)?.trim();

    // Validation
    if (userId == null || !ObjectId.isValidHexId(userId)) {
      return _error('Valid user_id is required');
    }
    if (title == null || title.isEmpty) {
      return _error('title is required');
    }
    if (message == null || message.isEmpty) {
      return _error('message is required');
    }
    if (type == null || type.isEmpty) {
      return _error('type is required');
    }
    if (!['order', 'promotion', 'system', 'payment', 'delivery']
        .contains(type)) {
      return _error(
          'type must be order, promotion, system, payment, or delivery');
    }

    final notifData = {
      'user_id': ObjectId.fromHexString(userId),
      'title': title,
      'message': message,
      'type': type,
      'is_read': false,
      'related_id': body['related_id'] != null &&
              ObjectId.isValidHexId(body['related_id'] as String)
          ? ObjectId.fromHexString(body['related_id'] as String)
          : null,
      'created_at': DateTime.now(),
    };

    final result =
        await DatabaseService.notifications.insertOne(notifData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Notification created successfully',
      'data': {
        'id': result.id.toHexString(),
        'user_id': userId,
        'title': title,
        'message': message,
        'type': type,
        'is_read': false,
      },
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _handlePut(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];

  if (id == null || id.isEmpty) {
    return _error('id is required for PUT', statusCode: 400);
  }

  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid notification ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.notifications
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Notification not found', statusCode: 404);
    }

    final title = (body['title'] as String?)?.trim();
    final message = (body['message'] as String?)?.trim();
    final type = (body['type'] as String?)?.trim();

    if (title == null || title.isEmpty) {
      return _error('title is required for PUT');
    }
    if (message == null || message.isEmpty) {
      return _error('message is required for PUT');
    }
    if (type == null || type.isEmpty) {
      return _error('type is required for PUT');
    }

    var modifier = modify.set('title', title);
    modifier = modifier.set('message', message);
    modifier = modifier.set('type', type);
    modifier = modifier.set('is_read', body['is_read'] ?? false);

    await DatabaseService.notifications.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.notifications
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Notification updated successfully',
      'data': updated != null ? DatabaseService.cleanDocument(updated) : null,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _handlePatch(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];

  if (id == null || id.isEmpty) {
    return _error('id is required for PATCH', statusCode: 400);
  }

  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid notification ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.notifications
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Notification not found', statusCode: 404);
    }

    var modifier = modify;
    var hasUpdate = false;

    if (body.containsKey('is_read')) {
      modifier = modifier.set('is_read', body['is_read']);
      hasUpdate = true;
    }

    if (body.containsKey('title')) {
      modifier = modifier.set('title', body['title']);
      hasUpdate = true;
    }

    if (body.containsKey('message')) {
      modifier = modifier.set('message', body['message']);
      hasUpdate = true;
    }

    if (body.containsKey('type')) {
      modifier = modifier.set('type', body['type']);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.notifications.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.notifications
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Notification partially updated',
      'data': updated != null ? DatabaseService.cleanDocument(updated) : null,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _handleDelete(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];
  final userId = context.request.uri.queryParameters['user_id'];
  final deleteAll = context.request.uri.queryParameters['delete_all'];

  try {
    await DatabaseService.startDb();

    // Delete all for user
    if (deleteAll == 'true' && userId != null && userId.isNotEmpty) {
      if (!ObjectId.isValidHexId(userId)) {
        return _error('Invalid user ID format', statusCode: 400);
      }

      final result = await DatabaseService.notifications
          .deleteMany({'user_id': ObjectId.fromHexString(userId)});

      return Response.json(body: {
        'success': true,
        'message': 'All notifications deleted',
        'deleted_count': result.nRemoved,
      });
    }

    if (id == null || id.isEmpty) {
      return _error('id or (user_id + delete_all) is required');
    }

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid notification ID format', statusCode: 400);
    }

    final existing = await DatabaseService.notifications
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Notification not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      await DatabaseService.notifications
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));
      return Response.json(body: {
        'success': true,
        'message': 'Notification deleted permanently',
      });
    } else {
      await DatabaseService.notifications.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify.set('is_read', true),
      );
      return Response.json(body: {
        'success': true,
        'message': 'Notification marked as read (soft delete)',
      });
    }
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Response _error(String message, {int statusCode = 400}) {
  return Response.json(
    statusCode: statusCode,
    body: {'success': false, 'message': message},
  );
}