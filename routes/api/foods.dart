import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import '../../services/database_service.dart';

Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;

  // GET - ទាញយកមុខម្ហូប
  if (method == HttpMethod.get) {
    return DatabaseService.withDb(context, () async {
      final query = context.request.uri.queryParameters;
      final filter = <String, dynamic>{};

      // ត្រងតាម restaurant_id
      if (query.containsKey('restaurant_id')) {
        filter['restaurant_id'] = query['restaurant_id'];
      }

      final docs = await DatabaseService.foods.find(filter).toList();
      final foods = docs.map((doc) => DatabaseService.cleanDocument(doc)).toList();
      return Response.json(
        body: {
          'data': foods,
          'message': 'Foods fetched successfully',
        },
      );
    });
  }

  // POST - បង្កើតមុខម្ហូបថ្មី
  if (method == HttpMethod.post) {
    return DatabaseService.withDb(context, () async {
      try {
        final body = await context.request.body();
        final json = jsonDecode(body) as Map<String, dynamic>;

        json['created_at'] = DateTime.now().toIso8601String();
        json['is_available'] = json['is_available'] ?? true;

        await DatabaseService.foods.insertOne(json);

        return Response.json(
          statusCode: 201,
          body: {
            'message': 'Food created successfully',
            'data': json,
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