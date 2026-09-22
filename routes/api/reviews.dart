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
  final restaurantId = context.request.uri.queryParameters['restaurant_id'];
  final userId = context.request.uri.queryParameters['user_id'];
  final status = context.request.uri.queryParameters['status'];

  if (id != null && id.isNotEmpty) {
    return _getReviewById(id);
  }
  if (restaurantId != null && restaurantId.isNotEmpty) {
    return _getReviewsByRestaurant(restaurantId, status);
  }
  if (userId != null && userId.isNotEmpty) {
    return _getReviewsByUser(userId);
  }
  return _getAllReviews(context);
}

Future<Response> _getAllReviews(RequestContext context) async {
  try {
    await DatabaseService.startDb();

    final pageStr = context.request.uri.queryParameters['page'] ?? '1';
    final limitStr = context.request.uri.queryParameters['limit'] ?? '10';
    final page = int.tryParse(pageStr) ?? 1;
    final limit = int.tryParse(limitStr) ?? 10;
    final skip = (page - 1) * limit;

    final allReviews = await DatabaseService.reviews.find().toList();
    final reviews = allReviews.skip(skip).take(limit).toList();
    final total = allReviews.length;

    final data = <Map<String, dynamic>>[];
    for (final r in reviews) {
      data.add(DatabaseService.cleanDocument(r));
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

Future<Response> _getReviewById(String id) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(id)) {
      return _error('Invalid review ID format', statusCode: 400);
    }

    final reviewMap = await DatabaseService.reviews
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    if (reviewMap == null) {
      return _error('Review not found', statusCode: 404);
    }

    return Response.json(body: {
      'success': true,
      'data': DatabaseService.cleanDocument(reviewMap),
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getReviewsByRestaurant(
  String restaurantId,
  String? status,
) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(restaurantId)) {
      return _error('Invalid restaurant ID format', statusCode: 400);
    }

    final query = <String, dynamic>{
      'restaurant_id': ObjectId.fromHexString(restaurantId),
    };
    if (status != null && status.isNotEmpty) {
      query['status'] = status;
    }

    final reviews = await DatabaseService.reviews.find(query).toList();

    final data = <Map<String, dynamic>>[];
    for (final r in reviews) {
      data.add(DatabaseService.cleanDocument(r));
    }

    // គណនា average rating
    double avgRating = 0;
    if (data.isNotEmpty) {
      final sum = data.fold<double>(
        0,
        (acc, r) => acc + ((r['rating'] as num?)?.toDouble() ?? 0),
      );
      avgRating = sum / data.length;
    }

    return Response.json(body: {
      'success': true,
      'data': data,
      'count': data.length,
      'average_rating': avgRating,
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

Future<Response> _getReviewsByUser(String userId) async {
  try {
    await DatabaseService.startDb();

    if (!ObjectId.isValidHexId(userId)) {
      return _error('Invalid user ID format', statusCode: 400);
    }

    final reviews = await DatabaseService.reviews
        .find(where.eq('user_id', ObjectId.fromHexString(userId)))
        .toList();

    final data = <Map<String, dynamic>>[];
    for (final r in reviews) {
      data.add(DatabaseService.cleanDocument(r));
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
    final restaurantId = body['restaurant_id'] as String?;
    final orderId = body['order_id'] as String?;
    final rating = body['rating'];

    // Validation
    if (userId == null || !ObjectId.isValidHexId(userId)) {
      return _error('Valid user_id is required');
    }
    if (restaurantId == null || !ObjectId.isValidHexId(restaurantId)) {
      return _error('Valid restaurant_id is required');
    }
    if (rating == null) {
      return _error('rating is required');
    }

    final ratingValue = (rating as num).toDouble();
    if (ratingValue < 1 || ratingValue > 5) {
      return _error('rating must be between 1 and 5');
    }

    // Check if user already reviewed this order
    if (orderId != null && orderId.isNotEmpty) {
      if (!ObjectId.isValidHexId(orderId)) {
        return _error('Invalid order ID format');
      }
      final existing = await DatabaseService.reviews
          .findOne(where.eq('order_id', ObjectId.fromHexString(orderId)));
      if (existing != null) {
        return _error('Review already exists for this order', statusCode: 409);
      }
    }

    final reviewData = {
      'user_id': ObjectId.fromHexString(userId),
      'restaurant_id': ObjectId.fromHexString(restaurantId),
      'order_id': orderId != null && orderId.isNotEmpty
          ? ObjectId.fromHexString(orderId)
          : null,
      'rating': ratingValue,
      'review_text': body['review_text'] ?? '',
      'images': body['images'] ?? [],
      'is_verified_purchase': orderId != null && orderId.isNotEmpty,
      'status': body['status'] ?? 'pending',
      'created_at': DateTime.now(),
      'updated_at': DateTime.now(),
    };

    final result = await DatabaseService.reviews.insertOne(reviewData);

    // Update restaurant rating
    await _updateRestaurantRating(restaurantId);

    return Response.json(statusCode: 201, body: {
      'success': true,
      'message': 'Review created successfully',
      'data': {
        'id': result.id.toHexString(),
        'user_id': userId,
        'restaurant_id': restaurantId,
        'rating': ratingValue,
        'review_text': reviewData['review_text'],
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
      return _error('Invalid review ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.reviews
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Review not found', statusCode: 404);
    }

    final rating = body['rating'];
    if (rating == null) {
      return _error('rating is required for PUT');
    }

    final ratingValue = (rating as num).toDouble();
    if (ratingValue < 1 || ratingValue > 5) {
      return _error('rating must be between 1 and 5');
    }

    final modifier = modify.set('rating', ratingValue);
    final modifier2 = modifier.set('review_text', body['review_text'] ?? '');
    final modifier3 = modifier2.set('images', body['images'] ?? []);
    final modifier4 = modifier3.set('status', body['status'] ?? 'pending');
    final modifier5 = modifier4.set('updated_at', DateTime.now());

    await DatabaseService.reviews.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier5,
    );

    // Update restaurant rating
    final restaurantId = existing['restaurant_id'] as ObjectId;
    await _updateRestaurantRating(restaurantId.toHexString());

    final updated = await DatabaseService.reviews
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Review updated successfully',
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
      return _error('Invalid review ID format', statusCode: 400);
    }

    final body = await context.request.json() as Map<String, dynamic>;

    final existing = await DatabaseService.reviews
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Review not found', statusCode: 404);
    }

    var modifier = modify.set('updated_at', DateTime.now());
    var hasUpdate = false;

    if (body.containsKey('rating')) {
      final ratingValue = (body['rating'] as num).toDouble();
      if (ratingValue < 1 || ratingValue > 5) {
        return _error('rating must be between 1 and 5');
      }
      modifier = modifier.set('rating', ratingValue);
      hasUpdate = true;
    }

    if (body.containsKey('review_text')) {
      modifier = modifier.set('review_text', body['review_text'] ?? '');
      hasUpdate = true;
    }

    if (body.containsKey('images')) {
      modifier = modifier.set('images', body['images']);
      hasUpdate = true;
    }

    if (body.containsKey('status')) {
      modifier = modifier.set('status', body['status']);
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return _error('No fields to update', statusCode: 400);
    }

    await DatabaseService.reviews.updateOne(
      where.eq('_id', ObjectId.fromHexString(id)),
      modifier,
    );

    // Update restaurant rating
    final restaurantId = existing['restaurant_id'] as ObjectId;
    await _updateRestaurantRating(restaurantId.toHexString());

    final updated = await DatabaseService.reviews
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));

    return Response.json(body: {
      'success': true,
      'message': 'Review partially updated',
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
      return _error('Invalid review ID format', statusCode: 400);
    }

    final existing = await DatabaseService.reviews
        .findOne(where.eq('_id', ObjectId.fromHexString(id)));
    if (existing == null) {
      return _error('Review not found', statusCode: 404);
    }

    final hardDelete = context.request.uri.queryParameters['hard'] == 'true';

    if (hardDelete) {
      await DatabaseService.reviews
          .deleteOne(where.eq('_id', ObjectId.fromHexString(id)));
    } else {
      await DatabaseService.reviews.updateOne(
        where.eq('_id', ObjectId.fromHexString(id)),
        modify
            .set('status', 'rejected')
            .set('updated_at', DateTime.now()),
      );
    }

    // Update restaurant rating
    final restaurantId = existing['restaurant_id'] as ObjectId;
    await _updateRestaurantRating(restaurantId.toHexString());

    return Response.json(body: {
      'success': true,
      'message': hardDelete
          ? 'Review deleted permanently'
          : 'Review rejected (soft delete)',
    });
  } catch (e) {
    return _error('Server error: $e', statusCode: 500);
  }
}

// ==================== HELPERS ====================
Future<void> _updateRestaurantRating(String restaurantId) async {
  try {
    if (!ObjectId.isValidHexId(restaurantId)) return;

    final reviews = await DatabaseService.reviews
        .find(where.eq(
          'restaurant_id',
          ObjectId.fromHexString(restaurantId),
        ))
        .toList();

    // Filter approved reviews
    final approved = reviews
        .where((r) => r['status'] == 'approved')
        .toList();

    if (approved.isEmpty) {
      await DatabaseService.restaurants.updateOne(
        where.eq('_id', ObjectId.fromHexString(restaurantId)),
        modify.set('rating', 0.0).set('total_ratings', 0),
      );
      return;
    }

    final sum = approved.fold<double>(
      0,
      (acc, r) => acc + ((r['rating'] as num?)?.toDouble() ?? 0),
    );
    final avgRating = sum / approved.length;

    await DatabaseService.restaurants.updateOne(
      where.eq('_id', ObjectId.fromHexString(restaurantId)),
      modify
          .set('rating', avgRating)
          .set('total_ratings', approved.length)
          .set('updated_at', DateTime.now()),
    );
  } catch (e) {
    print('Error updating restaurant rating: $e');
  }
}

Response _error(String message, {int statusCode = 400}) {
  return Response.json(
    statusCode: statusCode,
    body: {'success': false, 'message': message},
  );
}