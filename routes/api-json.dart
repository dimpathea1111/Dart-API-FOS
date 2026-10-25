import 'dart:convert';
import 'dart:io';
import 'package:dart_frog/dart_frog.dart';

Future<Response> onRequest(RequestContext context) async {
  final file = File('public/openapi.json');
  
  if (await file.exists()) {
    final jsonString = await file.readAsString();
    
    // បម្លែងពី String ទៅជា Map ដើម្បីឱ្យ Response យល់ថាវាជា JSON ពិតប្រាកដ
    final jsonData = jsonDecode(jsonString);
    
    return Response.json(
      body: jsonData,
      headers: {'Content-Type': 'application/json'},
    );
  } else {
    return Response.json(
      statusCode: 404,
      body: {'error': 'openapi.json not found in public folder.'},
    );
  }
}