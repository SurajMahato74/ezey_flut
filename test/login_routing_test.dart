import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ezeyway/models/login_response.dart';
import 'package:ezeyway/models/user_role.dart';
import 'package:ezeyway/services/api_service.dart';
import 'package:ezeyway/services/auth_service.dart';
import 'package:ezeyway/services/login_navigation.dart';

LoginResponse response(
        {bool? exists, bool approved = false, bool rejected = false}) =>
    LoginResponse.fromJson({
      'token': 'test-token',
      'user': {
        'id': 1,
        'username': 'vendor',
        'email': 'vendor@example.com',
        'user_type': 'customer',
        'created_at': '2026-01-01T00:00:00Z'
      },
      'available_roles': ['customer', if (approved) 'vendor'],
      'profile_exists': exists,
      'is_approved': approved,
      'is_rejected': rejected,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('returning approved vendor goes home after OTP', () {
    expect(
        loginDestination(
            response(exists: true, approved: true), UserRole.vendor),
        LoginDestination.home);
  });
  test('pending and rejected vendors never repeat onboarding', () {
    expect(loginDestination(response(exists: true), UserRole.vendor),
        LoginDestination.pending);
    expect(
        loginDestination(
            response(exists: true, rejected: true), UserRole.vendor),
        LoginDestination.rejected);
  });
  test('only absent vendor profiles need onboarding; customers go home', () {
    expect(loginDestination(response(exists: false), UserRole.vendor),
        LoginDestination.vendorProfile);
    expect(loginDestination(response(exists: false), UserRole.customer),
        LoginDestination.home);
    expect(
        () => loginDestination(response(), UserRole.vendor), throwsException);
    expect(() => loginDestination(LoginResponse(), UserRole.customer),
        throwsException);
  });
  test('OTP preserves selected role and profile existence rather than approval',
      () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();
    await Future<void>.delayed(Duration.zero);
    await http.runWithClient(() async {
      await auth.loginWithOtp('vendor@example.com', '123456',
          selectedRole: UserRole.vendor);
    },
        () => MockClient((request) async {
              expect(request.url.path, '/api/verify-otp/');
              expect(jsonDecode(request.body), {
                'email': 'vendor@example.com',
                'otp': '123456',
              });
              final existing = response(exists: true);
              return http.Response(
                  jsonEncode({
                    'token': existing.token,
                    'user': existing.user!.toJson(),
                    'available_roles': existing.availableRoles,
                    'profile_exists': true,
                    'is_approved': false,
                  }),
                  200);
            }));
    expect(auth.currentRole, UserRole.vendor);
    expect(auth.needsVendorProfileCompletion(UserRole.vendor), isFalse);
    expect(auth.hasVendorProfilePending(), isTrue);
    await auth.completeLogin(response(exists: true, approved: true),
        selectedRole: UserRole.customer);
    expect(auth.currentRole, UserRole.customer);
    await expectLater(auth.completeLogin(LoginResponse()), throwsException);
  });
  test('profile lookup errors never report missing profile', () async {
    await http.runWithClient(() async {
      await expectLater(
          ApiService().getVendorProfileStatus('test-token'), throwsException);
    }, () => MockClient((_) async => http.Response('{}', 500)));
  });
  for (final paginated in [true, false]) {
    test('profile lookup supports ${paginated ? 'paginated' : 'list'} response',
        () async {
      final profiles = [
        {'id': 1, 'is_approved': true}
      ];
      await http.runWithClient(() async {
        final status = await ApiService().getVendorProfileStatus('test-token');
        expect(status['exists'], isTrue);
        expect(status['is_approved'], isTrue);
      },
          () => MockClient((_) async => http.Response(
              jsonEncode(paginated ? {'results': profiles} : profiles), 200)));
    });
  }
}
