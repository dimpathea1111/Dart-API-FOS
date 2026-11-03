import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_payway/dart_payway.dart';
import 'package:dotenv/dotenv.dart';

final env = DotEnv(includePlatformEnvironment: true)..load();

Future<Response> onRequest(RequestContext context) async {
  final body = await context.request.json() as Map<String, dynamic>;
  final amount = double.parse(body['amount'].toString());
  final tranId = body['tran_id'] as String;

  // ១. បង្កើត Merchant សម្រាប់ version 1.x
  final merchant = PaywayMerchant(
    merchantID: env['PAYWAY_MERCHANT_ID']!,
    merchantApiName: env['PAYWAY_MERCHANT_NAME'] ?? 'My Dart API',
    merchantApiKey: env['PAYWAY_API_KEY']!,
    baseApiUrl: env['PAYWAY_API_URL']!,
    refererDomain: env['PAYWAY_REFERER_DOMAIN'] ?? 'http://localhost',
  );

  final service = PaywayTransactionService(merchant: merchant);

  // ២. បង្កើត Transaction
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

    // ៣. ពិនិត្យលទ្ធផលដោយប្រើ response.status (ដែលជា PaywayTransactionStatus object)
    // នៅក្នុង version 1.1.0+2, code '0' មានន័យថាជោគជ័យ
    final isSuccess = response.status?.code == '0';

    if (isSuccess) {
      return Response.json(
        body: {
          'status_code': response.status?.code,
          'status_message': response.status?.message,
          'checkout_url': response.checkoutQrUrl, // ✅ ប្រើ checkoutQrUrl
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










// import 'package:dart_frog/dart_frog.dart';
// import 'package:dart_payway/dart_payway.dart';
// import 'package:dotenv/dotenv.dart';

// final env = DotEnv(includePlatformEnvironment: true)..load();

// Future<Response> onRequest(RequestContext context) async {
//   try {
//     // 1. Get request data
//     final body = await context.request.json() as Map<String, dynamic>;

//     final amount = double.tryParse(body['amount'].toString());
//     final tranId = body['tran_id']?.toString();

//     if (amount == null || amount <= 0 || tranId == null || tranId.isEmpty) {
//       return Response.json(
//         statusCode: 400,
//         body: {'error': 'Invalid amount or transaction ID'},
//       );
//     }

//     // 2. Initialize PayWay service
//     final service = PaywayTransactionService(
//       merchant: PaywayMerchant(
//         merchantID: env['PAYWAY_MERCHANT_ID'] ?? '',
//         merchantApiName: env['PAYWAY_MERCHANT_NAME'] ?? '',
//         merchantApiKey: env['PAYWAY_API_KEY'] ?? '',
//         baseApiUrl: env['PAYWAY_API_URL'] ?? '',
//         refererDomain: 'https://your-domain.com',
//       ),
//     );

//     // 3. Create transaction
//     final transaction = PaywayCreateTransaction(
//       amount: amount,
//       items: [
//         PaywayTransactionItem(
//           name: 'Food Order',
//           price: amount,
//           quantity: 1,
//         ),
//       ],
//       reqTime: service.uniqueReqTime(),
//       tranId: tranId,
//       email: body['email']?.toString() ?? '',
//       firstname: body['firstname']?.toString() ?? '',
//       lastname: body['lastname']?.toString() ?? '',
//       phone: body['phone']?.toString() ?? '',
//       option: PaywayPaymentOption.abapay_khqr_deeplink,
//       shipping: 0.0,
//       returnUrl: 'https://your-domain.com/api/payway/callback',
//     );

//     // 4. Generate checkout URI
//     final checkoutUri = await service.generateTransactionCheckoutURI(
//       transaction: transaction,
//     );

//     // 5. Return checkout URL
//     return Response.json(
//       body: {
//         'success': true,
//         'tran_id': tranId,
//         'checkout_url': checkoutUri.toString(),
//       },
//     );
//   } catch (e) {
//     return Response.json(
//       statusCode: 500,
//       body: {'error': e.toString()},
//     );
//   }
// }
