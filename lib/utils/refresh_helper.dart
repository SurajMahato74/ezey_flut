// lib/utils/refresh_helper.dart
import 'package:flutter/material.dart';
import '../services/data_preloader_service.dart';
import '../services/auth_service.dart';

class RefreshHelper {
  static Future<void> refreshAppData(BuildContext context) async {
    final preloader = DataPreloaderService();
    final authService = AuthService();
    
    try {
      // Clear existing cache
      preloader.clearCache();
      
      // Reload fresh data
      await preloader.preloadAppData();
    } catch (e) {
      // Handle silently
    }
  }
  
  static Future<void> refreshSpecificData(BuildContext context, String dataType) async {
    final preloader = DataPreloaderService();
    
    try {
      switch (dataType) {
        case 'categories':
          await preloader.refreshCategories();
          break;
        case 'products':
          await preloader.refreshProducts();
          break;
        case 'notifications':
          await preloader.refreshNotificationCount();
          break;
      }
    } catch (e) {
      // Handle silently
    }
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}