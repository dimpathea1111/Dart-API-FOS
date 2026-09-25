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
  final paymentId = context.request.uri.queryParameters['payment_id'];
  final type = context.request.uri.queryParameters['type'];

  if (id != null && id.isNotEmpty) {
    return _getTransactionById(id);
  }
  if (userId != null && userId.isNotEmpty) {
    return _getTransactionsByUser(userId, type);
  }
  if (paymentId != null && paymentId.isNotEmpty) {
    return _getTransactionsByPayment(paymentId);
  }
  return _getAllTransactions(context);
}

Future<Response> _getAllTransactions(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allTxs = await DatabaseService.transactions.find().toList();

    allTxs.sort((a, b) {
      final aDate = a['created_at'] as DateTime? ?? DateTime.now();
      final bDate = b['created_at'] as DateTime? ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

    final txs = allTxs.skip(skip).take(limit).toList();
    final total = allTxs.length;

    final data = <Map<String, dynamic>>[];
    for (final t in txs) {
      data.add(DatabaseService.cleanDocument(t));
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

Future<Response> _getTransactionById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid transaction ID format', statusCode: 400);
    }

    final txMap = await DatabaseService.transactions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (txMap == null) {
      return _error('Transaction not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(txMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getTransactionsByUser(String userId, String? type) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(userId)) {
      return _error('Invalid user ID format', statusCode: 400);
    }

    final query = <String, dynamic>{
      'user_id': ObjectId.fromHexString(userId),
    };
    if (type != null && type.isNotEmpty) {
      query['type'] = type;
    }

    final txs = await DatabaseService.transactions.find(query).toList();

    txs.sort((a, b) {
      final aDate = a['created_at'] as DateTime? ?? DateTime.now();
      final bDate = b['created_at'] as DateTime? ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

    final data = <Map<String, dynamic>>[];
    for (final t in txs) {
      data.add(DatabaseService.cleanDocument(t));
    }

    double totalCredit = 0;
    double totalDebit = 0;
    for (final t in txs) {
      final amount = (t['amount'] as num?)?.toDouble() ?? 0;
      if (t['type'] == 'credit') {
        totalCredit += amount;
      } else {
        totalDebit += amount;
      }
    }

    return Response.json(body: {
      'success': true,
      'data': data,
      'count': data.length,
      'total_credit': totalCredit,
      'total_debit': totalDebit,
      'balance': totalCredit - totalDebit,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getTransactionsByPayment(String paymentId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(paymentId)) {
      return _error('Invalid payment ID format', statusCode: 400);
    }

    final txs = await DatabaseService.transactions
        .find(where.eq('payment_id', ObjectId.fromHexString(paymentId)))
        .toList();

    final data = <Map<String, dynamic>>[];
    for (final t in txs) {
      data.add(DatabaseService.cleanDocument(t));
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
    final userId = body['user_id'] as String?;
    final type = (body['type'] as String?)?.trim();
    final amount = body['amount'];

    if (userId == null || !ObjectId.isValidHexId(userId)) {
      return _error('Valid user_id is required');
    }
    if (type == null || type.isEmpty) {
      return _error('type is required');
    }
    if (!['credit', 'debit'].contains(type)) {
      return _error('type must be credit or debit');
    }
    if (amount == null) {
      return _error('amount is required');
    }

    final amountValue = (amount as num).toDouble();
    if (amountValue <= 0) {
      return _error('amount must be greater than 0');
    }

    final userTxs = await DatabaseService.transactions
        .find(where.eq('user_id', ObjectId.fromHexString(userId)))
        .toList();

    double totalCredit = 0;
    double totalDebit = 0;
    for (final t in userTxs) {
      final amt = (t['amount'] as num?)?.toDouble() ?? 0;
      if (t['type'] == 'credit') {
        totalCredit += amt;
      } else {
        totalDebit += amt;
      }
    }

    final currentBalance = totalCredit - totalDebit;
    final balanceAfter = type == 'credit'
        ? currentBalance + amountValue
        : currentBalance - amountValue;

    if (type == 'debit' && balanceAfter < 0) {
      return _error('Insufficient balance', statusCode: 400);
    }

    final txData = {
      'payment_id': body['payment_id'] != null &&
              ObjectId.isValidHexId(body['payment_id'] as String)
          ? ObjectId.fromHexString(body['payment_id'] as String)
          : null,
      'user_id': ObjectId.fromHexString(userId),
      'type': type,
      'amount': amountValue,
      'description': body['description'] ?? '',
      'reference_id': body['reference_id'] ?? '',
      'balance_after': balanceAfter,
      'created_at': DateTime.now(),
    };

    final result = await DatabaseService.transactions.insertOne(txData);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Transaction created successfully',
      'data': {
        'id': result.id.toHexString(),
        'user_id': userId,
        'type': type,
        'amount': amountValue,
        'balance_after': balanceAfter,
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
      return _error('Invalid transaction ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.transactions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Transaction not found', statusCode: 404);
    }

    final type = (body['type'] as String?)?.trim();
    final amount = body['amount'];

    if (type == null || type.isEmpty) {
      return _error('type is required for PUT');
    }
    if (amount == null) {
      return _error('amount is required for PUT');
    }

    var modifier = modify.set('type', type);
    modifier = modifier.set('amount', (amount as num).toDouble());
    modifier = modifier.set('description', body['description'] ?? '');
    modifier = modifier.set('reference_id', body['reference_id'] ?? '');

    await DatabaseService.transactions.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.transactions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Transaction updated successfully',
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
      return _error('Invalid transaction ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.transactions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Transaction not found', statusCode: 404);
    }

    var modifier = modify;
    var hasUpdate = false;

    if (body.containsKey('description')) {
      modifier = modifier.set('description', body['description']);
      hasUpdate = true;
    }

    if (body.containsKey('reference_id')) {
      modifier = modifier.set('reference_id', body['reference_id']);
      hasUpdate = true;
    }

    if (body.containsKey('amount')) {
      modifier = modifier.set('amount', (body['amount'] as num).toDouble());
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.transactions.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    final updated = await DatabaseService.transactions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Transaction partially updated',
      'data': updated != null ? DatabaseService.cleanDocument(updated) : null,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== DELETE ====================
Future<Response> _handleDelete(RequestContext context) async {
  final id = context.request.uri.queryParameters['id'];
  final userId = context.request.uri.queryParameters['user_id'];

  try {
    await DatabaseService.startDb();

    if (userId != null && userId.isNotEmpty) {
      if (!ObjectId.isValidHexId(userId)) {
        return _error('Invalid user ID format', statusCode: 400);
      }

      final result = await DatabaseService.transactions
          .deleteMany({'user_id': ObjectId.fromHexString(userId)});

      return Response.json(body: {
        'success': true,
        'message': 'All user transactions deleted',
        'deleted_count': result.nRemoved,
      });
    }

    if (id == null || id.isEmpty) {
      return _error('id or user_id is required');
    }

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid transaction ID format', statusCode: 400);
    }

    final existing = await DatabaseService.transactions
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Transaction not found', statusCode: 404);
    }

    await DatabaseService.transactions
        .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Transaction deleted permanently',
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