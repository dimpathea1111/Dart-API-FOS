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
  final code = context.request.uri.queryParameters['code'];
  final restaurantId = context.request.uri.queryParameters['restaurant_id'];
  final isActive = context.request.uri.queryParameters['is_active'];

  if (id != null && id.isNotEmpty) {
    return _getPromotionById(id);
  }
  if (code != null && code.isNotEmpty) {
    return _getPromotionByCode(code);
  }
  if (restaurantId != null && restaurantId.isNotEmpty) {
    return _getPromotionsByRestaurant(restaurantId, isActive);
  }
  return _getAllPromotions(context, isActive);
}

Future<Response> _getAllPromotions(
  RequestContext context,
  String? isActive,
) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    var allPromotions = await DatabaseService.promotions.find().toList();

    if (isActive != null && isActive.isNotEmpty) {
      final activeBool = isActive.toLowerCase() == 'true';
      allPromotions =
          allPromotions.where((p) => p['is_active'] == activeBool).toList();
    }

    final promotions = allPromotions.skip(skip).take(limit).toList();
    final total = allPromotions.length;

    final data = <Map<String, dynamic>>[];
    for (final p in promotions) {
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

Future<Response> _getPromotionById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid promotion ID format', statusCode: 400);
    }

    final promoMap = await DatabaseService.promotions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (promoMap == null) {
      return _error('Promotion not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(promoMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getPromotionByCode(String code) async {
  try {
    await DatabaseService.startDb();

    final promoMap = await DatabaseService.promotions
        .findOne(where.eq('code', code.toUpperCase()));

    if (promoMap == null) {
      return _error('Promotion not found', statusCode: 404);
    }

    // Check if active and within date range
    final isActive = promoMap['is_active'] == true;
    final now = DateTime.now();
    final startDate = promoMap['start_date'] as DateTime?;
    final endDate = promoMap['end_date'] as DateTime?;

    final isValid = isActive &&
        startDate != null &&
        endDate != null &&
        now.isAfter(startDate) &&
        now.isBefore(endDate);

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(promoMap),
      'is_valid': isValid,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getPromotionsByRestaurant(
  String restaurantId,
  String? isActive,
) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(restaurantId)) {
      return _error('Invalid restaurant ID format', statusCode: 400);
    }

    final query = <String, dynamic>{
      'restaurant_id': ObjectId.fromHexString(restaurantId),
    };
    if (isActive != null && isActive.isNotEmpty) {
      query['is_active'] = isActive.toLowerCase() == 'true';
    }

    final promotions =
        await DatabaseService.promotions.find(query).toList();

    final data = <Map<String, dynamic>>[];
    for (final p in promotions) {
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
    final name = (body['name'] as String?)?.trim();
    final code = (body['code'] as String?)?.trim().toUpperCase();
    final discountType = (body['discount_type'] as String?)?.trim();
    final discountValue = body['discount_value'];
    final startDate = body['start_date'] as String?;
    final endDate = body['end_date'] as String?;

    // Validation
    if (name == null || name.isEmpty) {
      return _error('name is required');
    }
    if (code == null || code.isEmpty) {
      return _error('code is required');
    }
    if (discountType == null || discountType.isEmpty) {
      return _error('discount_type is required');
    }
    if (!['percentage', 'fixed', 'free_delivery'].contains(discountType)) {
      return _error('discount_type must be percentage, fixed, or free_delivery');
    }
    if (discountValue == null) {
      return _error('discount_value is required');
    }
    if (startDate == null || endDate == null) {
      return _error('start_date and end_date are required');
    }

    // Check code uniqueness
    final existing = await DatabaseService.promotions
        .findOne(where.eq('code', code));
    if (existing != null) {
      return _error('Promotion code already exists', statusCode: 409);
    }

    final promoData = {
      'restaurant_id': body['restaurant_id'] != null
          ? ObjectId.fromHexString(body['restaurant_id'] as String)
          : null,
      'name': name,
      'description': body['description'] ?? '',
      'code': code,
      'discount_type': discountType,
      'discount_value': (discountValue as num).toDouble(),
      'min_order_amount': (body['min_order_amount'] as num?)?.toDouble(),
      'max_discount': (body['max_discount'] as num?)?.toDouble(),
      'applicable_to': body['applicable_to'] ?? 'all',
      'start_date': DateTime.parse(startDate),
      'end_date': DateTime.parse(endDate),
      'usage_limit': body['usage_limit'],
      'used_count': 0,
      'is_active': body['is_active'] ?? true,
      'created_at': DateTime.now(),
      'updated_at': DateTime.now(),
    };

    final result = await DatabaseService.promotions.insertOne(promoData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Promotion created successfully',
      'data': {
        'id': result.id.toHexString(),
        'name': name,
        'code': code,
        'discount_type': discountType,
        'discount_value': promoData['discount_value'],
        'is_active': promoData['is_active'],
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
      return _error('Invalid promotion ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.promotions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Promotion not found', statusCode: 404);
    }

    final name = (body['name'] as String?)?.trim();
    final code = (body['code'] as String?)?.trim().toUpperCase();
    final discountType = (body['discount_type'] as String?)?.trim();
    final discountValue = body['discount_value'];
    final startDate = body['start_date'] as String?;
    final endDate = body['end_date'] as String?;

    if (name == null || name.isEmpty) {
      return _error('name is required for PUT');
    }
    if (code == null || code.isEmpty) {
      return _error('code is required for PUT');
    }
    if (discountType == null || discountType.isEmpty) {
      return _error('discount_type is required for PUT');
    }
    if (discountValue == null) {
      return _error('discount_value is required for PUT');
    }
    if (startDate == null || endDate == null) {
      return _error('start_date and end_date are required for PUT');
    }

    // Check code conflict
    final codeConflict = await DatabaseService.promotions.findOne({
      'code': code,
      '_id': {'\$ne': ObjectId.fromHexString(id)},
    });
    if (codeConflict != null) {
      return _error('Promotion code already used', statusCode: 409);
    }

    var modifier = modify.set('name', name);
    modifier = modifier.set('description', body['description'] ?? '');
    modifier = modifier.set('code', code);
    modifier = modifier.set('discount_type', discountType);
    modifier = modifier.set(
      'discount_value',
      (discountValue as num).toDouble(),
    );
    modifier = modifier.set(
      'min_order_amount',
      (body['min_order_amount'] as num?)?.toDouble(),
    );
    modifier = modifier.set(
      'max_discount',
      (body['max_discount'] as num?)?.toDouble(),
    );
    modifier = modifier.set('applicable_to', body['applicable_to'] ?? 'all');
    modifier = modifier.set('start_date', DateTime.parse(startDate));
    modifier = modifier.set('end_date', DateTime.parse(endDate));
    modifier = modifier.set('usage_limit', body['usage_limit']);
    modifier = modifier.set('is_active', body['is_active'] ?? true);
    modifier = modifier.set('updated_at', DateTime.now());

    await DatabaseService.promotions.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.promotions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Promotion updated successfully',
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
      return _error('Invalid promotion ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.promotions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Promotion not found', statusCode: 404);
    }

    var modifier = modify.set('updated_at', DateTime.now());
    var hasUpdate = false;

    if (body.containsKey('name')) {
      final v = (body['name'] as String?)?.trim();
      if (v == null || v.isEmpty) return _error('name cannot be empty');
      modifier = modifier.set('name', v);
      hasUpdate = true;
    }

    if (body.containsKey('description')) {
      modifier = modifier.set('description', body['description'] ?? '');
      hasUpdate = true;
    }

    if (body.containsKey('discount_type')) {
      modifier = modifier.set('discount_type', body['discount_type']);
      hasUpdate = true;
    }

    if (body.containsKey('discount_value')) {
      modifier = modifier.set(
        'discount_value',
        (body['discount_value'] as num).toDouble(),
      );
      hasUpdate = true;
    }

    if (body.containsKey('min_order_amount')) {
      modifier = modifier.set(
        'min_order_amount',
        (body['min_order_amount'] as num).toDouble(),
      );
      hasUpdate = true;
    }

    if (body.containsKey('max_discount')) {
      modifier = modifier.set(
        'max_discount',
        (body['max_discount'] as num).toDouble(),
      );
      hasUpdate = true;
    }

    if (body.containsKey('start_date')) {
      modifier = modifier.set(
        'start_date',
        DateTime.parse(body['start_date'] as String),
      );
      hasUpdate = true;
    }

    if (body.containsKey('end_date')) {
      modifier = modifier.set(
        'end_date',
        DateTime.parse(body['end_date'] as String),
      );
      hasUpdate = true;
    }

    if (body.containsKey('usage_limit')) {
      modifier = modifier.set('usage_limit', body['usage_limit']);
      hasUpdate = true;
    }

    if (body.containsKey('is_active')) {
      modifier = modifier.set('is_active', body['is_active']);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.promotions.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.promotions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Promotion partially updated',
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
      return _error('Invalid promotion ID format', statusCode: 400);
    }

    final existing = await DatabaseService.promotions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Promotion not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      await DatabaseService.promotions
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));
      return Response.json(body: {
        'success': true,
        'message': 'Promotion deleted permanently',
      });
    } else {
      await DatabaseService.promotions.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify.set('is_active', false).set('updated_at', DateTime.now()),
      );
      return Response.json(body: {
        'success': true,
        'message': 'Promotion deactivated (soft delete)',
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