import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../../services/database_service.dart';
import '../../models/review.dart';
import '../../utils/auth_middleware.dart';

Handler middleware(Handler handler) => authMiddlewareHandler(handler);Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;
  final path = context.request.uri.pathSegments;

  // GET /api/reviews
  if (path.length == 1 && method == HttpMethod.get) {
    return _getAllReviews(context);
  }

  // POST /api/reviews
  if (path.length == 1 && method == HttpMethod.post) {
    return _createReview(context);
  }

  // GET /api/reviews/{id}
  if (path.length == 2 && method == HttpMethod.get) {
    return _getReview(context, path[1]);
  }

  // PUT /api/reviews/{id}
  if (path.length == 2 && method == HttpMethod.put) {
    return _updateReview(context, path[1]);
  }

  // DELETE /api/reviews/{id}
  if (path.length == 2 && method == HttpMethod.delete) {
    return _deleteReview(context, path[1]);
  }

  // GET /api/reviews/restaurant/{restaurantId}
  if (path.length == 3 && path[1] == 'restaurant' && method == HttpMethod.get) {
    return _getReviewsByRestaurant(context, path[2]);
  }

  // GET /api/reviews/user/{userId}
  if (path.length == 3 && path[1] == 'user' && method == HttpMethod.get) {
    return _getReviewsByUser(context, path[2]);
  }

  // GET /api/reviews/restaurant/{restaurantId}/summary
  if (path.length == 4 && path[1] == 'restaurant' && path[3] == 'summary' && method == HttpMethod.get) {
    return _getReviewSummary(context, path[2]);
  }

  return Response.json(
    statusCode: 404,
    body: {'success': false, 'message': 'Endpoint not found'},
  );
}

Future<Response> _getAllReviews(RequestContext context) async {
  return DatabaseService.withDb(context, () async {
    final docs = await DatabaseService.reviews.find().toList();
    final reviews = docs.map((doc) => Review.fromJson(doc).toJson()).toList();
    return Response.json(body: {
      'success': true,
      'data': reviews,
      'total': reviews.length,
      'message': 'Reviews fetched successfully',
    });
  });
}

Future<Response> _getReview(RequestContext context, String reviewId) async {
  return DatabaseService.withDb(context, () async {
    try {
      final doc = await DatabaseService.reviews.findOne({'_id': ObjectId.fromHexString(reviewId)});
      if (doc == null) {
        return Response.json(
          statusCode: 404,
          body: {'success': false, 'message': 'Review not found'},
        );
      }
      return Response.json(body: {
        'success': true,
        'data': Review.fromJson(doc).toJson(),
        'message': 'Review fetched successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid review ID'},
      );
    }
  });
}

Future<Response> _createReview(RequestContext context) async {
  return DatabaseService.withDb(context, () async {
    try {
      final body = await context.request.body();
      final json = jsonDecode(body) as Map<String, dynamic>;
      
      json['created_at'] = DateTime.now().toIso8601String();
      json['updated_at'] = DateTime.now().toIso8601String();
      
      await DatabaseService.reviews.insertOne(json);
      
      // Update restaurant rating
      await _updateRestaurantRating(json['restaurant_id'] as String);
      
      return Response.json(
        statusCode: 201,
        body: {'success': true, 'data': json, 'message': 'Review created successfully'},
      );
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid request: $e'},
      );
    }
  });
}

Future<Response> _updateReview(RequestContext context, String reviewId) async {
  return DatabaseService.withDb(context, () async {
    try {
      final body = await context.request.body();
      final json = jsonDecode(body) as Map<String, dynamic>;
      
      json['updated_at'] = DateTime.now().toIso8601String();
      
      await DatabaseService.reviews.updateOne(
        {'_id': ObjectId.fromHexString(reviewId)},
        {'\$set': json},
      );
      
      final updatedDoc = await DatabaseService.reviews.findOne({'_id': ObjectId.fromHexString(reviewId)});
      return Response.json(body: {
        'success': true,
        'data': Review.fromJson(updatedDoc!).toJson(),
        'message': 'Review updated successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid request: $e'},
      );
    }
  });
}

Future<Response> _deleteReview(RequestContext context, String reviewId) async {
  return DatabaseService.withDb(context, () async {
    try {
      await DatabaseService.reviews.deleteOne({'_id': ObjectId.fromHexString(reviewId)});
      return Response.json(body: {
        'success': true,
        'message': 'Review deleted successfully',
      });
    } catch (e) {
      return Response.json(
        statusCode: 400,
        body: {'success': false, 'message': 'Invalid review ID'},
      );
    }
  });
}

Future<Response> _getReviewsByRestaurant(RequestContext context, String restaurantId) async {
  return DatabaseService.withDb(context, () async {
    final docs = await DatabaseService.reviews.find({'restaurant_id': restaurantId}).toList();
    final reviews = docs.map((doc) => Review.fromJson(doc).toJson()).toList();
    return Response.json(body: {
      'success': true,
      'data': reviews,
      'message': 'Reviews fetched successfully',
    });
  });
}

Future<Response> _getReviewsByUser(RequestContext context, String userId) async {
  return DatabaseService.withDb(context, () async {
    final docs = await DatabaseService.reviews.find({'user_id': userId}).toList();
    final reviews = docs.map((doc) => Review.fromJson(doc).toJson()).toList();
    return Response.json(body: {
      'success': true,
      'data': reviews,
      'message': 'Reviews fetched successfully',
    });
  });
}

Future<Response> _getReviewSummary(RequestContext context, String restaurantId) async {
  return DatabaseService.withDb(context, () async {
    final docs = await DatabaseService.reviews.find({'restaurant_id': restaurantId}).toList();
    
    if (docs.isEmpty) {
      return Response.json(body: {
        'success': true,
        'data': {
          'average_rating': 0,
          'total_reviews': 0,
          'rating_distribution': {
            '5': 0, '4': 0, '3': 0, '2': 0, '1': 0
          }
        },
        'message': 'No reviews found',
      });
    }
    
    double totalRating = 0;
    final distribution = {'5': 0, '4': 0, '3': 0, '2': 0, '1': 0};
    
    for (var doc in docs) {
      final rating = (doc['rating'] ?? 0).toDouble();
      totalRating += (rating as num).toDouble();
      
      final key = rating.round().toString();
      if (distribution.containsKey(key)) {
        distribution[key] = distribution[key]! + 1;
      }
    }
    
    return Response.json(body: {
      'success': true,
      'data': {
        'average_rating': (totalRating / docs.length).toStringAsFixed(1),
        'total_reviews': docs.length,
        'rating_distribution': distribution,
      },
      'message': 'Review summary fetched successfully',
    });
  });
}

Future<void> _updateRestaurantRating(String restaurantId) async {
  final docs = await DatabaseService.reviews.find({'restaurant_id': restaurantId}).toList();
  if (docs.isEmpty) return;
  
  double totalRating = 0;
  for (var doc in docs) {
    totalRating += ((doc['rating'] ?? 0) as num).toDouble();
  }
  
  final avgRating = totalRating / docs.length;
  await DatabaseService.restaurants.updateOne(
    {'_id': ObjectId.fromHexString(restaurantId)},
    {'\$set': {'rating': avgRating}},
  );
}