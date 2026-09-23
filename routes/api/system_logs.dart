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
  final action = context.request.uri.queryParameters['action'];

  if (id != null && id.isNotEmpty) {
    return _getLogById(id);
  }
  if (userId != null && userId.isNotEmpty) {
    return _getLogsByUser(userId);
  }
  if (action != null && action.isNotEmpty) {
    return _getLogsByAction(action);
  }
  return _getAllLogs(context);
}

Future<Response> _getAllLogs(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allLogs = await DatabaseService.systemLogs.find().toList();

    allLogs.sort((a, b) {
      final aDate = a['created_at'] as DateTime? ?? DateTime.now();
      final bDate = b['created_at'] as DateTime? ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

    final logs = allLogs.skip(skip).take(limit).toList();
    final total = allLogs.length;

    final data = <Map<String, dynamic>>[];
    for (final l in logs) {
      data.add(DatabaseService.cleanDocument(l));
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

Future<Response> _getLogById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid log ID format', statusCode: 400);
    }

    final logMap = await DatabaseService.systemLogs
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (logMap == null) {
      return _error('Log not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(logMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getLogsByUser(String userId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(userId)) {
      return _error('Invalid user ID format', statusCode: 400);
    }

    final logs = await DatabaseService.systemLogs
        .find(where.eq('user_id', ObjectId.fromHexString(userId)))
        .toList();

    logs.sort((a, b) {
      final aDate = a['created_at'] as DateTime? ?? DateTime.now();
      final bDate = b['created_at'] as DateTime? ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

    final data = <Map<String, dynamic>>[];
    for (final l in logs) {
      data.add(DatabaseService.cleanDocument(l));
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

Future<Response> _getLogsByAction(String action) async {
  try {
    await DatabaseService.startDb();

    final logs = await DatabaseService.systemLogs
        .find(where.eq('action', action))
        .toList();

    logs.sort((a, b) {
      final aDate = a['created_at'] as DateTime? ?? DateTime.now();
      final bDate = b['created_at'] as DateTime? ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

    final data = <Map<String, dynamic>>[];
    for (final l in logs) {
      data.add(DatabaseService.cleanDocument(l));
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
    final action = (body['action'] as String?)?.trim();

    if (action == null || action.isEmpty) {
      return _error('action is required');
    }

    final logData = {
      'user_id': body['user_id'] != null &&
              ObjectId.isValidHexId(body['user_id'] as String)
          ? ObjectId.fromHexString(body['user_id'] as String)
          : null,
      'action': action,
      'details': body['details'] ?? '',
      'ip_address': body['ip_address'] ?? '',
      'user_agent': body['user_agent'] ?? '',
      'created_at': DateTime.now(),
    };

    final result = await DatabaseService.systemLogs.insertOne(logData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Log created successfully',
      'data': {
        'id': result.id.toHexString(),
        'action': action,
        'details': logData['details'],
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
      return _error('Invalid log ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.systemLogs
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Log not found', statusCode: 404);
    }

    final action = (body['action'] as String?)?.trim();
    if (action == null || action.isEmpty) {
      return _error('action is required for PUT');
    }

    var modifier = modify.set('action', action);
    modifier = modifier.set('details', body['details'] ?? '');
    modifier = modifier.set('ip_address', body['ip_address'] ?? '');
    modifier = modifier.set('user_agent', body['user_agent'] ?? '');

    await DatabaseService.systemLogs.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.systemLogs
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Log updated successfully',
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
      return _error('Invalid log ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.systemLogs
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Log not found', statusCode: 404);
    }

    var modifier = modify;
    var hasUpdate = false;

    if (body.containsKey('action')) {
      modifier = modifier.set('action', body['action']);
      hasUpdate = true;
    }

    if (body.containsKey('details')) {
      modifier = modifier.set('details', body['details']);
      hasUpdate = true;
    }

    if (body.containsKey('ip_address')) {
      modifier = modifier.set('ip_address', body['ip_address']);
      hasUpdate = true;
    }

    if (body.containsKey('user_agent')) {
      modifier = modifier.set('user_agent', body['user_agent']);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.systemLogs.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.systemLogs
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Log partially updated',
      'data': updated != null ? DatabaseService.cleanDocument(updated) : null,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== DELETE ====================
Future<Response> _handleDelete(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];
  final clearOld = context.request.uri.queryParameters['clear_old'];
  final clearAll = context.request.uri.queryParameters['clear_all'];

  try {
    await DatabaseService.startDb();

    if (clearAll == 'true') {
      final result = await DatabaseService.systemLogs.deleteMany({});
      return Response.json(body: {
        'success': true,
        'message': 'All logs deleted',
        'deleted_count': result.nRemoved,
      });
    }

    if (clearOld != null && clearOld.isNotEmpty) {
      final days = int.tryParse(clearOld) ?? 30;
      final cutoff = DateTime.now().subtract(Duration(days: days));

      final oldLogs = await DatabaseService.systemLogs.find().toList();
      final toDelete = oldLogs
          .where((l) {
            final created = l['created_at'] as DateTime?;
            return created != null && created.isBefore(cutoff);
          })
          .map((l) => l['_id'])
          .toList();

      int deletedCount = 0;
      for (final logId in toDelete) {
        final result = await DatabaseService.systemLogs.deleteOne(
          where.eq('_id', logId),
        );
        deletedCount += result.nRemoved;
      }

      return Response.json(body: {
        'success': true,
        'message': 'Old logs deleted (older than $days days)',
        'deleted_count': deletedCount,
      });
    }

    if (id == null || id.isEmpty) {
      return _error('id, clear_old, or clear_all is required');
    }

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid log ID format', statusCode: 400);
    }

    final existing = await DatabaseService.systemLogs
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Log not found', statusCode: 404);
    }

    await DatabaseService.systemLogs
        .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Log deleted permanently',
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