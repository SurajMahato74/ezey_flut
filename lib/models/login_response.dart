// lib/models/login_response.dart
import 'user.dart';

class LoginResponse {
  final String? token;
  final User? user;
  final List<String>? availableRoles;
  final String? currentRole;
  final bool? profileExists;
  final bool? isApproved;
  final bool? isRejected;
  final String? rejectionReason;
  final DateTime? rejectionDate;
  final String? message;
  final bool? needsVerification;
  final bool? needsPrivacyAgreement;
  final int? userId;

  LoginResponse({
    this.token,
    this.user,
    this.availableRoles,
    this.currentRole,
    this.profileExists,
    this.isApproved,
    this.isRejected,
    this.rejectionReason,
    this.rejectionDate,
    this.message,
    this.needsVerification,
    this.needsPrivacyAgreement,
    this.userId,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      token: json['token'] as String?,
      user: json['user'] != null ? User.fromJson(json['user']) : null,
      availableRoles: json['available_roles'] != null
          ? List<String>.from(json['available_roles'])
          : null,
      currentRole: json['current_role'] as String?,
      profileExists: json['profile_exists'] as bool?,
      isApproved: json['is_approved'] as bool?,
      isRejected: json['is_rejected'] as bool?,
      rejectionReason: json['rejection_reason'] as String?,
      rejectionDate: json['rejection_date'] != null
          ? DateTime.tryParse(json['rejection_date'])
          : null,
      message: json['message'] as String?,
      needsVerification: json['needs_verification'] as bool?,
      needsPrivacyAgreement: json['needs_privacy_agreement'] as bool?,
      userId: json['user_id'] as int?,
    );
  }

  // THIS IS REQUIRED FOR YOUR LOGIN FLOW
  bool get isFullLogin => token != null && user != null;
}