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
  final isActive = context.request.uri.queryParameters['is_active'];
  final vehicleType = context.request.uri.queryParameters['vehicle_type'];

  if (id != null && id.isNotEmpty) {
    return _getDriverById(id);
  }
  if (userId != null && userId.isNotEmpty) {
    return _getDriverByUser(userId);
  }
  return _getAllDrivers(context, isActive, vehicleType);
}

Future<Response> _getAllDrivers(
  RequestContext context,
  String? isActive,
  String? vehicleType,
) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    var allDrivers = await DatabaseService.deliveryDrivers.find().toList();

    // Filter by is_active
    if (isActive != null && isActive.isNotEmpty) {
      final activeBool = isActive.toLowerCase() == 'true';
      allDrivers =
          allDrivers.where((d) => d['is_active'] == activeBool).toList();
    }

    // Filter by vehicle_type
    if (vehicleType != null && vehicleType.isNotEmpty) {
      allDrivers = allDrivers
          .where((d) => d['vehicle_type'] == vehicleType)
          .toList();
    }

    final drivers = allDrivers.skip(skip).take(limit).toList();
    final total = allDrivers.length;

    final data = <Map<String, dynamic>>[];
    for (final d in drivers) {
      data.add(DatabaseService.cleanDocument(d));
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

Future<Response> _getDriverById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid driver ID format', statusCode: 400);
    }

    final driverMap = await DatabaseService.deliveryDrivers
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (driverMap == null) {
      return _error('Driver not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(driverMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getDriverByUser(String userId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(userId)) {
      return _error('Invalid user ID format', statusCode: 400);
    }

    final driverMap = await DatabaseService.deliveryDrivers
        .findOne(where.eq('user_id', ObjectId.fromHexString(userId)));

    if (driverMap == null) {
      return _error('Driver not found for this user', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(driverMap),
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
    final vehicleType = (body['vehicle_type'] as String?)?.trim();
    final licenseNumber = (body['license_number'] as String?)?.trim();

    // Validation
    if (userId == null || !ObjectId.isValidHexId(userId)) {
      return _error('Valid user_id is required');
    }
    if (vehicleType == null || vehicleType.isEmpty) {
      return _error('vehicle_type is required');
    }
    if (licenseNumber == null || licenseNumber.isEmpty) {
      return _error('license_number is required');
    }

    // Check if user already has a driver profile
    final existing = await DatabaseService.deliveryDrivers
        .findOne(where.eq('user_id', ObjectId.fromHexString(userId)));
    if (existing != null) {
      return _error('Driver profile already exists for this user',
          statusCode: 409);
    }

    // Check license number uniqueness
    final licenseConflict = await DatabaseService.deliveryDrivers
        .findOne(where.eq('license_number', licenseNumber));
    if (licenseConflict != null) {
      return _error('License number already registered', statusCode: 409);
    }

    final driverData = {
      'user_id': ObjectId.fromHexString(userId),
      'vehicle_type': vehicleType,
      'license_number': licenseNumber,
      'is_active': body['is_active'] ?? true,
      'latitude': (body['latitude'] as num?)?.toDouble() ?? 0.0,
      'longitude': (body['longitude'] as num?)?.toDouble() ?? 0.0,
      'rating': 0.0,
      'total_deliveries': 0,
      'earnings': 0.0,
      'created_at': DateTime.now(),
      'updated_at': DateTime.now(),
    };

    final result = await DatabaseService.deliveryDrivers.insertOne(driverData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Driver profile created successfully',
      'data': {
        'id': result.id.toHexString(),
        'user_id': userId,
        'vehicle_type': vehicleType,
        'license_number': licenseNumber,
        'is_active': driverData['is_active'],
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
      return _error('Invalid driver ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.deliveryDrivers
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Driver not found', statusCode: 404);
    }

    final vehicleType = (body['vehicle_type'] as String?)?.trim();
    final licenseNumber = (body['license_number'] as String?)?.trim();

    if (vehicleType == null || vehicleType.isEmpty) {
      return _error('vehicle_type is required for PUT');
    }
    if (licenseNumber == null || licenseNumber.isEmpty) {
      return _error('license_number is required for PUT');
    }

    // Check license conflict
    final licenseConflict = await DatabaseService.deliveryDrivers.findOne({
      'license_number': licenseNumber,
      '_id': {'\$ne': ObjectId.fromHexString(id)},
    });
    if (licenseConflict != null) {
      return _error('License number already used', statusCode: 409);
    }

    var modifier = modify.set('vehicle_type', vehicleType);
    modifier = modifier.set('license_number', licenseNumber);
    modifier = modifier.set('is_active', body['is_active'] ?? true);
    modifier = modifier.set(
      'latitude',
      (body['latitude'] as num?)?.toDouble() ?? 0.0,
    );
    modifier = modifier.set(
      'longitude',
      (body['longitude'] as num?)?.toDouble() ?? 0.0,
    );
    modifier = modifier.set('updated_at', DateTime.now());

    await DatabaseService.deliveryDrivers.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.deliveryDrivers
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Driver updated successfully',
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
      return _error('Invalid driver ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.deliveryDrivers
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Driver not found', statusCode: 404);
    }

    var modifier = modify.set('updated_at', DateTime.now());
    var hasUpdate = false;

    if (body.containsKey('vehicle_type')) {
      final v = (body['vehicle_type'] as String?)?.trim();
      if (v == null || v.isEmpty) return _error('vehicle_type cannot be empty');
      modifier = modifier.set('vehicle_type', v);
      hasUpdate = true;
    }

    if (body.containsKey('license_number')) {
      final v = (body['license_number'] as String?)?.trim();
      if (v == null || v.isEmpty) return _error('license_number cannot be empty');

      final conflict = await DatabaseService.deliveryDrivers.findOne({
        'license_number': v,
        '_id': {'\$ne': ObjectId.fromHexString(id)},
      });
      if (conflict != null) {
        return _error('License number already used', statusCode: 409);
      }
      modifier = modifier.set('license_number', v);
      hasUpdate = true;
    }

    if (body.containsKey('is_active')) {
      modifier = modifier.set('is_active', body['is_active']);
      hasUpdate = true;
    }

    if (body.containsKey('latitude')) {
      modifier = modifier.set(
        'latitude',
        (body['latitude'] as num).toDouble(),
      );
      hasUpdate = true;
    }

    if (body.containsKey('longitude')) {
      modifier = modifier.set(
        'longitude',
        (body['longitude'] as num).toDouble(),
      );
      hasUpdate = true;
    }

    if (body.containsKey('rating')) {
      modifier = modifier.set('rating', (body['rating'] as num).toDouble());
      hasUpdate = true;
    }

    if (body.containsKey('total_deliveries')) {
      modifier = modifier.set('total_deliveries', body['total_deliveries']);
      hasUpdate = true;
    }

    if (body.containsKey('earnings')) {
      modifier = modifier.set('earnings', (body['earnings'] as num).toDouble());
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.deliveryDrivers.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.deliveryDrivers
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Driver partially updated',
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
      return _error('Invalid driver ID format', statusCode: 400);
    }

    final existing = await DatabaseService.deliveryDrivers
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Driver not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      await DatabaseService.deliveryDrivers
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));
      return Response.json(body: {
        'success': true,
        'message': 'Driver deleted permanently',
      });
    } else {
      await DatabaseService.deliveryDrivers.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify.set('is_active', false).set('updated_at', DateTime.now()),
      );
      return Response.json(body: {
        'success': true,
        'message': 'Driver deactivated (soft delete)',
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