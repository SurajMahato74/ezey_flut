import 'package:flutter/material.dart';

class NavigationService extends ChangeNotifier {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  String _currentPage = 'home';
  dynamic _categoryId;
  
  String get currentPage => _currentPage;
  dynamic get categoryId => _categoryId;

  void setCurrentPage(String page) {
    if (_currentPage != page) {
      _currentPage = page;
      _categoryId = null;
      notifyListeners();
    }
  }

  void navigateToCategory(dynamic categoryId) {
    _currentPage = 'category';
    _categoryId = categoryId;
    notifyListeners();
  }

  void restoreCurrentPage(String page) {
    _currentPage = page;
  }
}