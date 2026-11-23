import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:face_recognition_sdk/face_recognition_sdk.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';

/// Liveness on its own: the camera, a box per face and that face's liveness score. There is
/// nothing to press — no shutter, no gallery, no result screen. It is the plainest possible
/// demonstration that the engine tells a live face from a photo of one.
class LivenessScreen extends StatefulWidget {
  const LivenessScreen({super.key});

  /// Leaves room for the UI to breathe between detections on the preview stream.
  static const frameInterval = Duration(milliseconds: 120);

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends State<LivenessScreen>
    with WidgetsBindingObserver {
  final _engine = FaceEngine.instance;
  final _settings = AppSettings.instance;

  CameraController? _controller;
  bool _frameBusy = false;
  bool _frontCamera = true;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);

  List<FaceBox> _faces = const [];
  Size _frame = Size.zero;
  String _hint = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      unawaited(_stop());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    if (_controller != null) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _hint = 'Camera unavailable');
        return;
      }
      final wanted = _frontCamera
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == wanted,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.startImageStream(_onFrame);
      setState(() {
        _controller = controller;
        _hint = '';
      });
    } catch (_) {
      if (mounted) setState(() => _hint = 'Camera unavailable');
    }
  }

  Future<void> _stop() async {
    final controller = _controller;
    _controller = null;
    // Drop the last frame's boxes straight away, so re-entering the tab never shows the
    // faces from the previous visit sitting over a camera that has not started yet.
    if (mounted) setState(() => _faces = const []);
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Already stopped.
    }
    await controller.dispose();
    if (mounted) setState(() => _faces = const []);
  }

  Future<void> _flip() async {
    _frontCamera = !_frontCamera;
    await _stop();
    await _start();
  }

  /// Whether the overlay has to be flipped to sit on the preview.
  ///
  /// The front preview is mirrored on Android but not on iOS, so flipping on both put every
  /// box on the wrong side of an iPhone screen.
  bool get _overlayMirrored => _frontCamera && !Platform.isIOS;

  void _onFrame(CameraImage image) {
    if (_frameBusy || !_engine.isReady) return;
    final now = DateTime.now();
    if (now.difference(_lastFrameAt) < LivenessScreen.frameInterval) return;
    _lastFrameAt = now;
    _frameBusy = true;
    unawaited(_analyze(image).whenComplete(() => _frameBusy = false));
  }

  Future<void> _analyze(CameraImage image) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final live = await ingestCameraPreviewFrame(
        image,
        sensorOrientation: controller.description.sensorOrientation,
        frontCamera: _frontCamera,
      );
      if (!live.ingested || !mounted) return;
      final exported = await exportLastLiveFrame();
      final uri = exported.uri;
      if (uri == null || uri.isEmpty) return;

      // Liveness is the whole point of this screen, so it is the one estimator asked for.
      final faces = await _engine.run(() => faceDetection(
            uri,
            const FaceDetectionParam(checkLiveness: true, checkPose: false),
          ));
      if (!mounted) return;
      setState(() {
        _faces = faces;
        _frame = Size(live.width.toDouble(), live.height.toDouble());
        _hint = faces.isEmpty ? 'No face' : '';
      });
    } catch (_) {
      // A dropped frame is not worth reporting; the next one will do.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.previewSize?.height ?? 1,
                height: controller.value.previewSize?.width ?? 1,
                child: CameraPreview(controller),
              ),
            ),
          CustomPaint(
            painter: _LivenessPainter(
              faces: _faces,
              frame: _frame,
              mirrored: _overlayMirrored,
              limits: _settings.limits,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Text(
                      'Liveness',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cameraswitch_outlined),
                    color: Colors.white,
                    onPressed: _flip,
                  ),
                ],
              ),
            ),
          ),
          if (_hint.isNotEmpty)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _hint,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Face boxes with their liveness score.
///
/// The engine works on a frame that is scaled down and, on the front camera, not mirrored,
/// while the preview fills the view and is mirrored. Boxes are mapped with the same
/// cover maths the preview uses, so they sit on the face rather than near it.
class _LivenessPainter extends CustomPainter {
  _LivenessPainter({
    required this.faces,
    required this.frame,
    required this.mirrored,
    required this.limits,
  });

  final List<FaceBox> faces;
  final Size frame;
  final bool mirrored;
  final FaceLimits limits;

  static const _live = Color(0xFF2EE6A6);
  static const _fake = Color(0xFFFF6B6B);

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.width <= 0 || frame.height <= 0 || faces.isEmpty) return;
    final scale = (size.width / frame.width) > (size.height / frame.height)
        ? size.width / frame.width
        : size.height / frame.height;
    final dx = (size.width - frame.width * scale) / 2;
    final dy = (size.height - frame.height * scale) / 2;

    for (final face in faces) {
      final isLive = limits.isLive(face.liveness);
      final colour = isLive ? _live : _fake;

      var left = face.x1 * scale + dx;
      var right = face.x2 * scale + dx;
      final top = face.y1 * scale + dy;
      final bottom = face.y2 * scale + dy;
      if (mirrored) {
        final mirroredLeft = size.width - right;
        right = size.width - left;
        left = mirroredLeft;
      }

      final rect = Rect.fromLTRB(left, top, right, bottom);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(9)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = colour,
      );

      final score = (face.liveness ?? 0).toStringAsFixed(2);
      final painter = TextPainter(
        text: TextSpan(
          text: '${isLive ? 'Live' : 'Fake'}  $score',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelTop = (top - painter.height - 10).clamp(0.0, size.height);
      final label = Rect.fromLTWH(
        left,
        labelTop,
        painter.width + 14,
        painter.height + 6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(label, const Radius.circular(6)),
        Paint()..color = colour,
      );
      painter.paint(canvas, Offset(left + 7, labelTop + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _LivenessPainter old) =>
      old.faces != faces || old.frame != frame || old.mirrored != mirrored;
}
