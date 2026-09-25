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
  final menuId = context.request.uri.queryParameters['menu_id'];
  final optionGroup = context.request.uri.queryParameters['option_group'];

  if (id != null && id.isNotEmpty) {
    return _getOptionById(id);
  }
  if (menuId != null && menuId.isNotEmpty) {
    return _getOptionsByMenu(menuId, optionGroup);
  }
  return _getAllOptions(context);
}

Future<Response> _getAllOptions(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allOptions = await DatabaseService.menuOptions.find().toList();
    final options = allOptions.skip(skip).take(limit).toList();
    final total = allOptions.length;

    final data = <Map<String, dynamic>>[];
    for (final o in options) {
      data.add(DatabaseService.cleanDocument(o));
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

Future<Response> _getOptionById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid option ID format', statusCode: 400);
    }

    final optionMap = await DatabaseService.menuOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (optionMap == null) {
      return _error('Menu option not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(optionMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getOptionsByMenu(String menuId, String? optionGroup) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(menuId)) {
      return _error('Invalid menu ID format', statusCode: 400);
    }

    final query = <String, dynamic>{
      'menu_id': ObjectId.fromHexString(menuId),
    };
    if (optionGroup != null && optionGroup.isNotEmpty) {
      query['option_group'] = optionGroup;
    }

    final options = await DatabaseService.menuOptions.find(query).toList();

    // Group by option_group
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final o in options) {
      final group = o['option_group'] as String? ?? 'Other';
      grouped.putIfAbsent(group, () => []);
      grouped[group]!.add(DatabaseService.cleanDocument(o));
    }

    return Response.json(body: {
      'success': true,
      'data': options.map((o) => DatabaseService.cleanDocument(o)).toList(),
      'grouped': grouped,
      'count': options.length,
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
    final menuId = body['menu_id'] as String?;
    final optionGroup = (body['option_group'] as String?)?.trim();
    final optionName = (body['option_name'] as String?)?.trim();

    // Validation
    if (menuId == null || !ObjectId.isValidHexId(menuId)) {
      return _error('Valid menu_id is required');
    }
    if (optionGroup == null || optionGroup.isEmpty) {
      return _error('option_group is required');
    }
    if (optionName == null || optionName.isEmpty) {
      return _error('option_name is required');
    }

    final optionData = {
      'menu_id': ObjectId.fromHexString(menuId),
      'option_group': optionGroup,
      'option_name': optionName,
      'option_price': (body['option_price'] as num?)?.toDouble() ?? 0.0,
      'is_required': body['is_required'] ?? false,
      'selection_type': body['selection_type'] ?? 'single',
      'max_select': body['max_select'] ?? 1,
      'sort_order': body['sort_order'] ?? 0,
      'created_at': DateTime.now(),
    };

    final result = await DatabaseService.menuOptions.insertOne(optionData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Menu option created successfully',
      'data': {
        'id': result.id.toHexString(),
        'menu_id': menuId,
        'option_group': optionGroup,
        'option_name': optionName,
        'option_price': optionData['option_price'],
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
      return _error('Invalid option ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.menuOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Menu option not found', statusCode: 404);
    }

    final optionGroup = (body['option_group'] as String?)?.trim();
    final optionName = (body['option_name'] as String?)?.trim();

    if (optionGroup == null || optionGroup.isEmpty) {
      return _error('option_group is required for PUT');
    }
    if (optionName == null || optionName.isEmpty) {
      return _error('option_name is required for PUT');
    }

    var modifier = modify.set('option_group', optionGroup);
    modifier = modifier.set('option_name', optionName);
    modifier = modifier.set(
      'option_price',
      (body['option_price'] as num?)?.toDouble() ?? 0.0,
    );
    modifier = modifier.set('is_required', body['is_required'] ?? false);
    modifier = modifier.set(
      'selection_type',
      body['selection_type'] ?? 'single',
    );
    modifier = modifier.set('max_select', body['max_select'] ?? 1);
    modifier = modifier.set('sort_order', body['sort_order'] ?? 0);

    await DatabaseService.menuOptions.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.menuOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Menu option updated successfully',
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
      return _error('Invalid option ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.menuOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Menu option not found', statusCode: 404);
    }

    var modifier = modify;
    var hasUpdate = false;

    if (body.containsKey('option_group')) {
      final v = (body['option_group'] as String?)?.trim();
      if (v == null || v.isEmpty) return _error('option_group cannot be empty');
      modifier = modifier.set('option_group', v);
      hasUpdate = true;
    }

    if (body.containsKey('option_name')) {
      final v = (body['option_name'] as String?)?.trim();
      if (v == null || v.isEmpty) return _error('option_name cannot be empty');
      modifier = modifier.set('option_name', v);
      hasUpdate = true;
    }

    if (body.containsKey('option_price')) {
      modifier = modifier.set(
        'option_price',
        (body['option_price'] as num).toDouble(),
      );
      hasUpdate = true;
    }

    if (body.containsKey('is_required')) {
      modifier = modifier.set('is_required', body['is_required']);
      hasUpdate = true;
    }

    if (body.containsKey('selection_type')) {
      modifier = modifier.set('selection_type', body['selection_type']);
      hasUpdate = true;
    }

    if (body.containsKey('max_select')) {
      modifier = modifier.set('max_select', body['max_select']);
      hasUpdate = true;
    }

    if (body.containsKey('sort_order')) {
      modifier = modifier.set('sort_order', body['sort_order']);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.menuOptions.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.menuOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Menu option partially updated',
      'data': updated != null ? DatabaseService.cleanDocument(updated) : null,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== DELETE ====================
Future<Response> _handleDelete(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];
  final menuId = context.request.uri.queryParameters['menu_id'];

  try {
    await DatabaseService.startDb();

    // Clear all options for a menu
    if (menuId != null && menuId.isNotEmpty) {
      if (!ObjectId.isValidHexId(menuId)) {
        return _error('Invalid menu ID format', statusCode: 400);
      }

      final result = await DatabaseService.menuOptions
          .deleteMany({'menu_id': ObjectId.fromHexString(menuId)});

      return Response.json(body: {
        'success': true,
        'message': 'All menu options removed',
        'deleted_count': result.nRemoved,
      });
    }

    // Delete single option
    if (id == null || id.isEmpty) {
      return _error('id or menu_id is required');
    }

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid option ID format', statusCode: 400);
    }

    final existing = await DatabaseService.menuOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Menu option not found', statusCode: 404);
    }

    await DatabaseService.menuOptions
        .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Menu option removed',
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