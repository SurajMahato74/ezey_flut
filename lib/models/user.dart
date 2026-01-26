class User {
  final int id;
  final String username;
  final String displayName;
  final String email;
  final String userType;
  final String? phoneNumber;
  final String? address;
  final DateTime? dateOfBirth;
  final String? profilePicture;
  final String? profilePictureUrl;
  final String? googleId;
  final bool isVerified;
  final bool emailVerified;
  final bool phoneVerified;
  final bool privacyPolicyAgreed;
  final DateTime createdAt;
  final String? plainPassword;
  final String? firstName;
  final String? lastName;
  final String? referralCode;

  User({
    required this.id,
    required this.username,
    required this.displayName,
    required this.email,
    required this.userType,
    this.phoneNumber,
    this.address,
    this.dateOfBirth,
    this.profilePicture,
    this.profilePictureUrl,
    this.googleId,
    required this.isVerified,
    required this.emailVerified,
    required this.phoneVerified,
    required this.privacyPolicyAgreed,
    required this.createdAt,
    this.plainPassword,
    this.firstName,
    this.lastName,
    this.referralCode,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      displayName: json['display_name'] ?? json['username'],
      email: json['email'],
      userType: json['user_type'],
      phoneNumber: json['phone_number'],
      address: json['address'],
      dateOfBirth: json['date_of_birth'] != null ? DateTime.parse(json['date_of_birth']) : null,
      profilePicture: json['profile_picture'],
      profilePictureUrl: json['profile_picture_url'],
      googleId: json['google_id'],
      isVerified: json['is_verified'] ?? false,
      emailVerified: json['email_verified'] ?? false,
      phoneVerified: json['phone_verified'] ?? false,
      privacyPolicyAgreed: json['privacy_policy_agreed'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      plainPassword: json['plain_password'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      referralCode: json['referral_code'],
    );
  }

  // Helper to get the full profile picture URL
  String? get fullProfilePictureUrl {
     // Prioritize uploaded profile picture over Google/external URL
     if (profilePicture != null && profilePicture!.isNotEmpty) {
       if (profilePicture!.startsWith('http')) return profilePicture;
       // Assuming standard Django structure if just path
       return 'https://ezeyway.com/media/$profilePicture';
     }
     // Fall back to external URL (e.g., Google profile photo)
     if (profilePictureUrl != null && profilePictureUrl!.isNotEmpty) {
       return profilePictureUrl;
     }
     return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'email': email,
      'user_type': userType,
      'phone_number': phoneNumber,
      'address': address,
      'date_of_birth': dateOfBirth?.toIso8601String(),
      'profile_picture': profilePicture,
      'profile_picture_url': profilePictureUrl,
      'google_id': googleId,
      'is_verified': isVerified,
      'email_verified': emailVerified,
      'phone_verified': phoneVerified,
      'privacy_policy_agreed': privacyPolicyAgreed,
      'created_at': createdAt.toIso8601String(),
      'plain_password': plainPassword,
      'first_name': firstName,
      'last_name': lastName,
      'referral_code': referralCode,
    };
  }
}