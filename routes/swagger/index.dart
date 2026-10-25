import 'package:dart_frog/dart_frog.dart';

Future<Response> onRequest(RequestContext context) async {
  const html = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>TastyGo API Documentation</title>
  <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5.9.0/swagger-ui.css" />
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5.9.0/swagger-ui-bundle.js"></script>
  <script>
    window.onload = function() {
      SwaggerUIBundle({
        url: "/api-json", 
        dom_id: '#swagger-ui',
        deepLinking: true,
        presets: [
          SwaggerUIBundle.presets.apis,
          SwaggerUIBundle.SwaggerUIStandalonePreset
        ],
        layout: "BaseLayout"
      });
    };
  </script>
</body>
</html>
  ''';

  // ប្រើ Response() ធម្មតា ជំនួសឱ្យ Response.json() ដើម្បីបង្ហាញ HTML
  return Response(
    body: html,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
    },
  );
}