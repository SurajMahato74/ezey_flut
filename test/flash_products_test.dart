import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ezeyway/services/api_service.dart';

void main() {
  test(
      'Flash finds featured products beyond first page using backend total_pages',
      () async {
    final pages = <int>[];
    await http.runWithClient(() async {
      final products = await ApiService().getFlashProducts();
      expect(products.map((p) => p['id']), [2, 3]);
      expect(pages, [1, 2, 3]);
    },
        () => MockClient((request) async {
              expect(request.url.path, '/api/search/products/');
              expect(
                  request.url.queryParameters.containsKey('latitude'), isFalse);
              expect(request.url.queryParameters.containsKey('longitude'),
                  isFalse);
              final page = int.parse(request.url.queryParameters['page']!);
              pages.add(page);
              return http.Response(
                  jsonEncode({
                    'page': page,
                    'total_pages': 3,
                    'page_size': 100,
                    'results': [
                      {'id': page, 'featured': page > 1, 'vendor_id': 7}
                    ],
                  }),
                  200);
            }));
  });

  test('Flash continues across empty pages and deduplicates featured items',
      () async {
    await http.runWithClient(() async {
      final products = await ApiService().getFlashProducts();
      expect(products.map((p) => p['id']), [4]);
    },
        () => MockClient((request) async {
              final page = int.parse(request.url.queryParameters['page']!);
              return http.Response(
                  jsonEncode({
                    'total_pages': 3,
                    'results': page == 1
                        ? []
                        : [
                            {'id': 4, 'featured': true, 'quantity': 0}
                          ],
                  }),
                  200);
            }));
  });

  test('Flash also supports next-link pagination', () async {
    final pages = <int>[];
    await http.runWithClient(() async {
      expect((await ApiService().getFlashProducts()).map((p) => p['id']), [2]);
      expect(pages, [1, 2]);
    },
        () => MockClient((request) async {
              final page = int.parse(request.url.queryParameters['page']!);
              pages.add(page);
              return http.Response(
                  jsonEncode({
                    'next': page == 1
                        ? 'https://ezeyway.com/api/search/products/?page=2'
                        : null,
                    'results': [
                      {'id': page, 'featured': page == 2}
                    ],
                  }),
                  200);
            }));
  });

  test('Flash surfaces load failures instead of reporting no featured products',
      () async {
    await http.runWithClient(() async {
      await expectLater(ApiService().getFlashProducts(), throwsException);
    }, () => MockClient((_) async => http.Response('{}', 500)));
  });
}
