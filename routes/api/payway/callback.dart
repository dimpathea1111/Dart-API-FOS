

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_payway/dart_payway.dart';
import 'package:dotenv/dotenv.dart';

final env = DotEnv(includePlatformEnvironment: true)..load();

Future<Response> onRequest(RequestContext context) async {
  final body = await context.request.json() as Map<String, dynamic>;
  
  // បន្ថែម print ដើម្បីមើលទិន្នន័យពី Postman
  print('Body from Postman: $body');
  print('Merchant ID from .env: ${env['PAYWAY_MERCHANT_ID']}');
  print('API Key from .env: ${env['PAYWAY_API_KEY']}');

  // ពិនិត្យថាតើមាន amount និង tran_id ឬអត់
  final amountStr = body['amount']?.toString();
  final tranId = body['tran_id']?.toString();

  if (amountStr == null || tranId == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Missing amount or tran_id in request body'},
    );
  }

  // ពិនិត្យថាតើ .env ត្រូវបានផ្ទុកត្រឹមត្រូវឬអត់
  if (env['PAYWAY_MERCHANT_ID'] == null || env['PAYWAY_API_KEY'] == null) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Missing PAYWAY environment variables in .env file'},
    );
  }

  final amount = double.parse(amountStr);

  // បង្កើត Merchant
  final merchant = PaywayMerchant(
    merchantID: env['PAYWAY_MERCHANT_ID']!,
    merchantApiName: env['PAYWAY_MERCHANT_NAME'] ?? 'My Dart API',
    merchantApiKey: env['PAYWAY_API_KEY']!,
    baseApiUrl: env['PAYWAY_API_URL'] ?? 'https://payway-dev.ababank.com/api/',
    refererDomain: env['PAYWAY_REFERER_DOMAIN'] ?? 'http://localhost',
  );

  final service = PaywayTransactionService(merchant: merchant);

  // បង្កើត Transaction
  final transaction = PaywayCreateTransaction(
    amount: amount,
    items: [
      PaywayTransactionItem(name: 'Order $tranId', price: amount, quantity: 1),
    ],
    reqTime: service.uniqueReqTime(),
    tranId: tranId,
    email: 'customer@example.com',
    firstname: 'Customer',
    lastname: 'Name',
    phone: '010000000',
    option: PaywayPaymentOption.abapay_khqr_deeplink,
    shipping: 0.0,
    returnUrl: env['PAYWAY_RETURN_URL'] ?? 'http://localhost:8080/api/payway/callback',
    continueSuccessUrl: 'http://localhost:8080/success',
  );

  try {
    final response = await service.createTransaction(
      transaction: transaction,
      enabledLogger: true,
    );

    final isSuccess = response.status?.code == '0';

    if (isSuccess) {
      return Response.json(
        body: {
          'status_code': response.status?.code,
          'status_message': response.status?.message,
          'checkout_url': response.checkoutQrUrl,
          'abapay_deeplink': response.abapayDeeplink,
          'qr_string': response.qrString,
          'qr_image': response.qrImage,
        },
      );
    } else {
      return Response.json(
        statusCode: 400,
        body: {
          'status_code': response.status?.code,
          'message': response.status?.message ?? 'Transaction failed to initiate',
        },
      );
    }
  } catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': e.toString()},
    );
  }
}








// import 'dart:io';
// import 'package:dart_frog/dart_frog.dart';
// import 'package:dart_payway/dart_payway.dart';
// import 'package:dotenv/dotenv.dart';

// final env = DotEnv(includePlatformEnvironment: true)..load();

// Future<Response> onRequest(RequestContext context) async {
//   final body = await context.request.json() as Map<String, dynamic>;
//   final tranId = body['tran_id'] as String?;

//   if (tranId == null) {
//     return Response(statusCode: 400, body: 'Missing tran_id');
//   }

//   final merchant = PaywayMerchant(
//     merchantID: env['PAYWAY_MERCHANT_ID']!,
//     merchantApiName: env['PAYWAY_MERCHANT_NAME'] ?? 'My Dart API',
//     merchantApiKey: env['PAYWAY_API_KEY']!,
//     baseApiUrl: env['PAYWAY_API_URL']!,
//     refererDomain: env['PAYWAY_REFERER_DOMAIN'] ?? 'http://localhost',
//   );

//   final service = PaywayTransactionService(merchant: merchant);

//   try {
//     // ១. បង្កើត PaywayCheckTransaction object
//     final checkTransaction = PaywayCheckTransaction(
//       tranId: tranId,
//       reqTime: service.uniqueReqTime(),
//     );

//     // ២. ហៅ checkTransaction
//     final checkResponse = await service.checkTransaction(
//       transaction: checkTransaction,
//     );

//     // ៣. ពិនិត្យស្ថានភាព (status ជា int ដោយផ្ទាល់)
//     // តម្លៃ 0 មានន័យថា ជោគជ័យ (APPROVED)
//     final isApproved = checkResponse.status == 0;

//     if (isApproved) {
//       // TODO: ធ្វើបច្ចុប្បន្នភាព Database នៅទីនេះ
//       print('✅ Payment successful for order: $tranId');
//       return Response(statusCode: 200, body: 'OK');
//     } else {
//       // បង្ហាញលេខកូដស្ថានភាពដោយផ្ទាល់
//       print('❌ Payment not approved. Status code: ${checkResponse.status}');
//       return Response(statusCode: 200, body: 'OK');
//     }
//   } catch (e) {
//     print('Error checking transaction: $e');
//     return Response(statusCode: 500, body: 'Error: ${e.toString()}');
//   }
// }




