import 'package:flutter/material.dart';
import '../models/login_response.dart';
import '../models/user_role.dart';
import '../screens/main_app_screen.dart';
import '../screens/vendor_profile_completion_screen.dart';
import 'api_service.dart';

enum LoginDestination { home, vendorProfile, pending, rejected }

/// Approval controls dashboard access; it does not determine profile existence.
LoginDestination loginDestination(LoginResponse response, UserRole role) {
  if (!response.isFullLogin) throw Exception('Login did not complete.');
  if (role == UserRole.customer) return LoginDestination.home;
  if (response.profileExists == false) return LoginDestination.vendorProfile;
  if (response.isRejected == true) return LoginDestination.rejected;
  if (response.isApproved == true ||
      response.availableRoles?.contains('vendor') == true) {
    return LoginDestination.home;
  }
  if (response.profileExists == true) return LoginDestination.pending;
  throw Exception('Could not confirm your vendor profile. Please try again.');
}

Future<void> navigateAfterLogin(
    BuildContext context, LoginResponse response, UserRole role,
    {bool removeAllRoutes = true}) async {
  var resolved = response;
  if (!response.isFullLogin) {
    throw Exception('Login did not complete. Please try again.');
  }
  // Older servers may omit these fields. Only a successful lookup can establish
  // that a profile is absent; network failures must never trigger onboarding.
  if (role == UserRole.vendor && response.profileExists == null) {
    final status = await ApiService().getVendorProfileStatus(response.token!);
    resolved = LoginResponse(
      token: response.token,
      user: response.user,
      availableRoles: response.availableRoles,
      profileExists: status['exists'],
      isApproved: status['is_approved'],
      isRejected: status['is_rejected'],
      rejectionReason: status['rejection_reason'],
    );
  }
  final destination = loginDestination(resolved, role);
  if (!context.mounted) return;
  if (destination == LoginDestination.pending ||
      destination == LoginDestination.rejected) {
    final rejected = destination == LoginDestination.rejected;
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(rejected ? 'Profile Rejected' : 'Pending Approval'),
              content: Text(rejected
                  ? resolved.rejectionReason ??
                      'Your vendor profile was rejected. Please contact support.'
                  : 'Your vendor profile is already submitted and awaiting admin approval. You do not need to fill it in again.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'))
              ],
            ));
    return;
  }
  if (destination == LoginDestination.home && !removeAllRoutes) {
    // FIX: Instead of popping into potentially empty history, check if we can pop.
    // If we can't pop, we MUST push a new route to prevent the blank screen crash.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainAppScreen()),
      );
    }
    return;
  }
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
        builder: (_) => destination == LoginDestination.vendorProfile
            ? const VendorProfileCompletionScreen()
            : const MainAppScreen()),
    (_) => false,
  );
}
