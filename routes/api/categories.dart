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
    final search = context.request.uri.queryParameters['search'];

    if (id != null && id.isNotEmpty) {
      return _getCategoryById(id);
    }
    if (search != null && search.isNotEmpty) {
      return _searchCategories(search);
    }
    return _getAllCategories(context);
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getAllCategories(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allCategories = await DatabaseService.categories.find().toList();
    final categories = allCategories.skip(skip).take(limit).toList();
    final total = allCategories.length;

    final data = <Map<String, dynamic>>[];
    for (final c in categories) {
      data.add(DatabaseService.cleanDocument(c));
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

Future<Response> _getCategoryById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid category ID format', statusCode: 400);
    }

    final categoryMap = await DatabaseService.categories
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (categoryMap == null) {
      return _error('Category not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(categoryMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _searchCategories(String search) async {
  try {
    await DatabaseService.startDb();

    final allCategories = await DatabaseService.categories.find().toList();
    final filtered = allCategories.where((c) {
      final name = (c['name'] as String?)?.toLowerCase() ?? '';
      final description = (c['description'] as String?)?.toLowerCase() ?? '';
      final query = search.toLowerCase();
      return name.contains(query) || description.contains(query);
    }).toList();

    final data = <Map<String, dynamic>>[];
    for (final c in filtered) {
      data.add(DatabaseService.cleanDocument(c));
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

    // Check duplicate name
    final existing = await DatabaseService.categories.findOne({'name': name});
    if (existing != null) {
      return _error('Category already exists', statusCode: 409);
    }

    final categoryData = {
      'name': name,
      'description': body['description'] ?? '',
      'image_url': body['image_url'],
      'is_active': body['is_active'] ?? true,
      'created_at': DateTime.now(),
    };

    final result = await DatabaseService.categories.insertOne(categoryData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Category created successfully',
      'data': {
        'id': result.id.toHexString(),
        'name': name,
        'description': categoryData['description'],
        'image_url': categoryData['image_url'],
        'is_active': categoryData['is_active'],
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
      return _error('Invalid category ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.categories
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Category not found', statusCode: 404);
    }

    final name = (body['name'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      return _error('name is required for PUT');
    }

    // Check name conflict
    final nameConflict = await DatabaseService.categories.findOne({
      'name': name,
      '_id': {'\$ne': ObjectId.fromHexString(id)},
    });
    if (nameConflict != null) {
      return _error('Category name already exists', statusCode: 409);
    }

    var modifier = modify.set('name', name);
    modifier = modifier.set('description', body['description'] ?? '');
    modifier = modifier.set('image_url', body['image_url']);
    modifier = modifier.set('is_active', body['is_active'] ?? true);
    modifier = modifier.set('updated_at', DateTime.now());

    await DatabaseService.categories.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.categories
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Category updated successfully',
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
      return _error('Invalid category ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.categories
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Category not found', statusCode: 404);
    }

    var modifier = modify.set('updated_at', DateTime.now());
    var hasUpdate = false;

    if (body.containsKey('name')) {
      final v = (body['name'] as String?)?.trim();
      if (v == null || v.isEmpty) return _error('name cannot be empty');

      // Check conflict
      final conflict = await DatabaseService.categories.findOne({
        'name': v,
        '_id': {'\$ne': ObjectId.fromHexString(id)},
      });
      if (conflict != null) {
        return _error('Category name already exists', statusCode: 409);
      }

      modifier = modifier.set('name', v);
      hasUpdate = true;
    }

    if (body.containsKey('description')) {
      modifier = modifier.set('description', body['description'] ?? '');
      hasUpdate = true;
    }

    if (body.containsKey('image_url')) {
      modifier = modifier.set('image_url', body['image_url']);
      hasUpdate = true;
    }

    if (body.containsKey('is_active')) {
      modifier = modifier.set('is_active', body['is_active']);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.categories.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.categories
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Category partially updated',
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
      return _error('Invalid category ID format', statusCode: 400);
    }

    final existing = await DatabaseService.categories
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Category not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      await DatabaseService.categories
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));
      return Response.json(body: {
        'success': true,
        'message': 'Category deleted permanently',
      });
    } else {
      await DatabaseService.categories.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify.set('is_active', false).set('updated_at', DateTime.now()),
      );
      return Response.json(body: {
        'success': true,
        'message': 'Category deactivated (soft delete)',
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