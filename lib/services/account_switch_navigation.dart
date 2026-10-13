import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/user_role.dart';
import '../screens/main_app_screen.dart';
import '../screens/vendor_profile_completion_screen.dart';
import 'auth_service.dart';

String accountSwitchError(Object error) {
  if (error is TimeoutException) {
    return 'The server took too long to respond. Please try again.';
  }
  if (error is http.ClientException) {
    return 'Could not reach the server. Check your connection and try again.';
  }
  if (error is FormatException) {
    return 'The server returned an invalid response. Please try again.';
  }
  return error.toString().replaceFirst('Exception: ', '');
}

Future<void> switchAccountMode(BuildContext context, UserRole role) async {
  // Auth notifications may dispose the old profile screen. Keep the root
  // navigator, and remove only this operation's loading route.
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  final loading = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  navigator.push(loading);
  bool? switched;
  Object? failure;
  try {
    switched = await AuthService().switchToRole(role);
  } catch (error) {
    failure = error;
  } finally {
    if (navigator.mounted && loading.isActive) navigator.removeRoute(loading);
  }
  if (!navigator.mounted) return;
  if (failure != null) {
    if (messenger.mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text(accountSwitchError(failure)),
        backgroundColor: Colors.red,
      ));
    }
    return;
  }
  if (switched == false) {
    await navigator.push(MaterialPageRoute(
      builder: (_) => const VendorProfileCompletionScreen(),
    ));
  } else {
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainAppScreen()),
      (_) => false,
    );
  }
}
