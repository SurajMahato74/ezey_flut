import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PermissionHelper {
  static Future<bool> requestImagePermissions(BuildContext context) async {
    try {
      // Try to pick an image to test permissions
      final ImagePicker picker = ImagePicker();
      final XFile? testImage = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1,
        maxHeight: 1,
      );
      
      // If we got here without error, permissions are granted
      return true;
    } catch (e) {
      // Show permission dialog
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
              'This app needs access to your photos to upload images. Please grant permission in your device settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return false;
    }
  }
}