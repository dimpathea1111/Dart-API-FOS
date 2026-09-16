import 'package:dart_frog/dart_frog.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:bcrypt/bcrypt.dart';
import '../../models/user.dart';
import '../../services/database_service.dart';
import '../../utils/auth_middleware.dart';

Handler middleware(Handler handler) => authMiddlewareHandler(handler);

Future<Response> onRequest(RequestContext context) async {
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
}

// ==================== GET ====================
Future<Response> _handleGet(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];

  if (id != null) {
    return _getUserById(id);
  }
  return _getAllUsers(context);
}

Future<Response> _getAllUsers(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final page = int.tryParse(
          context.request.uri.queryParameters['page'] ?? '1',
        ) ??
        1;
    final limit = int.tryParse(
          context.request.uri.queryParameters['limit'] ?? '10',
        ) ??
        10;
    final skip = (page - 1) * limit;

    final allUsers = await DatabaseService.users.find().toList();

    final users = allUsers.skip(skip).take(limit).toList();
    final total = allUsers.length;

    return Response.json(body: {
      'success': true,
      'data': users.map((u) => User.fromJson(u).toJson()).toList(),
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

Future<Response> _getUserById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid user ID format', statusCode: 400);
    }

    final userMap = await DatabaseService.users
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (userMap == null) {
      return _error('User not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': User.fromJson(userMap).toJson(),
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
    final email = (body['email'] as String?)?.trim().toLowerCase();
    final phone = (body['phone'] as String?)?.trim();
    final password = body['password'] as String?;

    if (name == null || name.isEmpty) {
      return _error('Name is required');
    }
    if (email == null || email.isEmpty || !_isValidEmail(email)) {
      return _error('Valid email is required');
    }
    if (password == null || password.length < 6) {
      return _error('Password must be at least 6 characters');
    }

    final existing = await DatabaseService.users.findOne({'email': email});
    if (existing != null) {
      return _error('Email already registered', statusCode: 409);
    }

    if (phone != null && phone.isNotEmpty) {
      final existingPhone =
          await DatabaseService.users.findOne({'phone': phone});
      if (existingPhone != null) {
        return _error('Phone already registered', statusCode: 409);
      }
    }

    final passwordHash = BCrypt.hashpw(password, BCrypt.gensalt());

    final user = User(
      name: name,
      email: email,
      phone: phone,
      passwordHash: passwordHash,
    );

    final result = await DatabaseService.users.insertOne(user.toMap());

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'User created successfully',
      'data': {
        'id': result.id.toHexString(),
        'name': name,
        'email': email,
        'phone': phone,
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
      return _error('Invalid user ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.users
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('User not found', statusCode: 404);
    }

    final name = (body['name'] as String?)?.trim();
    final email = (body['email'] as String?)?.trim().toLowerCase();
    final phone = (body['phone'] as String?)?.trim();

    if (name == null || name.isEmpty) {
      return _error('Name is required for PUT');
    }
    if (email == null || email.isEmpty || !_isValidEmail(email)) {
      return _error('Valid email is required for PUT');
    }

    final emailConflict = await DatabaseService.users.findOne({
      'email': email,
      '_id': {'\$ne': ObjectId.fromHexString(id)},
    });
    if (emailConflict != null) {
      return _error('Email already used by another user', statusCode: 409);
    }

    if (phone != null && phone.isNotEmpty) {
      final phoneConflict = await DatabaseService.users.findOne({
        'phone': phone,
        '_id': {'\$ne': ObjectId.fromHexString(id)},
      });
      if (phoneConflict != null) {
        return _error('Phone already used by another user', statusCode: 409);
      }
    }

    // ⭐ បង្កើត ModifierBuilder ដោយប្រើ .set() ម្តងមួយ
    var modifier = modify.set('name', name);
    modifier = modifier.set('email', email);
    modifier = modifier.set('phone', phone);
    modifier = modifier.set('profile_pic', body['profile_pic']);
    modifier = modifier.set(
      'preferred_language',
      body['preferred_language'] ?? 'en',
    );
    modifier = modifier.set('updated_at', DateTime.now());

    final password = body['password'] as String?;
    if (password != null && password.isNotEmpty) {
      if (password.length < 6) {
        return _error('Password must be at least 6 characters');
      }
      modifier = modifier
          .set('password_hash', BCrypt.hashpw(password, BCrypt.gensalt()));
    }

    await DatabaseService.users.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updatedUser = await DatabaseService.users
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'User updated successfully',
      'data': User.fromJson(updatedUser!).toJson(),
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
      return _error('Invalid user ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.users
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('User not found', statusCode: 404);
    }

    // ⭐ ចាប់ផ្តើមជាមួយ modifier ទទេ
    var modifier = modify.set('updated_at', DateTime.now());
    var hasUpdate = false;

    if (body.containsKey('name')) {
      final name = (body['name'] as String?)?.trim();
      if (name == null || name.isEmpty) {
        return _error('Name cannot be empty');
      }
      modifier = modifier.set('name', name);
      hasUpdate = true;
    }

    if (body.containsKey('email')) {
      final email = (body['email'] as String?)?.trim().toLowerCase();
      if (email == null || email.isEmpty || !_isValidEmail(email)) {
        return _error('Valid email is required');
      }
      final conflict = await DatabaseService.users.findOne({
        'email': email,
        '_id': {'\$ne': ObjectId.fromHexString(id)},
      });
      if (conflict != null) {
        return _error('Email already used by another user', statusCode: 409);
      }
      modifier = modifier.set('email', email);
      hasUpdate = true;
    }

    if (body.containsKey('phone')) {
      final phone = (body['phone'] as String?)?.trim();
      if (phone != null && phone.isNotEmpty) {
        final conflict = await DatabaseService.users.findOne({
          'phone': phone,
          '_id': {'\$ne': ObjectId.fromHexString(id)},
        });
        if (conflict != null) {
          return _error('Phone already used by another user', statusCode: 409);
        }
      }
      modifier = modifier.set('phone', phone);
      hasUpdate = true;
    }

    if (body.containsKey('profile_pic')) {
      modifier = modifier.set('profile_pic', body['profile_pic']);
      hasUpdate = true;
    }

    if (body.containsKey('preferred_language')) {
      modifier =
          modifier.set('preferred_language', body['preferred_language']);
      hasUpdate = true;
    }

    if (body.containsKey('password')) {
      final password = body['password'] as String?;
      if (password == null || password.length < 6) {
        return _error('Password must be at least 6 characters');
      }
      modifier = modifier
          .set('password_hash', BCrypt.hashpw(password, BCrypt.gensalt()));
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.users.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updatedUser = await DatabaseService.users
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'User partially updated',
      'data': User.fromJson(updatedUser!).toJson(),
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
      return _error('Invalid user ID format', statusCode: 400);
    }

    final existing = await DatabaseService.users
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('User not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      await DatabaseService.users
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));
      return Response.json(body: {
        'success': true,
        'message': 'User deleted permanently',
      });
    } else {
      await DatabaseService.users.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify
            .set('is_active', false)
            .set('updated_at', DateTime.now()),
      );
      return Response.json(body: {
        'success': true,
        'message': 'User deactivated (soft delete)',
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

bool _isValidEmail(String email) {
  return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
}