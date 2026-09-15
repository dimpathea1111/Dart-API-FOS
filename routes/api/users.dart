import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import 'package:crypto/crypto.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../../services/database_service.dart';
import '../../models/user.dart';
import '../../utils/auth_middleware.dart';

Handler middleware(Handler handler) => authMiddlewareHandler(handler);


Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;
  final path = context.request.uri.pathSegments;

  // GET /api/users
  if (path.length == 1 && method == HttpMethod.get) {
    return _getAllUsers(context);
  }

  // GET /api/users/{id}
  if (path.length == 2 && method == HttpMethod.get) {
    return _getUser(context, path[1]);
  }

  // PUT /api/users/{id}
  if (path.length == 2 && method == HttpMethod.put) {
    return _updateUser(context, path[1]);
  }

  // DELETE /api/users/{id}
  if (path.length == 2 && method == HttpMethod.delete) {
    return _deleteUser(context, path[1]);
  }

  return Response.json(
    statusCode: 404,
    body: {'success': false, 'message': 'Endpoint not found'},
  );
}

Future<Response> _getAllUsers(RequestContext context) async {
  return DatabaseService.withDb(context, () async {
    final docs = await DatabaseService.users.find().toList();
    final users = docs.map((doc) => User.fromJson(doc).toJson()).toList();
    return Response.json(body: {
      'success': true,
      'data': users,
      'total': users.length,
      'message': 'Users fetched successfully',
    });
  });
}

Future<Response> _getUser(RequestContext context, String userId) async {
  final currentUserId = getUserId(context);
  if (currentUserId != userId) {
    return Response.json(
      statusCode: 403,
      body: {'success': false, 'message': 'You can only view your own profile'},
    );
  }

  return DatabaseService.withDb(context, () async {
    try {
      final doc = await DatabaseService.users.findOne({'_id': ObjectId.fromHexString(userId)});
      if (doc == null) {
        return Response.json(
          statusCode: 404,
          body: {'success': false, 'message': 'User not found'},
        );
      }
      return Response.json(body: {
        'success': true,
        'data': User.fromJson(doc).toJson(),
        'message': 'User fetched successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid user ID'},
      );
    }
  });
}

Future<Response> _updateUser(RequestContext context, String userId) async {
  final currentUserId = getUserId(context);
  if (currentUserId != userId) {
    return Response.json(
      statusCode: 403,
      body: {'success': false, 'message': 'You can only update your own profile'},
    );
  }

  return DatabaseService.withDb(context, () async {
    try {
      final body = await context.request.body();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final updateData = <String, dynamic>{};
      if (json.containsKey('name')) updateData['name'] = json['name'];
      if (json.containsKey('phone')) updateData['phone'] = json['phone'];
      if (json.containsKey('profile_pic')) updateData['profile_pic'] = json['profile_pic'];
      if (json.containsKey('preferred_language')) updateData['preferred_language'] = json['preferred_language'];
      updateData['updated_at'] = DateTime.now().toIso8601String();

      await DatabaseService.users.updateOne(
        {'_id': ObjectId.fromHexString(userId)},
        {'\$set': updateData},
      );

      final updatedDoc = await DatabaseService.users.findOne({'_id': ObjectId.fromHexString(userId)});
      return Response.json(body: {
        'success': true,
        'data': User.fromJson(updatedDoc!).toJson(),
        'message': 'User updated successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid request: $e'},
      );
    }
  });
}

Future<Response> _deleteUser(RequestContext context, String userId) async {
  final currentUserId = getUserId(context);
  if (currentUserId != userId) {
    return Response.json(
      statusCode: 403,
      body: {'success': false, 'message': 'You can only delete your own profile'},
    );
  }

  return DatabaseService.withDb(context, () async {
    try {
      await DatabaseService.users.deleteOne({'_id': ObjectId.fromHexString(userId)});
      return Response.json(body: {
        'success': true,
        'message': 'User deleted successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid user ID'},
      );
    }
  });
}