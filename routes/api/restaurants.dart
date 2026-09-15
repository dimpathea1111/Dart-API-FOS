import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../../services/database_service.dart';
import '../../models/order.dart';
import '../../utils/auth_middleware.dart';

Handler middleware(Handler handler) => authMiddlewareHandler(handler);Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;
  final path = context.request.uri.pathSegments;

  // GET /api/orders
  if (path.length == 1 && method == HttpMethod.get) {
    return _getAllOrders(context);
  }

  // POST /api/orders
  if (path.length == 1 && method == HttpMethod.post) {
    return _createOrder(context);
  }

  // GET /api/orders/{id}
  if (path.length == 2 && method == HttpMethod.get) {
    return _getOrder(context, path[1]);
  }

  // PUT /api/orders/{id}
  if (path.length == 2 && method == HttpMethod.put) {
    return _updateOrder(context, path[1]);
  }

  // DELETE /api/orders/{id}
  if (path.length == 2 && method == HttpMethod.delete) {
    return _deleteOrder(context, path[1]);
  }

  // GET /api/orders/user/{userId}
  if (path.length == 3 && path[1] == 'user' && method == HttpMethod.get) {
    return _getOrdersByUser(context, path[2]);
  }

  // GET /api/orders/restaurant/{restaurantId}
  if (path.length == 3 && path[1] == 'restaurant' && method == HttpMethod.get) {
    return _getOrdersByRestaurant(context, path[2]);
  }

  // GET /api/orders/status/{status}
  if (path.length == 3 && path[1] == 'status' && method == HttpMethod.get) {
    return _getOrdersByStatus(context, path[2]);
  }

  // PATCH /api/orders/{id}/status
  if (path.length == 3 && path[2] == 'status' && method == HttpMethod.patch) {
    return _updateOrderStatus(context, path[1]);
  }

  // PATCH /api/orders/{id}/cancel
  if (path.length == 3 && path[2] == 'cancel' && method == HttpMethod.patch) {
    return _cancelOrder(context, path[1]);
  }

  // GET /api/orders/track/{orderNumber}
  if (path.length == 3 && path[1] == 'track' && method == HttpMethod.get) {
    return _trackOrder(context, path[2]);
  }

  return Response.json(
    statusCode: 404,
    body: {'success': false, 'message': 'Endpoint not found'},
  );
}

Future<Response> _getAllOrders(RequestContext context) async {
  return DatabaseService.withDb(context, () async {
    final query = context.request.uri.queryParameters;
    final filter = <String, dynamic>{};
    
    if (query.containsKey('user_id')) filter['user_id'] = query['user_id'];
    if (query.containsKey('restaurant_id')) filter['restaurant_id'] = query['restaurant_id'];
    if (query.containsKey('order_status')) filter['order_status'] = query['order_status'];
    
    final docs = await DatabaseService.orders.find(filter).toList();
    final orders = docs.map((doc) => Order.fromJson(doc).toJson()).toList();
    return Response.json(body: {
      'success': true,
      'data': orders,
      'total': orders.length,
      'message': 'Orders fetched successfully',
    });
  });
}

Future<Response> _getOrder(RequestContext context, String orderId) async {
  return DatabaseService.withDb(context, () async {
    try {
      final doc = await DatabaseService.orders.findOne({'_id': ObjectId.fromHexString(orderId)});
      if (doc == null) {
        return Response.json(
          statusCode: 404,
          body: {'success': false, 'message': 'Order not found'},
        );
      }
      return Response.json(body: {
        'success': true,
        'data': Order.fromJson(doc).toJson(),
        'message': 'Order fetched successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid order ID'},
      );
    }
  });
}

Future<Response> _createOrder(RequestContext context) async {
  return DatabaseService.withDb(context, () async {
    try {
      final body = await context.request.body();
      final json = jsonDecode(body) as Map<String, dynamic>;
      
      // Generate order number
      final orderNumber = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
      json['order_number'] = orderNumber;
      json['created_at'] = DateTime.now().toIso8601String();
      json['updated_at'] = DateTime.now().toIso8601String();
      json['order_status'] = 'placed';
      json['payment_status'] = 'pending';
      
      await DatabaseService.orders.insertOne(json);
      return Response.json(
        statusCode: 201,
        body: {'success': true, 'data': json, 'message': 'Order created successfully'},
      );
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid request: $e'},
      );
    }
  });
}

Future<Response> _updateOrder(RequestContext context, String orderId) async {
  return DatabaseService.withDb(context, () async {
    try {
      final body = await context.request.body();
      final json = jsonDecode(body) as Map<String, dynamic>;
      
      json['updated_at'] = DateTime.now().toIso8601String();
      
      await DatabaseService.orders.updateOne(
        {'_id': ObjectId.fromHexString(orderId)},
        {'\$set': json},
      );
      
      final updatedDoc = await DatabaseService.orders.findOne({'_id': ObjectId.fromHexString(orderId)});
      return Response.json(body: {
        'success': true,
        'data': Order.fromJson(updatedDoc!).toJson(),
        'message': 'Order updated successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid request: $e'},
      );
    }
  });
}

Future<Response> _deleteOrder(RequestContext context, String orderId) async {
  return DatabaseService.withDb(context, () async {
    try {
      await DatabaseService.orders.deleteOne({'_id': ObjectId.fromHexString(orderId)});
      return Response.json(body: {
        'success': true,
        'message': 'Order deleted successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid order ID'},
      );
    }
  });
}

Future<Response> _getOrdersByUser(RequestContext context, String userId) async {
  return DatabaseService.withDb(context, () async {
    final docs = await DatabaseService.orders.find({'user_id': userId}).toList();
    final orders = docs.map((doc) => Order.fromJson(doc).toJson()).toList();
    return Response.json(body: {
      'success': true,
      'data': orders,
      'message': 'Orders fetched successfully',
    });
  });
}

Future<Response> _getOrdersByRestaurant(RequestContext context, String restaurantId) async {
  return DatabaseService.withDb(context, () async {
    final docs = await DatabaseService.orders.find({'restaurant_id': restaurantId}).toList();
    final orders = docs.map((doc) => Order.fromJson(doc).toJson()).toList();
    return Response.json(body: {
      'success': true,
      'data': orders,
      'message': 'Orders fetched successfully',
    });
  });
}

Future<Response> _getOrdersByStatus(RequestContext context, String status) async {
  return DatabaseService.withDb(context, () async {
    final docs = await DatabaseService.orders.find({'order_status': status}).toList();
    final orders = docs.map((doc) => Order.fromJson(doc).toJson()).toList();
    return Response.json(body: {
      'success': true,
      'data': orders,
      'message': 'Orders fetched successfully',
    });
  });
}

Future<Response> _updateOrderStatus(RequestContext context, String orderId) async {
  return DatabaseService.withDb(context, () async {
    try {
      final body = await context.request.body();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final status = json['status']?.toString();
      
      if (status == null || status.isEmpty) {
        return Response.json(
          statusCode: 400,
          body: {'success': false, 'message': 'Status is required'},
        );
      }
      
      await DatabaseService.orders.updateOne(
        {'_id': ObjectId.fromHexString(orderId)},
        {
          '\$set': {
            'order_status': status,
            'updated_at': DateTime.now().toIso8601String(),
          }
        },
      );
      
      return Response.json(body: {
        'success': true,
        'message': 'Order status updated successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid request: $e'},
      );
    }
  });
}

Future<Response> _cancelOrder(RequestContext context, String orderId) async {
  return DatabaseService.withDb(context, () async {
    try {
      await DatabaseService.orders.updateOne(
        {'_id': ObjectId.fromHexString(orderId)},
        {
          '\$set': {
            'order_status': 'cancelled',
            'updated_at': DateTime.now().toIso8601String(),
          }
        },
      );
      
      return Response.json(body: {
        'success': true,
        'message': 'Order cancelled successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid order ID'},
      );
    }
  });
}

Future<Response> _trackOrder(RequestContext context, String orderNumber) async {
  return DatabaseService.withDb(context, () async {
    final doc = await DatabaseService.orders.findOne({'order_number': orderNumber});
    if (doc == null) {
      return Response.json(
        statusCode: 404,
        body: {'success': false, 'message': 'Order not found'},
      );
    }
    return Response.json(body: {
      'success': true,
      'data': Order.fromJson(doc).toJson(),
      'message': 'Order tracked successfully',
    });
  });
}