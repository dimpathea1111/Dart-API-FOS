import 'package:dart_frog/dart_frog.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../../services/database_service.dart';
import '../../utils/auth_middleware.dart';

Handler middleware(Handler handler) => authMiddlewareHandler(handler);

Future<Response> onRequest(RequestContext context) async {
  try {
    final method = context.request.method.value;  // ← Line 13 - គ្មាន !

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

Future<Response> _handleGet(RequestContext context) async {
  try {
    final id = context.request.uri.queryParameters['id'];
    final userId = context.request.uri.queryParameters['user_id'];

    if (id != null && id.isNotEmpty) {
      return _getAddressById(id);
    }
    if (userId != null && userId.isNotEmpty) {
      return _getAddressesByUser(userId);
    }
    return _getAllAddresses(context);
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getAllAddresses(RequestContext context) async {
  try {
    print('🔍 DEBUG: Starting _getAllAddresses');
    await DatabaseService.startDb();
    print('🔍 DEBUG: Database connected');

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    print('🔍 DEBUG: Fetching addresses...');
    final allAddresses = await DatabaseService.addresses.find().toList();
    print('🔍 DEBUG: Found ${allAddresses.length} addresses');

    final addresses = allAddresses.skip(skip).take(limit).toList();
    final total = allAddresses.length;

    print('🔍 DEBUG: Processing documents...');
    final data = <Map<String, dynamic>>[];
    for (final a in addresses) {
      try {
        data.add(DatabaseService.cleanDocument(a));
      } catch (e) {
        print('🔍 DEBUG: Error cleaning document: $e');
        data.add({'error': 'Failed to parse document', 'raw': a.toString()});
      }
    }

    print('🔍 DEBUG: Returning response');
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
  } catch (e, stackTrace) {
    print('❌ ERROR in _getAllAddresses: $e');
    print('❌ STACK: $stackTrace');
    return _error('Server error: $e', statusCode: 500);
  }
}
Future<Response> _getAddressById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid address ID format', statusCode: 400);
    }

    final addressMap = await DatabaseService.addresses
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (addressMap == null) {
      return _error('Address not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(addressMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getAddressesByUser(String userId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(userId)) {
      return _error('Invalid user ID format', statusCode: 400);
    }

    final addresses = await DatabaseService.addresses
        .find(where.eq('user_id', ObjectId.fromHexString(userId)))
        .toList();

    return Response.json(body: {
      'success': true,
      'data': addresses.map((a) => DatabaseService.cleanDocument(a)).toList(),
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
    final addressLine1 = (body['address_line1'] as String?)?.trim();
    final city = (body['city'] as String?)?.trim();
    final state = (body['state'] as String?)?.trim();
    final zipcode = (body['zipcode'] as String?)?.trim();

    if (userId == null || userId.isEmpty) {
      return _error('user_id is required');
    }
    if (!ObjectId.isValidHexId(userId)) {
      return _error('Invalid user ID format');
    }
    if (addressLine1 == null || addressLine1.isEmpty) {
      return _error('address_line1 is required');
    }
    if (city == null || city.isEmpty) {
      return _error('city is required');
    }
    if (state == null || state.isEmpty) {
      return _error('state is required');
    }
    if (zipcode == null || zipcode.isEmpty) {
      return _error('zipcode is required');
    }

    final isDefault = body['is_default'] == true;
    if (isDefault) {
      await DatabaseService.addresses.updateMany(
        {'user_id': ObjectId.fromHexString(userId), 'is_default': true},
        modify.set('is_default', false),
      );
    }

    final addressData = {
      'user_id': ObjectId.fromHexString(userId),
      'restaurant_id': body['restaurant_id'] != null
          ? ObjectId.fromHexString(body['restaurant_id'] as String)
          : null,
      'address_line1': addressLine1,
      'address_line2': body['address_line2'] ?? '',
      'city': city,
      'state': state,
      'zipcode': zipcode,
      'country': body['country'] ?? 'Cambodia',
      'latitude': body['latitude'],
      'longitude': body['longitude'],
      'address_type': body['address_type'] ?? 'home',
      'is_default': isDefault,
      'created_at': DateTime.now(),
    };

    final result = await DatabaseService.addresses.insertOne(addressData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Address created successfully',
      'data': {
        'id': result.id.toHexString(),
        'user_id': userId,
        'address_line1': addressLine1,
        'city': city,
        'state': state,
        'zipcode': zipcode,
        'country': addressData['country'],
        'address_type': addressData['address_type'],
        'is_default': isDefault,
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
      return _error('Invalid address ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.addresses
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Address not found', statusCode: 404);
    }

    final addressLine1 = (body['address_line1'] as String?)?.trim();
    final city = (body['city'] as String?)?.trim();
    final state = (body['state'] as String?)?.trim();
    final zipcode = (body['zipcode'] as String?)?.trim();

    if (addressLine1 == null || addressLine1.isEmpty) {
      return _error('address_line1 is required for PUT');
    }
    if (city == null || city.isEmpty) {
      return _error('city is required for PUT');
    }
    if (state == null || state.isEmpty) {
      return _error('state is required for PUT');
    }
    if (zipcode == null || zipcode.isEmpty) {
      return _error('zipcode is required for PUT');
    }

    var modifier = modify.set('address_line1', addressLine1);
    modifier = modifier.set('address_line2', body['address_line2'] ?? '');
    modifier = modifier.set('city', city);
    modifier = modifier.set('state', state);
    modifier = modifier.set('zipcode', zipcode);
    modifier = modifier.set('country', body['country'] ?? 'Cambodia');
    modifier = modifier.set('latitude', body['latitude']);
    modifier = modifier.set('longitude', body['longitude']);
    modifier = modifier.set('address_type', body['address_type'] ?? 'home');
    modifier = modifier.set('is_default', body['is_default'] ?? false);
    modifier = modifier.set('updated_at', DateTime.now());

    await DatabaseService.addresses.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updatedAddress = await DatabaseService.addresses
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Address updated successfully',
      'data': updatedAddress != null
          ? DatabaseService.cleanDocument(updatedAddress)
          : null,
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
      return _error('Invalid address ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.addresses
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Address not found', statusCode: 404);
    }

    var modifier = modify.set('updated_at', DateTime.now());
    var hasUpdate = false;

    if (body.containsKey('address_line1')) {
      final v = (body['address_line1'] as String?)?.trim();
      if (v == null || v.isEmpty) return _error('address_line1 cannot be empty');
      modifier = modifier.set('address_line1', v);
      hasUpdate = true;
    }

    if (body.containsKey('address_line2')) {
      modifier = modifier.set('address_line2', body['address_line2'] ?? '');
      hasUpdate = true;
    }

    if (body.containsKey('city')) {
      final v = (body['city'] as String?)?.trim();
      if (v == null || v.isEmpty) return _error('city cannot be empty');
      modifier = modifier.set('city', v);
      hasUpdate = true;
    }

    if (body.containsKey('state')) {
      final v = (body['state'] as String?)?.trim();
      if (v == null || v.isEmpty) return _error('state cannot be empty');
      modifier = modifier.set('state', v);
      hasUpdate = true;
    }

    if (body.containsKey('zipcode')) {
      final v = (body['zipcode'] as String?)?.trim();
      if (v == null || v.isEmpty) return _error('zipcode cannot be empty');
      modifier = modifier.set('zipcode', v);
      hasUpdate = true;
    }

    if (body.containsKey('country')) {
      modifier = modifier.set('country', body['country']);
      hasUpdate = true;
    }

    if (body.containsKey('address_type')) {
      modifier = modifier.set('address_type', body['address_type']);
      hasUpdate = true;
    }

    if (body.containsKey('is_default')) {
      modifier = modifier.set('is_default', body['is_default']);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.addresses.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updatedAddress = await DatabaseService.addresses
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Address partially updated',
      'data': updatedAddress != null
          ? DatabaseService.cleanDocument(updatedAddress)
          : null,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _handleDelete(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];

  if (id == null || id.isEmpty) {
    return _error('id is required for DELETE', statusCode: 400);
  }

  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid address ID format', statusCode: 400);
    }

    final existing = await DatabaseService.addresses
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Address not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      await DatabaseService.addresses
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));
      return Response.json(body: {
        'success': true,
        'message': 'Address deleted permanently',
      });
    } else {
      await DatabaseService.addresses.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify.set('is_active', false).set('updated_at', DateTime.now()),
      );
      return Response.json(body: {
        'success': true,
        'message': 'Address deactivated (soft delete)',
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