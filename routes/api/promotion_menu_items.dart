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
  final promotionId = context.request.uri.queryParameters['promotion_id'];
  final menuId = context.request.uri.queryParameters['menu_id'];

  if (id != null && id.isNotEmpty) {
    return _getItemById(id);
  }
  if (promotionId != null && promotionId.isNotEmpty) {
    return _getItemsByPromotion(promotionId);
  }
  if (menuId != null && menuId.isNotEmpty) {
    return _getItemsByMenu(menuId);
  }
  return _getAllItems(context);
}

Future<Response> _getAllItems(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allItems =
        await DatabaseService.promotionMenuItems.find().toList();
    final items = allItems.skip(skip).take(limit).toList();
    final total = allItems.length;

    final data = <Map<String, dynamic>>[];
    for (final i in items) {
      data.add(DatabaseService.cleanDocument(i));
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

Future<Response> _getItemById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid item ID format', statusCode: 400);
    }

    final itemMap = await DatabaseService.promotionMenuItems
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (itemMap == null) {
      return _error('Promotion menu item not found', statusCode: 404);
    }

    // ទាញ promotion និង menu details
    final promotionId = itemMap['promotion_id'];
    final menuId = itemMap['menu_id'];

    Map<String, dynamic>? promotionData;
    Map<String, dynamic>? menuData;

    if (promotionId is ObjectId) {
      final promotion = await DatabaseService.promotions
          .findOne(where.eq('_id', promotionId));
      if (promotion != null) {
        promotionData = DatabaseService.cleanDocument(promotion);
      }
    }

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
        if (promotionData != null) 'promotion': promotionData,
        if (menuData != null) 'menu': menuData,
      },
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getItemsByPromotion(String promotionId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(promotionId)) {
      return _error('Invalid promotion ID format', statusCode: 400);
    }

    final items = await DatabaseService.promotionMenuItems
        .find(where.eq('promotion_id', ObjectId.fromHexString(promotionId)))
        .toList();

    final data = <Map<String, dynamic>>[];
    for (final i in items) {
      final cleaned = DatabaseService.cleanDocument(i);
      final menuId = i['menu_id'];

      if (menuId is ObjectId) {
        final menu = await DatabaseService.menu
            .findOne(where.eq('_id', menuId));
        if (menu != null) {
          cleaned['menu'] = DatabaseService.cleanDocument(menu);
        }
      }
      data.add(cleaned);
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

Future<Response> _getItemsByMenu(String menuId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(menuId)) {
      return _error('Invalid menu ID format', statusCode: 400);
    }

    final items = await DatabaseService.promotionMenuItems
        .find(where.eq('menu_id', ObjectId.fromHexString(menuId)))
        .toList();

    final data = <Map<String, dynamic>>[];
    for (final i in items) {
      data.add(DatabaseService.cleanDocument(i));
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
    final promotionId = body['promotion_id'] as String?;
    final menuId = body['menu_id'] as String?;

    // Validation
    if (promotionId == null || !ObjectId.isValidHexId(promotionId)) {
      return _error('Valid promotion_id is required');
    }
    if (menuId == null || !ObjectId.isValidHexId(menuId)) {
      return _error('Valid menu_id is required');
    }

    // Check if promotion exists
    final promotion = await DatabaseService.promotions
        .findOne(where.eq('_id', ObjectId.fromHexString(promotionId)));
    if (promotion == null) {
      return _error('Promotion not found', statusCode: 404);
    }

    // Check if menu exists
    final menu = await DatabaseService.menu
        .findOne(where.eq('_id', ObjectId.fromHexString(menuId)));
    if (menu == null) {
      return _error('Menu item not found', statusCode: 404);
    }

    // Check if already linked
    final existing = await DatabaseService.promotionMenuItems.findOne({
      'promotion_id': ObjectId.fromHexString(promotionId),
      'menu_id': ObjectId.fromHexString(menuId),
    });
    if (existing != null) {
      return _error('Menu item already linked to this promotion',
          statusCode: 409);
    }

    final itemData = {
      'promotion_id': ObjectId.fromHexString(promotionId),
      'menu_id': ObjectId.fromHexString(menuId),
      'created_at': DateTime.now(),
    };

    final result =
        await DatabaseService.promotionMenuItems.insertOne(itemData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Menu item linked to promotion successfully',
      'data': {
        'id': result.id.toHexString(),
        'promotion_id': promotionId,
        'menu_id': menuId,
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
      return _error('Invalid item ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.promotionMenuItems
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Promotion menu item not found', statusCode: 404);
    }

    final promotionId = body['promotion_id'] as String?;
    final menuId = body['menu_id'] as String?;

    if (promotionId == null || !ObjectId.isValidHexId(promotionId)) {
      return _error('Valid promotion_id is required for PUT');
    }
    if (menuId == null || !ObjectId.isValidHexId(menuId)) {
      return _error('Valid menu_id is required for PUT');
    }

    // Check if already linked (excluding current)
    final conflict = await DatabaseService.promotionMenuItems.findOne({
      'promotion_id': ObjectId.fromHexString(promotionId),
      'menu_id': ObjectId.fromHexString(menuId),
      '_id': {'\$ne': ObjectId.fromHexString(id)},
    });
    if (conflict != null) {
      return _error('Menu item already linked to this promotion',
          statusCode: 409);
    }

    var modifier = modify.set(
      'promotion_id',
      ObjectId.fromHexString(promotionId),
    );
    modifier = modifier.set('menu_id', ObjectId.fromHexString(menuId));

    await DatabaseService.promotionMenuItems.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.promotionMenuItems
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Promotion menu item updated successfully',
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
      return _error('Invalid item ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.promotionMenuItems
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Promotion menu item not found', statusCode: 404);
    }

    var modifier = modify;
    var hasUpdate = false;

    if (body.containsKey('promotion_id')) {
      final v = body['promotion_id'] as String?;
      if (v == null || !ObjectId.isValidHexId(v)) {
        return _error('Invalid promotion ID format');
      }
      modifier = modifier.set('promotion_id', ObjectId.fromHexString(v));
      hasUpdate = true;
    }

    if (body.containsKey('menu_id')) {
      final v = body['menu_id'] as String?;
      if (v == null || !ObjectId.isValidHexId(v)) {
        return _error('Invalid menu ID format');
      }
      modifier = modifier.set('menu_id', ObjectId.fromHexString(v));
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.promotionMenuItems.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.promotionMenuItems
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Promotion menu item partially updated',
      'data': updated != null ? DatabaseService.cleanDocument(updated) : null,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== DELETE ====================
Future<Response> _handleDelete(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];
  final promotionId = context.request.uri.queryParameters['promotion_id'];
  final menuId = context.request.uri.queryParameters['menu_id'];

  try {
    await DatabaseService.startDb();

    // Delete by promotion_id + menu_id
    if (promotionId != null && menuId != null) {
      if (!ObjectId.isValidHexId(promotionId)) {
        return _error('Invalid promotion ID format', statusCode: 400);
      }
      if (!ObjectId.isValidHexId(menuId)) {
        return _error('Invalid menu ID format', statusCode: 400);
      }

    final result = await DatabaseService.promotionMenuItems.deleteOne({
  'promotion_id': ObjectId.fromHexString(promotionId),
  'menu_id': ObjectId.fromHexString(menuId),
});

if (result.nRemoved == 0) {
  return _error('Promotion menu item not found', statusCode: 404);
}

      return Response.json(body: {
        'success': true,
        'message': 'Menu item unlinked from promotion',
      });
    }

    // Clear all items for a promotion
    if (promotionId != null && promotionId.isNotEmpty) {
      if (!ObjectId.isValidHexId(promotionId)) {
        return _error('Invalid promotion ID format', statusCode: 400);
      }

      final result = await DatabaseService.promotionMenuItems
          .deleteMany({'promotion_id': ObjectId.fromHexString(promotionId)});

      return Response.json(body: {
        'success': true,
        'message': 'All menu items unlinked from promotion',
        'deleted_count': result.nRemoved,
      });
    }

    // Delete single item
    if (id == null || id.isEmpty) {
      return _error('id, promotion_id, or (promotion_id + menu_id) is required');
    }

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid item ID format', statusCode: 400);
    }

    final existing = await DatabaseService.promotionMenuItems
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Promotion menu item not found', statusCode: 404);
    }

    await DatabaseService.promotionMenuItems
        .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Promotion menu item deleted',
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