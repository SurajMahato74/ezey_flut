// lib/widgets/vendor_page_controller.dart
import 'package:flutter/material.dart';

/// InheritedWidget to provide PageController to vendor screens
class VendorPageController extends InheritedWidget {
  final PageController pageController;

  const VendorPageController({
    super.key,
    required this.pageController,
    required super.child,
  });

  static PageController? of(BuildContext context) {
    final VendorPageController? result = 
        context.dependOnInheritedWidgetOfExactType<VendorPageController>();
    return result?.pageController;
  }

  @override
  bool updateShouldNotify(VendorPageController oldWidget) {
    return pageController != oldWidget.pageController;
  }
}