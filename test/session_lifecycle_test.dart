import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ezeyway/models/login_response.dart';
import 'package:ezeyway/models/user_role.dart';
import 'package:ezeyway/services/auth_service.dart';
import 'package:ezeyway/services/data_preloader_service.dart';

final user = {
  'id': 9,
  'username': 'existing',
  'email': 'existing@example.com',
  'user_type': 'vendor',
  'created_at': '2026-01-01T00:00:00Z'
};
LoginResponse login() => LoginResponse.fromJson({
      'token': 'saved-token',
      'user': user,
      'available_roles': ['customer', 'vendor'],
      'profile_exists': true,
      'is_approved': true
    });
Map<String, Object> saved() =>
    {'token': 'saved-token', 'user': jsonEncode(user), 'last_role': 'vendor'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saved session is verified before restoring last vendor mode', () async {
    SharedPreferences.setMockInitialValues(saved());
    await http.runWithClient(() async {
      final auth = AuthService.forTesting();
      expect(auth.isLoggedIn, isFalse);
      expect(auth.user, isNull);
      await auth.initialized;
      expect(auth.isInitialized, isTrue);
      expect(auth.isLoggedIn, isTrue);
      expect(auth.currentRole, UserRole.vendor);
      auth.dispose();
    },
        () => MockClient((request) async => http.Response(
            jsonEncode(request.url.path.endsWith('/profile/')
                ? user
                : {
                    'results': [
                      {'id': 1, 'is_approved': true}
                    ]
                  }),
            200)));
  });

  test('expired saved token clears account and remembered mode', () async {
    SharedPreferences.setMockInitialValues(saved());
    await http.runWithClient(() async {
      final auth = AuthService.forTesting();
      await auth.initialized;
      expect(auth.isInitialized, isTrue);
      expect(auth.isLoggedIn, isFalse);
      expect(auth.user, isNull);
      expect(auth.currentRole, isNull);
      expect(
          (await SharedPreferences.getInstance()).getString('token'), isNull);
      auth.dispose();
    },
        () => MockClient(
            (_) async => http.Response('{"detail":"Invalid token."}', 401)));
  });

  test('offline startup does not display unverified saved user', () async {
    SharedPreferences.setMockInitialValues(saved());
    await http.runWithClient(() async {
      final auth = AuthService.forTesting();
      await auth.initialized;
      expect(auth.initializationError, contains('Could not verify'));
      expect(auth.user, isNull);
      expect(auth.isLoggedIn, isFalse);
      await auth.loginAsGuest(UserRole.customer);
      expect(auth.initializationError, isNull);
      expect(auth.token, isNull);
      auth.dispose();
    }, () => MockClient((_) async => throw http.ClientException('offline')));
  });

  test('late startup response cannot restore account after guest or logout',
      () async {
    for (final guest in [true, false]) {
      SharedPreferences.setMockInitialValues(saved());
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      await http.runWithClient(() async {
        final auth = AuthService.forTesting();
        await started.future;
        if (guest) {
          await auth.loginAsGuest(UserRole.customer);
        } else {
          await auth.clearSession();
        }
        pending.complete(http.Response(jsonEncode(user), 200));
        await auth.initialized;
        expect(auth.user, isNull);
        expect(auth.token, isNull);
        expect(auth.availableRoles, isEmpty);
        expect(auth.currentRole, guest ? UserRole.customer : isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('token'), isNull);
        expect(prefs.getString('user'), isNull);
        auth.dispose();
      },
          () => MockClient((request) {
                if (request.url.path.endsWith('/profile/')) {
                  started.complete();
                  return pending.future;
                }
                return Future.value(http.Response('{"results":[]}', 200));
              }));
    }
  });

  test(
      'skip from vendor is guest customer with no old permissions, including restart',
      () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService.forTesting();
    await auth.initialized;
    await auth.completeLogin(login(), selectedRole: UserRole.vendor);
    await auth.loginAsGuest(UserRole.vendor);
    expect(auth.currentRole, UserRole.customer);
    expect(auth.user, isNull);
    expect(auth.availableRoles, isEmpty);
    expect(auth.vendorProfileExists, isNull);
    final restarted = AuthService.forTesting();
    await restarted.initialized;
    expect(restarted.isLoggedIn, isFalse);
    expect(restarted.currentRole, UserRole.customer);
    expect(restarted.user, isNull);
    auth.dispose();
    restarted.dispose();
  });

  test('queued save cannot bring login back after logout', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService.forTesting();
    await auth.initialized;
    final saving = auth.completeLogin(login());
    await auth.clearSession();
    await saving;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('token'), isNull);
    expect(prefs.getString('last_role'), isNull);
    expect(auth.isLoggedIn, isFalse);
    auth.dispose();
  });

  test('late OTP response cannot log user back in after logout', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService.forTesting();
    await auth.initialized;
    final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      final signingIn = auth.loginWithOtp('existing@example.com', '123456');
      await auth.clearSession();
      final cancelled = expectLater(signingIn,
          throwsA(predicate((e) => e.toString().contains('Login cancelled'))));
      pending.complete(http.Response(
          jsonEncode({
            'token': 'saved-token',
            'user': user,
            'available_roles': ['customer', 'vendor'],
          }),
          200));
      await cancelled;
      expect(auth.user, isNull);
      expect(auth.isLoggedIn, isFalse);
      expect(
          (await SharedPreferences.getInstance()).getString('token'), isNull);
    }, () => MockClient((_) => pending.future));
    auth.dispose();
  });

  test('cache refresh preserves login preferences', () async {
    SharedPreferences.setMockInitialValues({});
    await AuthService().initialized;
    await AuthService().completeLogin(login());
    final preloader = DataPreloaderService();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cache_categories', '[]');
    await preloader.clearCache();
    expect(prefs.getString('token'), 'saved-token');
    expect(prefs.getString('user'), isNotNull);
    expect(prefs.getString('cache_categories'), isNull);
    await AuthService().clearSession();
    expect(preloader.userProfile, isNull);
    expect(preloader.vendorProfile, isNull);
    expect(preloader.cart, isNull);
  });
}
