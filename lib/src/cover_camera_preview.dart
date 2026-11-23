import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Full-bleed camera preview (FILL_CENTER / `resizeMode="cover"`), centered on both axes.
///
/// A bare [CameraPreview] letterboxes. Scaling it from the center keeps the picture
/// under the oval instead of leaving a strip of the sensor image off to one side.
class CoverCameraPreview extends StatelessWidget {
  const CoverCameraPreview({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewW = constraints.maxWidth;
        final viewH = constraints.maxHeight;
        if (viewW <= 0 || viewH <= 0) {
          return const ColoredBox(color: Colors.black);
        }
        final viewAr = viewW / viewH;
        // aspectRatio is sensor width / height (> 1). Compare it with the view the same way.
        final previewAr = controller.value.aspectRatio;
        var scale = viewAr * previewAr;
        if (scale < 1) scale = 1 / scale;
        return ClipRect(
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: Center(child: CameraPreview(controller)),
          ),
        );
      },
    );
  }
}
