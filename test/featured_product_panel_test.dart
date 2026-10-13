import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:ezeyway/services/auth_service.dart';
import 'package:ezeyway/widgets/featured_product_panel.dart';

class TestAuth extends ChangeNotifier implements AuthService {
  @override
  String get token => 'test-token';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final width in [360.0, 1200.0]) {
    testWidgets(
        'requires explicit purchase and handles wallet rejection at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final posts = <http.Request>[];
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Token test-token');
        if (request.url.path.endsWith('/products/42/')) {
          return http.Response('{"featured": false}', 200);
        }
        if (request.method == 'POST') {
          posts.add(request);
          return http.Response(
              jsonEncode({'error': 'Insufficient wallet balance'}), 400);
        }
        return http.Response(
            jsonEncode(request.url.path.endsWith('featured-info/')
                ? {'current_purchase': null, 'can_modify': true}
                : {
                    'packages': [
                      {
                        'id': 2,
                        'name': 'Weekly',
                        'amount': '100.00',
                        'duration_days': 7
                      }
                    ]
                  }),
            200);
      });
      await tester.pumpWidget(ChangeNotifierProvider<AuthService>.value(
          value: TestAuth(),
          child: MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: FeaturedProductPanel(
                          productId: 42, client: client))))));
      await tester.pumpAndSettle();
      expect(posts, isEmpty);
      await tester.tap(find.text('Weekly — Rs. 100.00'));
      await tester.pumpAndSettle();
      expect(posts, isEmpty);
      await tester.tap(find.text('Pay Rs. 100.00 and feature product'));
      await tester.pumpAndSettle();
      expect(posts, hasLength(1));
      expect(posts.single.url.path, '/api/featured-packages/purchase/');
      expect(jsonDecode(posts.single.body), containsPair('product_id', 42));
      expect(jsonDecode(posts.single.body), containsPair('package_id', 2));
      expect(
          find.textContaining('Insufficient wallet balance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('started package cannot be purchased again or rescheduled',
      (tester) async {
    final client = MockClient((request) async => http.Response(
        jsonEncode(request.url.path.endsWith('featured-info/')
            ? {
                'can_modify': false,
                'current_purchase': {
                  'package_name': 'Weekly',
                  'start_date': '2026-10-01',
                  'end_date': '2026-10-08'
                }
              }
            : request.url.path.endsWith('/products/42/')
                ? {'featured': false}
                : {'packages': []}),
        200));
    await tester.pumpWidget(ChangeNotifierProvider<AuthService>.value(
        value: TestAuth(),
        child: MaterialApp(
            home: Scaffold(
                body: FeaturedProductPanel(
                    productId: 42, featured: true, client: client)))));
    await tester.pumpAndSettle();
    expect(find.textContaining('not marked featured'), findsOneWidget);
    expect(find.text('This package has started and cannot be changed.'),
        findsNothing);
    expect(find.text('Check status again'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.textContaining('Saved featured status: Off'), findsOneWidget);
    expect(find.text('Saved featured status: On'), findsNothing);
  });
}
