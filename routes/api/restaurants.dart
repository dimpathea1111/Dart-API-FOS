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
    final cuisineType = context.request.uri.queryParameters['cuisine_type'];
    final search = context.request.uri.queryParameters['search'];

    if (id != null && id.isNotEmpty) {
      return _getRestaurantById(id);
    }
    if (cuisineType != null && cuisineType.isNotEmpty) {
      return _getRestaurantsByCuisine(cuisineType);
    }
    if (search != null && search.isNotEmpty) {
      return _searchRestaurants(search);
    }
    return _getAllRestaurants(context);
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getAllRestaurants(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allRestaurants = await DatabaseService.restaurants.find().toList();
    final restaurants = allRestaurants.skip(skip).take(limit).toList();
    final total = allRestaurants.length;

    final data = <Map<String, dynamic>>[];
    for (final r in restaurants) {
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

Future<Response> _getRestaurantById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid restaurant ID format', statusCode: 400);
    }

    final restaurantMap = await DatabaseService.restaurants
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (restaurantMap == null) {
      return _error('Restaurant not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(restaurantMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getRestaurantsByCuisine(String cuisineType) async {
  try {
    await DatabaseService.startDb();

    final restaurants = await DatabaseService.restaurants
        .find(where.eq('cuisine_type', cuisineType))
        .toList();

    final data = <Map<String, dynamic>>[];
    for (final r in restaurants) {
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

Future<Response> _searchRestaurants(String search) async {
  try {
    await DatabaseService.startDb();

    final allRestaurants = await DatabaseService.restaurants.find().toList();
    final filtered = allRestaurants.where((r) {
      final name = (r['name'] as String?)?.toLowerCase() ?? '';
      final description = (r['description'] as String?)?.toLowerCase() ?? '';
      final query = search.toLowerCase();
      return name.contains(query) || description.contains(query);
    }).toList();

    final data = <Map<String, dynamic>>[];
    for (final r in filtered) {
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
    final name = (body['name'] as String?)?.trim();

    if (name == null || name.isEmpty) {
      return _error('name is required');
    }

    final restaurantData = {
      'name': name,
      'description': body['description'] ?? '',
      'cuisine_type': body['cuisine_type'] ?? 'Khmer Food',
      'rating': (body['rating'] ?? 0.0).toDouble(),
      'delivery_fee': (body['delivery_fee'] ?? 0.0).toDouble(),
      'min_order_amount': (body['min_order_amount'] ?? 0.0).toDouble(),
      'phone': body['phone'] ?? '',
      'email': body['email'] ?? '',
      'opening_time': body['opening_time'] ?? '08:00',
      'closing_time': body['closing_time'] ?? '20:00',
      'is_active': body['is_active'] ?? true,
      'banner_image': body['banner_image'],
      'created_at': DateTime.now(),
      'updated_at': DateTime.now(),
    };

    final result =
        await DatabaseService.restaurants.insertOne(restaurantData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Restaurant created successfully',
      'data': {
        'id': result.id.toHexString(),
        ...restaurantData,
        'created_at': restaurantData['created_at'].toString(),
        'updated_at': restaurantData['updated_at'].toString(),
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
      return _error('Invalid restaurant ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.restaurants
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Restaurant not found', statusCode: 404);
    }

    final name = (body['name'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      return _error('name is required for PUT');
    }

    var modifier = modify.set('name', name);
    modifier = modifier.set('description', body['description'] ?? '');
    modifier =
        modifier.set('cuisine_type', body['cuisine_type'] ?? 'Khmer Food');
    modifier = modifier.set('rating', (body['rating'] ?? 0.0).toDouble());
    modifier = modifier.set(
      'delivery_fee',
      (body['delivery_fee'] ?? 0.0).toDouble(),
    );
    modifier = modifier.set(
      'min_order_amount',
      (body['min_order_amount'] ?? 0.0).toDouble(),
    );
    modifier = modifier.set('phone', body['phone'] ?? '');
    modifier = modifier.set('email', body['email'] ?? '');
    modifier = modifier.set('opening_time', body['opening_time'] ?? '08:00');
    modifier = modifier.set('closing_time', body['closing_time'] ?? '20:00');
    modifier = modifier.set('is_active', body['is_active'] ?? true);
    modifier = modifier.set('banner_image', body['banner_image']);
    modifier = modifier.set('updated_at', DateTime.now());

    await DatabaseService.restaurants.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.restaurants
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Restaurant updated successfully',
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
      return _error('Invalid restaurant ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.restaurants
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Restaurant not found', statusCode: 404);
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

    if (body.containsKey('cuisine_type')) {
      modifier = modifier.set('cuisine_type', body['cuisine_type']);
      hasUpdate = true;
    }

    if (body.containsKey('rating')) {
      modifier = modifier.set('rating', (body['rating'] as num).toDouble());
      hasUpdate = true;
    }

    if (body.containsKey('delivery_fee')) {
      modifier = modifier.set(
        'delivery_fee',
        (body['delivery_fee'] as num).toDouble(),
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

    if (body.containsKey('phone')) {
      modifier = modifier.set('phone', body['phone']);
      hasUpdate = true;
    }

    if (body.containsKey('email')) {
      modifier = modifier.set('email', body['email']);
      hasUpdate = true;
    }

    if (body.containsKey('opening_time')) {
      modifier = modifier.set('opening_time', body['opening_time']);
      hasUpdate = true;
    }

    if (body.containsKey('closing_time')) {
      modifier = modifier.set('closing_time', body['closing_time']);
      hasUpdate = true;
    }

    if (body.containsKey('is_active')) {
      modifier = modifier.set('is_active', body['is_active']);
      hasUpdate = true;
    }

    if (body.containsKey('banner_image')) {
      modifier = modifier.set('banner_image', body['banner_image']);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.restaurants.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.restaurants
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Restaurant partially updated',
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
      return _error('Invalid restaurant ID format', statusCode: 400);
    }

    final existing = await DatabaseService.restaurants
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Restaurant not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      await DatabaseService.restaurants
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));
      return Response.json(body: {
        'success': true,
        'message': 'Restaurant deleted permanently',
      });
    } else {
      await DatabaseService.restaurants.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify.set('is_active', false).set('updated_at', DateTime.now()),
      );
      return Response.json(body: {
        'success': true,
        'message': 'Restaurant deactivated (soft delete)',
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