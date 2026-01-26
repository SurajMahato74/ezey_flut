// lib/widgets/safe_network_image.dart
import 'package:flutter/material.dart';

class SafeNetworkImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty || imageUrl.contains('placeholder')) {
      return _buildPlaceholder();
    }

    // On Web, NetworkImage can fail due to CORS (403/Forbidden) if Using CanvasKit
    // For now, we use the standard Image.network with a robust error builder
    // In a real production app for Web, you might use a proxy or HTML renderer.
    
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholder ?? _buildSkeletonLoader();
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Image load failed: $imageUrl - Error: $error');
        return errorWidget ?? _buildErrorPlaceholder();
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.white10,
      child: const Icon(Icons.image, color: Colors.white24, size: 24),
    );
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.white10,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_rounded, color: Colors.red.withOpacity(0.5), size: 24),
          if (height != null && height! > 50)
            const Padding(
              padding: EdgeInsets.only(top: 4.0),
              child: Text(
                '403 Forbidden',
                style: TextStyle(color: Colors.white24, fontSize: 8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
