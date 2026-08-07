import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Verilen [imageUrl]'yi tam ekranda gösterir. Herhangi bir yere tıklamak
/// veya geri tuşuna basmak kapatır. Kaydırma/zoom için [InteractiveViewer].
void showFullscreenImage(BuildContext context, String imageUrl) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    barrierDismissible: true,
    builder: (ctx) => _FullscreenImageDialog(imageUrl: imageUrl),
  );
}

class _FullscreenImageDialog extends StatelessWidget {
  final String imageUrl;
  const _FullscreenImageDialog({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Material(
          color: Colors.black,
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.image_not_supported,
                        color: Colors.white38,
                        size: 64,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
