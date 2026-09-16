import 'package:dart_frog/dart_frog.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../../services/database_service.dart';

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
  try {
    final id = context.request.uri.queryParameters['id'];
    final restaurantId = context.request.uri.queryParameters['restaurant_id'];
    final categoryId = context.request.uri.queryParameters['category_id'];
    final search = context.request.uri.queryParameters['search'];

    if (id != null && id.isNotEmpty) {
      return _getMenuById(id);
    }
    if (restaurantId != null && restaurantId.isNotEmpty) {
      return _getMenuByRestaurant(restaurantId);
    }
    if (categoryId != null && categoryId.isNotEmpty) {
      return _getMenuByCategory(categoryId);
    }
    if (search != null && search.isNotEmpty) {
      return _searchMenu(search);
    }
    return _getAllMenu(context);
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getAllMenu(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allMenu = await DatabaseService.menu.find().toList();
    final menu = allMenu.skip(skip).take(limit).toList();
    final total = allMenu.length;

    final data = <Map<String, dynamic>>[];
    for (final m in menu) {
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

Future<Response> _getMenuById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid menu ID format', statusCode: 400);
    }

    final menuMap = await DatabaseService.menu
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (menuMap == null) {
      return _error('Menu item not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(menuMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getMenuByRestaurant(String restaurantId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(restaurantId)) {
      return _error('Invalid restaurant ID format', statusCode: 400);
    }

    final menu = await DatabaseService.menu
        .find(where.eq('restaurant_id', ObjectId.fromHexString(restaurantId)))
        .toList();

    final data = <Map<String, dynamic>>[];
    for (final m in menu) {
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

Future<Response> _getMenuByCategory(String categoryId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(categoryId)) {
      return _error('Invalid category ID format', statusCode: 400);
    }

    final menu = await DatabaseService.menu
        .find(where.eq('category_id', ObjectId.fromHexString(categoryId)))
        .toList();

    final data = <Map<String, dynamic>>[];
    for (final m in menu) {
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

Future<Response> _searchMenu(String search) async {
  try {
    await DatabaseService.startDb();

    final allMenu = await DatabaseService.menu.find().toList();
    final filtered = allMenu.where((m) {
      final name = (m['name'] as String?)?.toLowerCase() ?? '';
      final description = (m['description'] as String?)?.toLowerCase() ?? '';
      final query = search.toLowerCase();
      return name.contains(query) || description.contains(query);
    }).toList();

    final data = <Map<String, dynamic>>[];
    for (final m in filtered) {
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
    final restaurantId = body['restaurant_id'] as String?;
    final name = (body['name'] as String?)?.trim();
    final price = body['price'];

    // Validation
    if (restaurantId == null || restaurantId.isEmpty) {
      return _error('restaurant_id is required');
    }
    if (!ObjectId.isValidHexId(restaurantId)) {
      return _error('Invalid restaurant ID format');
    }
    if (name == null || name.isEmpty) {
      return _error('name is required');
    }
    if (price == null) {
      return _error('price is required');
    }

    final menuData = {
      'restaurant_id': ObjectId.fromHexString(restaurantId),
      'category_id': body['category_id'] != null
          ? ObjectId.fromHexString(body['category_id'] as String)
          : null,
      'name': name,
      'description': body['description'] ?? '',
      'price': (price as num).toDouble(),
      'discount_price': body['discount_price'] != null
          ? (body['discount_price'] as num).toDouble()
          : null,
      'currency': body['currency'] ?? 'USD',
      'preparation_time': body['preparation_time'] ?? 15,
      'is_available': body['is_available'] ?? true,
      'is_veg': body['is_veg'] ?? false,
      'spice_level': body['spice_level'] ?? 'mild',
      'calories': body['calories'],
      'image_urls': body['image_urls'] ?? [],
      'rating': 0.0,
      'total_ratings': 0,
      'created_at': DateTime.now(),
      'updated_at': DateTime.now(),
    };

    final result = await DatabaseService.menu.insertOne(menuData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Menu item created successfully',
      'data': {
        'id': result.id.toHexString(),
        'restaurant_id': restaurantId,
        'name': name,
        'price': menuData['price'],
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
      return _error('Invalid menu ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.menu
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Menu item not found', statusCode: 404);
    }

    final name = (body['name'] as String?)?.trim();
    final price = body['price'];

    if (name == null || name.isEmpty) {
      return _error('name is required for PUT');
    }
    if (price == null) {
      return _error('price is required for PUT');
    }

    var modifier = modify.set('name', name);
    modifier = modifier.set('description', body['description'] ?? '');
    modifier = modifier.set('price', (price as num).toDouble());
    modifier = modifier.set(
      'discount_price',
      body['discount_price'] != null
          ? (body['discount_price'] as num).toDouble()
          : null,
    );
    modifier = modifier.set('currency', body['currency'] ?? 'USD');
    modifier = modifier.set('preparation_time', body['preparation_time'] ?? 15);
    modifier = modifier.set('is_available', body['is_available'] ?? true);
    modifier = modifier.set('is_veg', body['is_veg'] ?? false);
    modifier = modifier.set('spice_level', body['spice_level'] ?? 'mild');
    modifier = modifier.set('calories', body['calories']);
    modifier = modifier.set('image_urls', body['image_urls'] ?? []);
    modifier = modifier.set('updated_at', DateTime.now());

    if (body['category_id'] != null) {
      modifier = modifier.set(
        'category_id',
        ObjectId.fromHexString(body['category_id'] as String),
      );
    }

    await DatabaseService.menu.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.menu
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Menu item updated successfully',
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
      return _error('Invalid menu ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.menu
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Menu item not found', statusCode: 404);
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

    if (body.containsKey('price')) {
      modifier = modifier.set('price', (body['price'] as num).toDouble());
      hasUpdate = true;
    }

    if (body.containsKey('discount_price')) {
      modifier = modifier.set(
        'discount_price',
        body['discount_price'] != null
            ? (body['discount_price'] as num).toDouble()
            : null,
      );
      hasUpdate = true;
    }

    if (body.containsKey('is_available')) {
      modifier = modifier.set('is_available', body['is_available']);
      hasUpdate = true;
    }

    if (body.containsKey('is_veg')) {
      modifier = modifier.set('is_veg', body['is_veg']);
      hasUpdate = true;
    }

    if (body.containsKey('spice_level')) {
      modifier = modifier.set('spice_level', body['spice_level']);
      hasUpdate = true;
    }

    if (body.containsKey('calories')) {
      modifier = modifier.set('calories', body['calories']);
      hasUpdate = true;
    }

    if (body.containsKey('preparation_time')) {
      modifier = modifier.set('preparation_time', body['preparation_time']);
      hasUpdate = true;
    }

    if (body.containsKey('image_urls')) {
      modifier = modifier.set('image_urls', body['image_urls']);
      hasUpdate = true;
    }

    if (body.containsKey('category_id')) {
      modifier = modifier.set(
        'category_id',
        body['category_id'] != null
            ? ObjectId.fromHexString(body['category_id'] as String)
            : null,
      );
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.menu.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.menu
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Menu item partially updated',
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
      return _error('Invalid menu ID format', statusCode: 400);
    }

    final existing = await DatabaseService.menu
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Menu item not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      await DatabaseService.menu
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));
      return Response.json(body: {
        'success': true,
        'message': 'Menu item deleted permanently',
      });
    } else {
      await DatabaseService.menu.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify.set('is_available', false).set('updated_at', DateTime.now()),
      );
      return Response.json(body: {
        'success': true,
        'message': 'Menu item deactivated (soft delete)',
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