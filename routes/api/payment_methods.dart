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
  final isDefault = context.request.uri.queryParameters['is_default'];
  final methodType = context.request.uri.queryParameters['method_type'];

  if (id != null && id.isNotEmpty) {
    return _getMethodById(id);
  }
  if (userId != null && userId.isNotEmpty) {
    return _getMethodsByUser(userId, isDefault, methodType);
  }
  return _getAllMethods(context);
}

Future<Response> _getAllMethods(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allMethods =
        await DatabaseService.paymentMethods.find().toList();
    final methods = allMethods.skip(skip).take(limit).toList();
    final total = allMethods.length;

    final data = <Map<String, dynamic>>[];
    for (final m in methods) {
      data.add(DatabaseService.cleanDocument(m));
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

Future<Response> _getMethodById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid payment method ID format', statusCode: 400);
    }

    final methodMap = await DatabaseService.paymentMethods
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (methodMap == null) {
      return _error('Payment method not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(methodMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getMethodsByUser(
  String userId,
  String? isDefault,
  String? methodType,
) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(userId)) {
      return _error('Invalid user ID format', statusCode: 400);
    }

    final query = <String, dynamic>{
      'user_id': ObjectId.fromHexString(userId),
      'is_active': true,
    };
    if (isDefault != null && isDefault.isNotEmpty) {
      query['is_default'] = isDefault.toLowerCase() == 'true';
    }
    if (methodType != null && methodType.isNotEmpty) {
      query['method_type'] = methodType;
    }

    final methods =
        await DatabaseService.paymentMethods.find(query).toList();

    final data = <Map<String, dynamic>>[];
    for (final m in methods) {
      data.add(DatabaseService.cleanDocument(m));
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
    final methodType = (body['method_type'] as String?)?.trim();

    if (userId == null || !ObjectId.isValidHexId(userId)) {
      return _error('Valid user_id is required');
    }
    if (methodType == null || methodType.isEmpty) {
      return _error('method_type is required');
    }
    if (!['card', 'wallet', 'bank_transfer', 'cod'].contains(methodType)) {
      return _error(
          'method_type must be card, wallet, bank_transfer, or cod');
    }

    final isDefault = body['is_default'] == true;

    // បើ is_default = true ត្រូវ set default ចាស់ = false
    if (isDefault) {
      await DatabaseService.paymentMethods.updateMany(
        {'user_id': ObjectId.fromHexString(userId), 'is_default': true},
        modify.set('is_default', false),
      );
    }

    final methodData = {
      'user_id': ObjectId.fromHexString(userId),
      'method_type': methodType,
      'provider': body['provider'] ?? '',
      'card_last4': body['card_last4'] ?? '',
      'card_brand': body['card_brand'] ?? '',
      'expiry_date': body['expiry_date'] != null
          ? DateTime.parse(body['expiry_date'] as String)
          : null,
      'account_info': body['account_info'] ?? '',
      'is_default': isDefault,
      'is_active': body['is_active'] ?? true,
      'created_at': DateTime.now(),
      'updated_at': DateTime.now(),
    };

    final result =
        await DatabaseService.paymentMethods.insertOne(methodData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Payment method added successfully',
      'data': {
        'id': result.id.toHexString(),
        'user_id': userId,
        'method_type': methodType,
        'provider': methodData['provider'],
        'is_default': isDefault,
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
      return _error('Invalid payment method ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.paymentMethods
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Payment method not found', statusCode: 404);
    }

    final methodType = (body['method_type'] as String?)?.trim();
    if (methodType == null || methodType.isEmpty) {
      return _error('method_type is required for PUT');
    }

    final isDefault = body['is_default'] ?? false;

    // បើ is_default = true ត្រូវ set default ចាស់ = false
    if (isDefault) {
      await DatabaseService.paymentMethods.updateMany(
        {
          'user_id': existing['user_id'],
          'is_default': true,
          '_id': {'\$ne': ObjectId.fromHexString(id)},
        },
        modify.set('is_default', false),
      );
    }

    var modifier = modify.set('method_type', methodType);
    modifier = modifier.set('provider', body['provider'] ?? '');
    modifier = modifier.set('card_last4', body['card_last4'] ?? '');
    modifier = modifier.set('card_brand', body['card_brand'] ?? '');
    modifier = modifier.set(
      'expiry_date',
      body['expiry_date'] != null
          ? DateTime.parse(body['expiry_date'] as String)
          : null,
    );
    modifier = modifier.set('account_info', body['account_info'] ?? '');
    modifier = modifier.set('is_default', isDefault);
    modifier = modifier.set('is_active', body['is_active'] ?? true);
    modifier = modifier.set('updated_at', DateTime.now());

    await DatabaseService.paymentMethods.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.paymentMethods
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Payment method updated successfully',
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
      return _error('Invalid payment method ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.paymentMethods
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Payment method not found', statusCode: 404);
    }

    var modifier = modify.set('updated_at', DateTime.now());
    var hasUpdate = false;

    if (body.containsKey('provider')) {
      modifier = modifier.set('provider', body['provider']);
      hasUpdate = true;
    }

    if (body.containsKey('card_last4')) {
      modifier = modifier.set('card_last4', body['card_last4']);
      hasUpdate = true;
    }

    if (body.containsKey('card_brand')) {
      modifier = modifier.set('card_brand', body['card_brand']);
      hasUpdate = true;
    }

    if (body.containsKey('expiry_date')) {
      modifier = modifier.set(
        'expiry_date',
        DateTime.parse(body['expiry_date'] as String),
      );
      hasUpdate = true;
    }

    if (body.containsKey('account_info')) {
      modifier = modifier.set('account_info', body['account_info']);
      hasUpdate = true;
    }

    if (body.containsKey('is_active')) {
      modifier = modifier.set('is_active', body['is_active']);
      hasUpdate = true;
    }

    if (body.containsKey('is_default')) {
      final isDefault = body['is_default'] == true;
      if (isDefault) {
        await DatabaseService.paymentMethods.updateMany(
          {
            'user_id': existing['user_id'],
            'is_default': true,
            '_id': {'\$ne': ObjectId.fromHexString(id)},
          },
          modify.set('is_default', false),
        );
      }
      modifier = modifier.set('is_default', isDefault);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.paymentMethods.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.paymentMethods
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Payment method partially updated',
      'data': updated != null ? DatabaseService.cleanDocument(updated) : null,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== DELETE ====================
Future<Response> _handleDelete(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];
  final userId = context.request.uri.queryParameters['user_id'];

  try {
    await DatabaseService.startDb();

    // Clear all methods for user
    if (userId != null && userId.isNotEmpty) {
      if (!ObjectId.isValidHexId(userId)) {
        return _error('Invalid user ID format', statusCode: 400);
      }

      final result = await DatabaseService.paymentMethods
          .deleteMany({'user_id': ObjectId.fromHexString(userId)});

      return Response.json(body: {
        'success': true,
        'message': 'All payment methods deleted',
        'deleted_count': result.nRemoved,
      });
    }

    // Delete single method
    if (id == null || id.isEmpty) {
      return _error('id or user_id is required');
    }

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid payment method ID format', statusCode: 400);
    }

    final existing = await DatabaseService.paymentMethods
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Payment method not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      await DatabaseService.paymentMethods
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));
      return Response.json(body: {
        'success': true,
        'message': 'Payment method deleted permanently',
      });
    } else {
      await DatabaseService.paymentMethods.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify
            .set('is_active', false)
            .set('updated_at', DateTime.now()),
      );
      return Response.json(body: {
        'success': true,
        'message': 'Payment method deactivated (soft delete)',
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
