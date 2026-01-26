// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config.dart';
import '../models/login_response.dart';
import 'package:image_picker/image_picker.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // 1. LOGIN – Now SMART: returns Map OR LoginResponse safely
  Future<dynamic> login(String email, String password) async {
    final url = Uri.parse(Config.loginEndpoint);
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      // Full login success → has token
      if (data['token'] != null) {
        return LoginResponse.fromJson(data);
      }
      // Email not verified → needs OTP
      else if (data['needs_verification'] == true) {
        return data; // {needs_verification: true, user_id: 54, message: "..."}
      }
      // Any other 200 case
      else {
        return data;
      }
    } else {
      String errorMessage = 'Login failed';
      if (data is Map) {
        if (data.containsKey('detail')) {
          errorMessage = data['detail'];
        } else if (data.containsKey('message')) {
          errorMessage = data['message'];
        } else if (data.containsKey('error')) {
          errorMessage = data['error'];
        } else if (data.containsKey('non_field_errors')) {
          final errs = data['non_field_errors'];
          errorMessage = errs is List ? errs.first.toString() : errs.toString();
        } else {
          // Iterate keys to find the first validation error
          // e.g. {"username": ["User not found"], "password": ["Invalid"]}
          for (var key in data.keys) {
            final value = data[key];
            if (value is List && value.isNotEmpty) {
              errorMessage = value.first.toString();
              break; 
            } else if (value is String) {
              errorMessage = value;
              break;
            }
          }
        }
      }
      throw Exception(errorMessage);
    }
  }

  // 2. REGISTER
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String userType,
    String? phoneNumber,
    bool privacyPolicyAgreed = false,
  }) async {
    final url = Uri.parse(Config.registerEndpoint);
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
        'user_type': userType,
        if (phoneNumber != null && phoneNumber.isNotEmpty) 'phone_number': phoneNumber,
        'privacy_policy_agreed': privacyPolicyAgreed,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 201 || response.statusCode == 200) {
      return data;
    } else {
      String error = 'Registration failed';
      if (data is Map && data.isNotEmpty) {
        final firstError = data.values.first;
        error = firstError is List ? firstError[0] : firstError.toString();
      }
      throw Exception(error);
    }
  }

  // 3. SEND OTP
  Future<void> sendOtp(String email) async {
    final url = Uri.parse(Config.sendOtpEndpoint);
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['error'] ?? 'Failed to send OTP');
    }
  }

  // 4. VERIFY OTP
  Future<LoginResponse> verifyOtp(String email, String otp) async {
    final url = Uri.parse(Config.verifyOtpEndpoint);
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'otp': otp}),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      // Privacy agreement needed - automatically agree
      if (data['needs_privacy_agreement'] == true) {
        final userId = int.tryParse(data['user_id'].toString()) ?? 0;
        return await agreeToPrivacyPolicy(userId);
      }
      return LoginResponse.fromJson(data);
    } else {
      throw Exception(data['error'] ?? 'Invalid or expired OTP');
    }
  }

  // 5. AGREE TO PRIVACY POLICY
  Future<LoginResponse> agreeToPrivacyPolicy(int userId) async {
    final url = Uri.parse(Config.agreePrivacyPolicyEndpoint);
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'agreed': true}),
    );

    if (response.statusCode == 200) {
      return LoginResponse.fromJson(jsonDecode(response.body));
    } else {
      final data = jsonDecode(response.body);
      throw Exception(data['error'] ?? 'Failed to agree to privacy policy');
    }
  }

  // 6. CREATE VENDOR PROFILE
  Future<Map<String, dynamic>> createVendorProfile({
    required String token,
    required Map<String, dynamic> profileData,
    List<http.MultipartFile>? shopImages,
    List<http.MultipartFile>? documents,
  }) async {
    final url = Uri.parse(Config.vendorProfilesEndpoint);
    var request = http.MultipartRequest('POST', url);
    request.headers['Authorization'] = 'Token $token';

    profileData.forEach((key, value) {
      if (value != null) request.fields[key] = value.toString();
    });

    if (shopImages != null) {
      for (var img in shopImages) {
        request.files.add(img);
      }
    }
    if (documents != null) {
      for (var doc in documents) {
        request.files.add(doc);
      }
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final data = jsonDecode(response.body);

    if (response.statusCode == 201) {
      return data;
    } else {
      String error = 'Failed to create profile';
      if (data is Map && data.isNotEmpty) {
        final first = data.values.first;
        error = first is List ? first[0] : first.toString();
      }
      throw Exception(error);
    }
  }

  // 7. GET VENDOR PROFILE STATUS
  Future<Map<String, dynamic>> getVendorProfileStatus(String token) async {
    final url = Uri.parse(Config.vendorProfilesEndpoint);
    final response = await http.get(url, headers: {
      'Authorization': 'Token $token',
      'Content-Type': 'application/json',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = data['results'] as List<dynamic>;
      if (list.isEmpty) return {'exists': false};
      final profile = list[0];
      return {
        'exists': true,
        'id': profile['id'],
        'vendor_id': profile['id'],
        'is_approved': profile['is_approved'] ?? false,
        'is_rejected': profile['is_rejected'] ?? false,
        'rejection_reason': profile['rejection_reason'],
        'shop_name': profile['shop_name'],
        'is_active': profile['is_active'] ?? false,
      };
    }
    return {'exists': false};
  }

  // 8. GET USER PROFILE
  Future<Map<String, dynamic>> getProfile(String token) async {
    final response = await http.get(
      Uri.parse(Config.profileEndpoint),
      headers: {'Authorization': 'Token $token'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load profile');
  }

  // 9. GET DELIVERY RADIUS
  Future<Map<String, dynamic>> getDeliveryRadius(String token) async {
    final response = await http.get(
      Uri.parse(Config.deliveryRadiusEndpoint),
      headers: {'Authorization': 'Token $token'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load delivery radius');
  }


  

  Future<Map<String, dynamic>> completeVendorOnboarding({
    required String token,
    required Map<String, dynamic> data,
    List<http.MultipartFile>? shopImages,
    http.MultipartFile? panDoc,
    http.MultipartFile? citizenshipFront,
    http.MultipartFile? citizenshipBack,
  }) async {
    final url = Uri.parse(Config.completeOnboardingEndpoint);
    var request = http.MultipartRequest('POST', url);
    request.headers['Authorization'] = 'Token $token';

    // Add text fields
    data.forEach((key, value) {
      if (value != null) {
        if (value is List) {
          request.fields[key] = jsonEncode(value);
        } else {
          request.fields[key] = value.toString();
        }
      }
    });

    // Add files
    if (shopImages != null) {
      for (var i = 0; i < shopImages.length; i++) {
        request.files.add(shopImages[i]);
      }
    }
    if (panDoc != null) request.files.add(panDoc);
    if (citizenshipFront != null) request.files.add(citizenshipFront);
    if (citizenshipBack != null) request.files.add(citizenshipBack);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final responseData = jsonDecode(response.body);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return responseData;
    } else {
      String error = 'Failed to complete onboarding';
      if (responseData is Map && responseData.isNotEmpty) {
        if (responseData.containsKey('error')) {
          error = responseData['error'].toString();
        } else {
          // Show field name with error
          final firstKey = responseData.keys.first;
          final firstValue = responseData[firstKey];
          final errorMsg = firstValue is List ? firstValue[0] : firstValue.toString();
          error = '$firstKey: $errorMsg';
        }
      }
      throw Exception(error);
    }
  }

  // 11. LOGOUT
  Future<bool> logout(String token) async {
    try {
      await http.post(
        Uri.parse(Config.logoutEndpoint),
        headers: {'Authorization': 'Token $token'},
      );
      return true;
    } catch (e) {
      return true; // Always allow local logout
    }
  }

  // 12. GET CATEGORIES
  Future<List<Map<String, dynamic>>> getCategories() async {
    final response = await http.get(Uri.parse(Config.categoriesEndpoint));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['categories'] is List) {
        return List<Map<String, dynamic>>.from(data['categories']);
      }
      throw Exception('Invalid response format');
    } else {
      throw Exception('Failed to load categories');
    }
  }

  // 13. GET SLIDERS
  Future<List<Map<String, dynamic>>> getSliders(String userType) async {
    final url = Uri.parse('${Config.slidersEndpoint}?user_type=$userType');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['sliders'] is List) {
        return List<Map<String, dynamic>>.from(data['sliders']);
      }
      throw Exception('Invalid response format');
    } else {
      throw Exception('Failed to load sliders');
    }
  }

  // 14. GET GLOBAL DELIVERY RADIUS (no auth required)
  Future<double> getGlobalDeliveryRadius() async {
    final response = await http.get(Uri.parse(Config.deliveryRadiusEndpoint));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['delivery_radius'] != null) {
        return double.tryParse(data['delivery_radius'].toString()) ?? 1000.0;
      }
      throw Exception('Invalid response format');
    } else {
      throw Exception('Failed to load delivery radius');
    }
  }

  // 15. SEARCH PRODUCTS (updated to match React sample)
  Future<Map<String, dynamic>> searchProducts({
    double? latitude,
    double? longitude,
    int pageSize = 20,
    int page = 1,
    String? search,
    String? sort,
    List<String>? categories,
  }) async {
    final queryParams = {
      'page_size': pageSize.toString(),
      'page': page.toString(),
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
      if (sort != null && sort.isNotEmpty) 'sort': sort,
      if (categories != null && categories.isNotEmpty) 'categories': categories.join(','),
    };

    final uri = Uri.parse(Config.searchProductsEndpoint).replace(queryParameters: queryParams);
    final headers = {'ngrok-skip-browser-warning': 'true'};
    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data; // Return the full response as in React sample
    } else {
      throw Exception('Failed to load products');
    }
  }

  // 16. SEARCH VENDORS
  Future<Map<String, dynamic>> searchVendors({
    double? latitude,
    double? longitude,
    int pageSize = 20,
    int page = 1,
    String? search,
    String? sort,
    List<String>? categories,
  }) async {
    final queryParams = {
      'page_size': pageSize.toString(),
      'page': page.toString(),
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
      if (sort != null && sort.isNotEmpty) 'sort': sort,
      if (categories != null && categories.isNotEmpty) 'categories': categories.join(','),
    };

    final uri = Uri.parse('${Config.baseUrl}/search/vendors/').replace(queryParameters: queryParams);
    final headers = {'ngrok-skip-browser-warning': 'true'};
    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data;
    } else {
      throw Exception('Failed to load vendors');
    }
  }

  // 16. GET PRODUCT DETAILS
  Future<Map<String, dynamic>> getProductDetails(int productId, {String? token}) async {
    final headers = <String, String>{};
    if (token != null) {
      headers['Authorization'] = 'Token $token';
    }
    final response = await http.get(
      Uri.parse('${Config.productsEndpoint}$productId/'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load product details');
    }
  }

  // 17. GET PRODUCT REVIEWS
  Future<Map<String, dynamic>> getProductReviews(int productId) async {
    final response = await http.get(Uri.parse('${Config.productReviewsEndpoint}$productId/reviews/'));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load product reviews');
    }
  }

  // 17. GET VENDOR DETAILS
  Future<Map<String, dynamic>> getVendorDetails(int vendorId) async {
    final response = await http.get(Uri.parse('${Config.baseUrl}/vendors/$vendorId/'));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load vendor details');
    }
  }

  // 18. TOGGLE VENDOR STATUS
  Future<Map<String, dynamic>> toggleVendorStatus(String token, bool isActive) async {
    // First get vendor profile to get the vendor ID
    final vendorProfile = await getVendorProfileStatus(token);
    if (!vendorProfile['exists']) {
      throw Exception('Vendor profile not found');
    }
    
    // Extract vendor ID from the profile data
    final vendorId = vendorProfile['id'] ?? vendorProfile['vendor_id'];
    if (vendorId == null) {
      throw Exception('Vendor ID not found');
    }
    
    final url = Uri.parse('${Config.baseUrl}/vendor-profiles/$vendorId/toggle-status/');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode({'is_active': isActive}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorData = jsonDecode(response.body);
      final errorMessage = errorData['error'] ?? 'Failed to toggle vendor status';
      throw Exception(errorMessage);
    }
  }

  // 19. GET VENDOR STATUS
  Future<Map<String, dynamic>> getVendorStatus(String token) async {
    // Use the same method as getVendorProfileStatus since they return the same data
    return await getVendorProfileStatus(token);
  }

  // 19.5 GET VENDOR WALLET
  Future<Map<String, dynamic>> getVendorWallet(String token) async {
    final url = Uri.parse(Config.vendorWalletEndpoint);
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch vendor wallet data');
    }
  }

Future<Map<String, dynamic>> getWalletTransactions(
  String token, {
  String? dateFrom,
  String? dateTo,
  int page = 1,
  int pageSize = 20,
}) async {
  final Map<String, String> queryParams = {
    'page': page.toString(),
    'page_size': pageSize.toString(),
  };

  // ✅ REQUIRED: tell backend to use custom date range
  if (dateFrom != null && dateTo != null) {
    queryParams['date_filter'] = 'custom';
    queryParams['date_from'] = dateFrom;
    queryParams['date_to'] = dateTo;
  }

  final uri = Uri.parse(Config.walletTransactionsEndpoint)
      .replace(queryParameters: queryParams);

  final response = await http.get(
    uri,
    headers: {
      'Authorization': 'Token $token',
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    },
  );

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception('Failed to fetch wallet transactions');
  }
}


  // 20. TOGGLE FAVORITE
  Future<Map<String, dynamic>> toggleFavorite(String token, int productId) async {
    final url = Uri.parse(Config.toggleFavoriteEndpoint);
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode({'product_id': productId}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to toggle favorite');
    }
  }

  // 21. GET FAVORITES
  Future<dynamic> getFavorites(String token) async {
    final url = Uri.parse(Config.favoritesEndpoint);
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Token $token',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get favorites');
    }
  }

  // 22. ADD TO CART
  Future<Map<String, dynamic>> addToCart(String token, int productId, int quantity) async {
    final url = Uri.parse('${Config.baseUrl}/cart/add/');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode({'product_id': productId, 'quantity': quantity}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to add to cart');
    }
  }

  // 22.1. UPDATE CART ITEM QUANTITY
  Future<Map<String, dynamic>> updateCartItem(String token, int itemId, int quantity) async {
    final url = Uri.parse('${Config.baseUrl}/cart/items/$itemId/update/');
    final response = await http.put(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode({'quantity': quantity}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update cart item');
    }
  }

  // 22.2. REMOVE CART ITEM
  Future<Map<String, dynamic>> removeCartItem(String token, int itemId) async {
    final url = Uri.parse('${Config.baseUrl}/cart/items/$itemId/remove/');
    final response = await http.delete(
      url,
      headers: {
        'Authorization': 'Token $token',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to remove cart item');
    }
  }

  // 23. UPDATE PROFILE
  Future<Map<String, dynamic>> updateProfile(String token, Map<String, dynamic> data) async {
    final url = Uri.parse(Config.profileEndpoint);
    final response = await http.patch(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(data),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final data = jsonDecode(response.body);
      String error = 'Failed to update profile';
      if (data is Map && data.containsKey('detail')) {
        error = data['detail'];
      }
      throw Exception(error);
    }
  }

  // 24. UPLOAD PROFILE PICTURE
  Future<Map<String, dynamic>> uploadProfilePicture(String token, XFile file) async {
    final url = Uri.parse(Config.uploadPictureEndpoint); 
    
    var request = http.MultipartRequest('POST', url);
    request.headers['Authorization'] = 'Token $token';
    
    // Determine mime type
    final ext = file.name.split('.').last.toLowerCase();
    MediaType? mediaType;
    if (ext == 'jpg' || ext == 'jpeg') {
      mediaType = MediaType('image', 'jpeg');
    } else if (ext == 'png') {
      mediaType = MediaType('image', 'png');
    } else if (ext == 'gif') {
      mediaType = MediaType('image', 'gif');
    } else if (ext == 'webp') {
      mediaType = MediaType('image', 'webp');
    }

    final bytes = await file.readAsBytes();
    request.files.add(
      http.MultipartFile.fromBytes(
        'profile_picture', 
        bytes,
        filename: file.name,
        contentType: mediaType, // Explicitly set content type
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data;
    } else {
      String msg = 'Failed to upload profile picture';
      if (data is Map && data.containsKey('error')) {
        msg = data['error'];
      }
      throw Exception(msg);
    }
  }


  // 25. CHANGE PASSWORD
  Future<Map<String, dynamic>> changePassword(String token, String newPassword) async {
    final url = Uri.parse(Config.changePasswordEndpoint);
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'new_password': newPassword}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final data = jsonDecode(response.body);
      String error = 'Failed to change password';
      if (data is Map && data.containsKey('error')) {
        error = data['error'];
      } else if (data is Map && data.containsKey('detail')) {
        error = data['detail'];
      }
      throw Exception(error);
    }
  }
  // 26. NOTIFICATIONS
  Future<dynamic> getNotifications(String token, {int page = 1, String? filterRole}) async {
    final url = Uri.parse('${Config.notificationsEndpoint}?page=$page');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Token $token',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load notifications');
    }
  }

  Future<void> markNotificationRead(String token, int id) async {
    final url = Uri.parse('${Config.markNotificationReadEndpoint}$id/read/');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
      },
    );
     // If 200/204 ok
    if (response.statusCode >= 400) {
       throw Exception('Failed to mark read');
    }
  }

  Future<void> markAllNotificationsRead(String token) async {
    final url = Uri.parse(Config.markAllNotificationsReadEndpoint);
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
      },
    );
    if (response.statusCode >= 400) {
       throw Exception('Failed to mark all read');
    }
  }

  // 27. GET CONVERSATIONS
  Future<dynamic> getConversations(String token, {int page = 1, int pageSize = 20}) async {
    final url = Uri.parse('${Config.baseUrl}/messaging/conversations/?page=$page&page_size=$pageSize');
    print('🔵 Getting conversations from: $url');
    
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Token $token',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    print('🔵 Conversations response status: ${response.statusCode}');
    print('🔵 Conversations response body: ${response.body.length > 500 ? "${response.body.substring(0, 500)}..." : response.body}');

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body);
        print('✅ Successfully parsed conversations data');
        return data;
      } catch (e) {
        print('❌ Error parsing conversations JSON: $e');
        throw Exception('Failed to parse conversations response: $e');
      }
    } else {
      print('❌ Failed to load conversations: ${response.statusCode}');
      throw Exception('Failed to load conversations: ${response.statusCode} - ${response.body}');
    }
  }

  // 28. GET MESSAGES
  Future<dynamic> getMessages(String token, int conversationId, {int page = 1}) async {
    final url = Uri.parse('${Config.baseUrl}/messaging/conversations/$conversationId/messages/?page=$page');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Token $token',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load messages');
    }
  }

  // 29. SEND MESSAGE
  Future<dynamic> sendMessage(String token, int conversationId, {String? content, XFile? file}) async {
    // Valid endpoint: /messaging/messages/send/
    final url = Uri.parse('${Config.baseUrl}/messaging/messages/send/');
    var request = http.MultipartRequest('POST', url);
    request.headers['Authorization'] = 'Token $token';
    request.headers['ngrok-skip-browser-warning'] = 'true';

    // Must include conversation_id in body for this endpoint
    request.fields['conversation_id'] = conversationId.toString();

    if (content != null && content.isNotEmpty) {
      request.fields['content'] = content;
      request.fields['message_type'] = 'text';
    }

    if (file != null) {
      request.fields['message_type'] = 'image'; 
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last.toLowerCase();
      MediaType? mediaType;
       if (ext == 'jpg' || ext == 'jpeg') {
        mediaType = MediaType('image', 'jpeg');
      } else if (ext == 'png') {
        mediaType = MediaType('image', 'png');
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'file', 
          bytes,
          filename: file.name,
          contentType: mediaType,
        ),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to send message: ${response.statusCode}');
    }
  }

  // 34. SEND LOCATION MESSAGE
  Future<dynamic> sendLocationMessage(String token, int conversationId, String locationText) async {
    final url = Uri.parse('${Config.baseUrl}/messaging/messages/send/');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode({
        'conversation_id': conversationId,
        'content': locationText,
        'message_type': 'text',
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to send location message: ${response.statusCode}');
    }
  }
  // 30. CREATE SUPPORT CONVERSATION
  Future<dynamic> createSupportConversation(String token, {String? initialMessage}) async {
    final url = Uri.parse('${Config.baseUrl}/messaging/conversations/create/');
    final body = <String, String>{};
    if (initialMessage != null) {
      body['message'] = initialMessage;
    }

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create support conversation: ${response.statusCode}');
    }
  }

  // 31. GET USER PROFILE (alias for getProfile)
  Future<Map<String, dynamic>> getUserProfile(String token) async {
    return await getProfile(token);
  }

  // 32. CREATE ORDER
  Future<Map<String, dynamic>> createOrder(String token, Map<String, dynamic> orderData) async {
    final url = Uri.parse('${Config.baseUrl}/orders/create/');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode(orderData),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final data = jsonDecode(response.body);
      String error = 'Failed to create order';
      if (data is Map && data.containsKey('error')) {
        error = data['error'];
      } else if (data is Map && data.containsKey('detail')) {
        error = data['detail'];
      }
      throw Exception(error);
    }
  }

  // 33. DELETE PRODUCT IMAGE
  Future<void> deleteProductImage(String token, int productId, int imageId) async {
    final url = Uri.parse('${Config.baseUrl}/products/$productId/images/$imageId/');
    final response = await http.delete(
      url,
      headers: {
        'Authorization': 'Token $token',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      try {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? data['error'] ?? data['detail'] ?? 'Failed to delete image');
      } catch (e) {
        throw Exception('Failed to delete image: ${response.statusCode}');
      }
    }
  }

  // 34. CREATE CALL
  Future<Map<String, dynamic>> createCall(String token, int receiverId, String callType) async {
    final url = Uri.parse(Config.createCallEndpoint);
    print('🔵 Creating call at: $url');
    print('🔵 Call data: receiverId=$receiverId, callType=$callType');
    
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode({
        'recipient_id': receiverId.toString(),
        'call_type': callType,
      }),
    );

    print('🔵 Create call response status: ${response.statusCode}');
    print('🔵 Create call response body: ${response.body}');

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data;
    } else {
      final data = jsonDecode(response.body);
      throw Exception(data['error'] ?? 'Failed to create call');
    }
  }

  // 35. UPDATE FCM TOKEN
  Future<void> updateFCMToken(String token, String fcmToken) async {
    final url = Uri.parse(Config.updateFcmTokenEndpoint);
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode({'fcm_token': fcmToken}),
    );

    if (response.statusCode != 200) {
      print('❌ Failed to update FCM token: ${response.statusCode} - ${response.body}');
    } else {
      print('✅ FCM token updated successfully');
    }
  }

  // 36. ACCEPT CALL
  Future<Map<String, dynamic>> acceptCall(String token, String callId) async {
    final url = Uri.parse('${Config.baseUrl}/calls/$callId/accept/');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: jsonEncode({
        'request_fresh_token': true,
        'token_expiry_seconds': 3600
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to accept call: ${response.statusCode}');
    }
  }

  // 37. REJECT CALL
  Future<void> rejectCall(String token, String callId) async {
    final url = Uri.parse('${Config.baseUrl}/calls/$callId/reject/');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to reject call: ${response.statusCode}');
    }
  }

  // 38. END CALL
  Future<void> endCall(String token, String callId) async {
    final url = Uri.parse('${Config.baseUrl}/calls/$callId/end/');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to end call: ${response.statusCode}');
    }
  }

  // 39. RECONNECT CALL
  Future<void> reconnectCall(String token, String callId) async {
    final url = Uri.parse('${Config.baseUrl}/calls/$callId/reconnect/');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to reconnect call: ${response.statusCode}');
    }
  }

  // 40. GET CALL STATUS
  Future<Map<String, dynamic>> getCallStatus(String token, String callId) async {
    final url = Uri.parse('${Config.baseUrl}/calls/$callId/status/');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Token $token',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get call status: ${response.statusCode}');
    }
  }

 

  // 43. MARK MESSAGE AS READ
  Future<void> markMessageAsRead(String token, int messageId) async {
    final url = Uri.parse('${Config.baseUrl}/messaging/messages/$messageId/read/');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark message as read: ${response.statusCode}');
    }
  }

  // 41. GET PENDING CALLS
  Future<Map<String, dynamic>> getPendingCalls(String token) async {
    final url = Uri.parse('${Config.baseUrl}/calls/pending/');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Token $token',
        'ngrok-skip-browser-warning': 'true',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get pending calls: ${response.statusCode}');
    }
  }
}

