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
  final orderItemId = context.request.uri.queryParameters['order_item_id'];
  final menuOptionId = context.request.uri.queryParameters['menu_option_id'];

  if (id != null && id.isNotEmpty) {
    return _getOptionById(id);
  }
  if (orderItemId != null && orderItemId.isNotEmpty) {
    return _getOptionsByOrderItem(orderItemId);
  }
  if (menuOptionId != null && menuOptionId.isNotEmpty) {
    return _getOptionsByMenuOption(menuOptionId);
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

    final allOptions =
        await DatabaseService.orderItemOptions.find().toList();
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

    final optionMap = await DatabaseService.orderItemOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (optionMap == null) {
      return _error('Order item option not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(optionMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getOptionsByOrderItem(String orderItemId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(orderItemId)) {
      return _error('Invalid order item ID format', statusCode: 400);
    }

    final options = await DatabaseService.orderItemOptions
        .find(where.eq('order_item_id', ObjectId.fromHexString(orderItemId)))
        .toList();

    final data = <Map<String, dynamic>>[];
    double totalPrice = 0;

    for (final o in options) {
      final cleaned = DatabaseService.cleanDocument(o);
      totalPrice += (o['option_price'] as num?)?.toDouble() ?? 0;
      data.add(cleaned);
    }

    return Response.json(body: {
      'success': true,
      'data': data,
      'count': data.length,
      'total_option_price': totalPrice,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getOptionsByMenuOption(String menuOptionId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(menuOptionId)) {
      return _error('Invalid menu option ID format', statusCode: 400);
    }

    final options = await DatabaseService.orderItemOptions
        .find(where.eq(
          'menu_option_id',
          ObjectId.fromHexString(menuOptionId),
        ))
        .toList();

    final data = <Map<String, dynamic>>[];
    for (final o in options) {
      data.add(DatabaseService.cleanDocument(o));
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
    final orderItemId = body['order_item_id'] as String?;
    final menuOptionId = body['menu_option_id'] as String?;
    final optionName = (body['option_name'] as String?)?.trim();
    final optionPrice = body['option_price'];
    final quantity = body['quantity'] ?? 1;

    // Validation
    if (orderItemId == null || !ObjectId.isValidHexId(orderItemId)) {
      return _error('Valid order_item_id is required');
    }
    if (menuOptionId == null || !ObjectId.isValidHexId(menuOptionId)) {
      return _error('Valid menu_option_id is required');
    }
    if (optionName == null || optionName.isEmpty) {
      return _error('option_name is required');
    }
    if (optionPrice == null) {
      return _error('option_price is required');
    }

    final optionData = {
      'order_item_id': ObjectId.fromHexString(orderItemId),
      'menu_option_id': ObjectId.fromHexString(menuOptionId),
      'option_name': optionName,
      'option_price': (optionPrice as num).toDouble(),
      'quantity': (quantity as num).toInt(),
      'created_at': DateTime.now(),
    };

    final result =
        await DatabaseService.orderItemOptions.insertOne(optionData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Order item option created successfully',
      'data': {
        'id': result.id.toHexString(),
        'order_item_id': orderItemId,
        'menu_option_id': menuOptionId,
        'option_name': optionName,
        'option_price': optionData['option_price'],
        'quantity': optionData['quantity'],
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

    final existing = await DatabaseService.orderItemOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Order item option not found', statusCode: 404);
    }

    final optionName = (body['option_name'] as String?)?.trim();
    final optionPrice = body['option_price'];
    final quantity = body['quantity'];

    if (optionName == null || optionName.isEmpty) {
      return _error('option_name is required for PUT');
    }
    if (optionPrice == null) {
      return _error('option_price is required for PUT');
    }
    if (quantity == null) {
      return _error('quantity is required for PUT');
    }

    var modifier = modify.set('option_name', optionName);
    modifier = modifier.set('option_price', (optionPrice as num).toDouble());
    modifier = modifier.set('quantity', (quantity as num).toInt());

    await DatabaseService.orderItemOptions.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.orderItemOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Order item option updated successfully',
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

    final existing = await DatabaseService.orderItemOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Order item option not found', statusCode: 404);
    }

    var modifier = modify;
    var hasUpdate = false;

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

    if (body.containsKey('quantity')) {
      final qty = (body['quantity'] as num).toInt();
      if (qty <= 0) {
        return _error('quantity must be greater than 0');
      }
      modifier = modifier.set('quantity', qty);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.orderItemOptions.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.orderItemOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Order item option partially updated',
      'data': updated != null ? DatabaseService.cleanDocument(updated) : null,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== DELETE ====================
Future<Response> _handleDelete(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];
  final orderItemId = context.request.uri.queryParameters['order_item_id'];

  try {
    await DatabaseService.startDb();

    // Clear all options for an order item
    if (orderItemId != null && orderItemId.isNotEmpty) {
      if (!ObjectId.isValidHexId(orderItemId)) {
        return _error('Invalid order item ID format', statusCode: 400);
      }

      final result = await DatabaseService.orderItemOptions
          .deleteMany({'order_item_id': ObjectId.fromHexString(orderItemId)});

      return Response.json(body: {
        'success': true,
        'message': 'All order item options removed',
        'deleted_count': result.nRemoved,
      });
    }

    // Delete single option
    if (id == null || id.isEmpty) {
      return _error('id or order_item_id is required');
    }

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid option ID format', statusCode: 400);
    }

    final existing = await DatabaseService.orderItemOptions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Order item option not found', statusCode: 404);
    }

    await DatabaseService.orderItemOptions
        .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Order item option removed',
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