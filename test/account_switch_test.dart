import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ezeyway/models/login_response.dart';
import 'package:ezeyway/models/user_role.dart';
import 'package:ezeyway/services/auth_service.dart';
import 'package:ezeyway/services/account_switch_navigation.dart';

Map<String, dynamic> user(String role) => {
      'id': 7,
      'username': 'returning',
      'email': 'returning@example.com',
      'user_type': role,
      'created_at': '2026-01-01T00:00:00Z',
    };

Map<String, dynamic> session(String role) => {
      'token': 'otp-session',
      'user': user(role),
      'current_role': role,
      'available_roles': ['customer'],
      'profile_exists': true,
      'is_approved': true,
    };

http.Response ok(Object data) => http.Response(jsonEncode(data), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuthService auth;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    auth = AuthService();
    await Future<void>.delayed(Duration.zero);
  });
  setUp(() async {
    await auth.completeLogin(LoginResponse.fromJson(session('customer')),
        selectedRole: UserRole.customer);
  });

  test('OTP session switches both ways with stale cached roles', () async {
    final requests = <String>[];
    await http.runWithClient(() async {
      await auth.loginWithOtp('returning@example.com', '123456',
          selectedRole: UserRole.customer);
      expect(auth.availableRoles, ['customer']);
      expect(await auth.switchToRole(UserRole.vendor), isTrue);
      expect(auth.currentRole, UserRole.vendor);
      expect(auth.user!.userType, 'vendor');
      expect(await auth.switchToRole(UserRole.customer), isTrue);
      expect(auth.currentRole, UserRole.customer);
      expect(auth.user!.userType, 'customer');
      expect(auth.token, 'otp-session');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_role'), 'customer');
      expect(requests.where((path) => path.endsWith('vendor-profiles/')),
          hasLength(1));
    },
        () => MockClient((request) async {
              requests.add(request.url.path);
              if (request.url.path.endsWith('verify-otp/'))
                return ok(session('customer'));
              expect(request.headers['Authorization'], 'Token otp-session');
              if (request.method == 'GET')
                return ok({
                  'results': [
                    {'id': 4, 'is_approved': true}
                  ]
                });
              final role = jsonDecode(request.body)['role'] as String;
              return ok({
                'current_role': role,
                'available_roles': ['customer', 'vendor'],
                'user': user(role)
              });
            }));
  });

  test('confirmed absent profile opens onboarding without changing mode',
      () async {
    await http.runWithClient(() async {
      expect(await auth.switchToRole(UserRole.vendor), isFalse);
      expect(auth.currentRole, UserRole.customer);
      expect(auth.vendorProfileExists, isFalse);
    },
        () => MockClient((request) async {
              expect(request.method, 'GET');
              return ok({'results': []});
            }));
  });

  for (final rejected in [false, true]) {
    test('existing ${rejected ? 'rejected' : 'pending'} vendor shows reason',
        () async {
      await http.runWithClient(() async {
        await expectLater(
            auth.switchToRole(UserRole.vendor),
            throwsA(predicate((e) => e.toString().contains(
                rejected ? 'Document unreadable' : 'pending admin approval'))));
        expect(auth.currentRole, UserRole.customer);
        expect(auth.vendorProfileExists, isTrue);
      },
          () => MockClient((request) async {
                expect(request.method, 'GET');
                return ok({
                  'results': [
                    {
                      'id': 4,
                      'is_approved': false,
                      'is_rejected': rejected,
                      'rejection_reason': 'Document unreadable'
                    }
                  ]
                });
              }));
    });
  }

  for (final status in [401, 403, 404, 500]) {
    test('HTTP $status does not change mode or trigger onboarding', () async {
      await http.runWithClient(() async {
        await expectLater(
            auth.switchToRole(UserRole.vendor),
            throwsA(predicate((e) => e.toString().contains(
                status == 401 ? 'session has expired' : 'HTTP $status'))));
        expect(auth.currentRole, UserRole.customer);
        expect(auth.vendorProfileExists, isTrue);
      },
          () => MockClient((_) async =>
              http.Response(jsonEncode({'detail': 'Request denied'}), status)));
    });
  }

  test('switch endpoint rejection preserves local role and backend reason',
      () async {
    await http.runWithClient(() async {
      await expectLater(
          auth.switchToRole(UserRole.vendor),
          throwsA(predicate(
              (e) => e.toString().contains('Vendor access suspended'))));
      expect(auth.currentRole, UserRole.customer);
      expect(auth.availableRoles, ['customer']);
    },
        () => MockClient((request) async => request.method == 'GET'
            ? ok({
                'results': [
                  {'id': 4, 'is_approved': true}
                ]
              })
            : http.Response('{"error":"Vendor access suspended"}', 403)));
  });

  test('duplicate switches cannot toggle the role twice', () async {
    final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      final first = auth.switchToRole(UserRole.customer);
      await expectLater(
          auth.switchToRole(UserRole.customer),
          throwsA(
              predicate((e) => e.toString().contains('already in progress'))));
      pending.complete(ok({
        'current_role': 'customer',
        'available_roles': ['customer'],
        'user': user('customer')
      }));
      expect(await first, isTrue);
      expect(auth.availableRoles, ['customer']);
    }, () => MockClient((_) => pending.future));
  });

  test('guest is told to sign in', () async {
    await auth.loginAsGuest(UserRole.customer);
    await expectLater(auth.switchToRole(UserRole.vendor),
        throwsA(predicate((e) => e.toString().contains('Please sign in'))));
  });

  testWidgets(
      'failed switch closes loading and shows reason without leaving profile',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
        builder: (context) => TextButton(
          onPressed: () => switchAccountMode(context, UserRole.vendor),
          child: const Text('Switch to Vendor'),
        ),
      ))));
      await tester.tap(find.text('Switch to Vendor'));
      await tester.pumpAndSettle();
      expect(find.text('Switch to Vendor'), findsOneWidget);
      expect(find.textContaining('HTTP 404'), findsOneWidget);
      expect(
          find.textContaining('Profile service unavailable'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(auth.currentRole, UserRole.customer);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((_) async =>
            http.Response('{"detail":"Profile service unavailable"}', 404)));
  });

  test('network and timeout errors have useful messages', () {
    expect(accountSwitchError(http.ClientException('offline')),
        contains('Check your connection'));
    expect(
        accountSwitchError(TimeoutException('timeout')), contains('too long'));
  });
}
