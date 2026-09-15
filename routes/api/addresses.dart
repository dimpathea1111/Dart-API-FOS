import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../../services/database_service.dart';
import '../../models/address.dart';
import '../../utils/auth_middleware.dart';

Handler middleware(Handler handler) => authMiddlewareHandler(handler);

Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;
  final path = context.request.uri.pathSegments;
  final userId = getUserId(context)!;

  // GET /api/addresses
  if (path.length == 1 && method == HttpMethod.get) {
    return _getAddresses(context, userId);
  }

  // POST /api/addresses
  if (path.length == 1 && method == HttpMethod.post) {
    return _createAddress(context, userId);
  }

  // GET /api/addresses/{id}
  if (path.length == 2 && method == HttpMethod.get) {
    return _getAddress(context, userId, path[1]);
  }

  // PUT /api/addresses/{id}
  if (path.length == 2 && method == HttpMethod.put) {
    return _updateAddress(context, userId, path[1]);
  }

  // DELETE /api/addresses/{id}
  if (path.length == 2 && method == HttpMethod.delete) {
    return _deleteAddress(context, userId, path[1]);
  }

  // PATCH /api/addresses/{id}/default
  if (path.length == 3 && path[2] == 'default' && method == HttpMethod.patch) {
    return _setDefaultAddress(context, userId, path[1]);
  }

  return Response.json(
    statusCode: 404,
    body: {'success': false, 'message': 'Endpoint not found'},
  );
}

Future<Response> _getAddresses(RequestContext context, String userId) async {
  return DatabaseService.withDb(context, () async {
    final docs = await DatabaseService.addresses.find({'user_id': userId}).toList();
    final addresses = docs.map((doc) => Address.fromJson(doc).toJson()).toList();
    return Response.json(body: {
      'success': true,
      'data': addresses,
      'message': 'Addresses fetched successfully',
    });
  });
}

Future<Response> _createAddress(RequestContext context, String userId) async {
  return DatabaseService.withDb(context, () async {
    try {
      final body = await context.request.body();
      final json = jsonDecode(body) as Map<String, dynamic>;
      
      json['user_id'] = userId;
      json['created_at'] = DateTime.now().toIso8601String();
      
      await DatabaseService.addresses.insertOne(json);
      return Response.json(
        statusCode: 201,
        body: {'success': true, 'data': json, 'message': 'Address created successfully'},
      );
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid request: $e'},
      );
    }
  });
}

Future<Response> _getAddress(RequestContext context, String userId, String addressId) async {
  return DatabaseService.withDb(context, () async {
    try {
      final doc = await DatabaseService.addresses.findOne({
        '_id': ObjectId.fromHexString(addressId),
        'user_id': userId,
      });
      if (doc == null) {
        return Response.json(
          statusCode: 404,
          body: {'success': false, 'message': 'Address not found'},
        );
      }
      return Response.json(body: {
        'success': true,
        'data': Address.fromJson(doc).toJson(),
        'message': 'Address fetched successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid address ID'},
      );
    }
  });
}

Future<Response> _updateAddress(RequestContext context, String userId, String addressId) async {
  return DatabaseService.withDb(context, () async {
    try {
      final body = await context.request.body();
      final json = jsonDecode(body) as Map<String, dynamic>;
      
      final updateData = <String, dynamic>{};
      if (json.containsKey('address_line1')) updateData['address_line1'] = json['address_line1'];
      if (json.containsKey('address_line2')) updateData['address_line2'] = json['address_line2'];
      if (json.containsKey('city')) updateData['city'] = json['city'];
      if (json.containsKey('state')) updateData['state'] = json['state'];
      if (json.containsKey('zipcode')) updateData['zipcode'] = json['zipcode'];
      if (json.containsKey('country')) updateData['country'] = json['country'];
      if (json.containsKey('address_type')) updateData['address_type'] = json['address_type'];
      
      await DatabaseService.addresses.updateOne(
        {'_id': ObjectId.fromHexString(addressId), 'user_id': userId},
        {'\$set': updateData},
      );
      
      final updatedDoc = await DatabaseService.addresses.findOne({'_id': ObjectId.fromHexString(addressId)});
      return Response.json(body: {
        'success': true,
        'data': Address.fromJson(updatedDoc!).toJson(),
        'message': 'Address updated successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid request: $e'},
      );
    }
  });
}

Future<Response> _deleteAddress(RequestContext context, String userId, String addressId) async {
  return DatabaseService.withDb(context, () async {
    try {
      await DatabaseService.addresses.deleteOne({
        '_id': ObjectId.fromHexString(addressId),
        'user_id': userId,
      });
      return Response.json(body: {
        'success': true,
        'message': 'Address deleted successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid address ID'},
      );
    }
  });
}

Future<Response> _setDefaultAddress(RequestContext context, String userId, String addressId) async {
  return DatabaseService.withDb(context, () async {
    try {
      // Remove default from all addresses
      await DatabaseService.addresses.updateMany(
        {'user_id': userId},
        {'\$set': {'is_default': false}},
      );
      
      // Set new default
      await DatabaseService.addresses.updateOne(
        {'_id': ObjectId.fromHexString(addressId), 'user_id': userId},
        {'\$set': {'is_default': true}},
      );
      
      return Response.json(body: {
        'success': true,
        'message': 'Default address set successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid address ID'},
      );
    }
  });
}