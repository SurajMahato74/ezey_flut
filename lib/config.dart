class Config {
  static const String baseUrl = 'https://ezeyway.com/api';
  static const String mediaUrl = 'https://ezeyway.com/media';

  // Agora Configuration
  static const String agoraAppId = '51aafec601fa444581210f9fac99a73a';
  static const String agoraAppCertificate = '0c85813471a1416cadab8a3d77d4fc7f';

  // Call Configuration
  static const int callTimeoutSeconds = 60; // Increased timeout for better UX
  static const int callRingingTimeoutSeconds = 45; // Time before showing missed call

  //for local testing
  static const String localBaseUrl = 'http://127.0.0.1:8000/api';
//static const String loginEndpoint = '$localBaseUrl/login/';

  static const String loginEndpoint = '$baseUrl/login/';
  static const String logoutEndpoint = '$baseUrl/logout/'; 
  static const String sendOtpEndpoint = '$baseUrl/send-otp/';
  static const String verifyOtpEndpoint = '$baseUrl/verify-otp/';
  static const String agreePrivacyPolicyEndpoint = '$baseUrl/agree-privacy-policy/';
  static const String profileEndpoint = '$baseUrl/profile/';
  static const String deliveryRadiusEndpoint = '$baseUrl/delivery-radius/';
  static const String registerEndpoint = '$baseUrl/register/';                    
  static const String vendorProfilesEndpoint = '$baseUrl/vendor-profiles/';       
  static const String vendorProfileDetailEndpoint = '$baseUrl/vendor-profiles';    
  static const String uploadPictureEndpoint = '$baseUrl/profile/upload-picture/';
  static const String completeOnboardingEndpoint = '$baseUrl/complete-onboarding/';
  static const String categoriesEndpoint = '$baseUrl/categories/';
  static const String slidersEndpoint = '$baseUrl/sliders/';
  static const String searchProductsEndpoint = '$baseUrl/search/products/';
  static const String productsEndpoint = '$baseUrl/products/';
  static const String productReviewsEndpoint = '$baseUrl/products/';
  static const String changePasswordEndpoint = '$baseUrl/change-password/simple/';

  static const String favoritesEndpoint = '$baseUrl/favorites/';
  static const String toggleFavoriteEndpoint = '$baseUrl/favorites/toggle/';
  static const String notificationsEndpoint = '$baseUrl/vendor-notifications/';
  static const String markAllNotificationsReadEndpoint = '$baseUrl/notifications/mark-all-read/';
  static const String markNotificationReadEndpoint = '$baseUrl/notifications/'; // Append /{id}/read/
  static const String vendorWalletEndpoint = '$baseUrl/vendor-wallet/';
  static const String walletTransactionsEndpoint = '$baseUrl/wallet/transactions/';
  static const String createCallEndpoint = '$baseUrl/messaging/calls/initiate/';
  static const String callStatusEndpoint = '$baseUrl/messaging/calls/'; // Append {call_id}/status/
  static const String syncCallStatusEndpoint = '$baseUrl/messaging/calls/'; // Append {call_id}/sync/
  static const String reconnectCallEndpoint = '$baseUrl/messaging/calls/'; // Append {call_id}/reconnect/
  static const String acceptCallEndpoint = '$baseUrl/messaging/calls/'; // Append {call_id}/accept/
  static const String rejectCallEndpoint = '$baseUrl/messaging/calls/'; // Append {call_id}/reject/
  static const String endCallEndpoint = '$baseUrl/messaging/calls/'; // Append {call_id}/end/
  static const String pendingCallsEndpoint = '$baseUrl/messaging/calls/pending/';
  static const String agoraTokenEndpoint = '$baseUrl/agora-token/';
  static const String updateFcmTokenEndpoint = '$baseUrl/update-fcm-token/';
}