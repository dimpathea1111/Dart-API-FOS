import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import '../../services/database_service.dart';

Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;

  if (method == HttpMethod.get) {
    return DatabaseService.withDb(context, () async {
      final query = context.request.uri.queryParameters;
      final filter = <String, dynamic>{};

      if (query.containsKey('user_id')) {
        filter['user_id'] = query['user_id'];
      }

      final docs = await DatabaseService.orders.find(filter).toList();
      final orders = docs.map((doc) => DatabaseService.cleanDocument(doc)).toList();
      return Response.json(
        body: {
          'data': orders,
          'message': 'Orders fetched successfully',
        },
      );
    });
  }

  // POST - បង្កើតការបញ្ជាទិញថ្មី
  if (method == HttpMethod.post) {
    return DatabaseService.withDb(context, () async {
      try {
        final body = await context.request.body();
        final json = jsonDecode(body) as Map<String, dynamic>;

        // បង្កើត order number
        final orderNumber = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
        
        // គណនា subtotal ពី items
        final items = json['items'] as List? ?? [];
        double subtotal = 0;
        for (var item in items) {
          final price = ((item['unit_price'] ?? 0) as num).toDouble();
          final qty = ((item['quantity'] ?? 1) as num).toInt();
          subtotal += price * qty;
        }

        final deliveryFee = ((json['delivery_fee'] ?? 0) as num).toDouble();
        final tax = subtotal * 0.1;
        final total = subtotal + tax + deliveryFee;

        final order = {
          'user_id': json['user_id'] ?? '',
          'restaurant_id': json['restaurant_id'] ?? '',
          'address_id': json['address_id'] ?? '',
          'order_number': orderNumber,
          'order_type': json['order_type'] ?? 'delivery',
          'subtotal': subtotal,
          'tax': tax,
          'delivery_fee': deliveryFee,
          'total_amount': total,
          'order_status': 'placed',
          'payment_status': 'pending',
          'items': items,
          'created_at': DateTime.now().toIso8601String(),
        };

        await DatabaseService.orders.insertOne(order);

        return Response.json(
          statusCode: 201,
          body: {
            'message': 'Order created successfully',
            'data': order,
          },
        );
      } catch (e) {
        return Response.json(
          statusCode: 400,
          body: {'error': 'Invalid request: $e'},
        );
      }
    });
  }

  return Response(
    statusCode: 405,
    body: 'Method not allowed',
  );
}