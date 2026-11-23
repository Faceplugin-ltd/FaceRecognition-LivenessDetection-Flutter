import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:face_recognition_sdk/face_recognition_sdk.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_settings.dart';
import 'attribute_result_screen.dart';
import 'result_screen.dart';
import 'status_card.dart';
import 'ui.dart';

/// What the live frame looks like to the coach.
enum CaptureStatus {
  ok('Face looks good', true),
  noFace('No face found', false),
  manyFaces('More than one face', false),
  moveCloser('Move closer', false),
  tooDark('Too dark', false),
  identifying('Identifying…', true),
  attributes('Reading attributes…', true);

  const CaptureStatus(this.text, this.good);

  final String text;
  final bool good;
}

/// Live camera identify with a status chip, shutter, gallery pick and Auto.
/// Attribute uses the same screen — [attributeMode] only changes what the shutter runs.
class IdentifyScreen extends StatefulWidget {
  const IdentifyScreen({super.key, this.attributeMode = false});

  final bool attributeMode;

  /// Auto fires once one good face has stayed in place this long.
  static const Duration autoStable = Duration(milliseconds: 300);

  /// Leaves room for the UI to breathe between detections on the preview stream.
  static const Duration frameInterval = Duration(milliseconds: 250);

  @override
  State<IdentifyScreen> createState() => _IdentifyScreenState();
}

class _IdentifyScreenState extends State<IdentifyScreen>
    with WidgetsBindingObserver {
  final AppSettings _settings = AppSettings.instance;
  final FaceEngine _engine = FaceEngine.instance;

  CameraController? _controller;
  FaceGallery? _gallery;
  List<CameraDescription> _cameras = const [];
  bool _frontCamera = true;
  bool _permissionDenied = false;
  bool _starting = false;
  bool _busy = false;
  bool _frameBusy = false;

  CaptureStatus _status = CaptureStatus.noFace;
  String? _lastUri;
  DateTime? _stableSince;
  Offset? _lastCenter;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _galleryCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine.addListener(_onEngine);
    _settings.addListener(_onSettings);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.removeListener(_onEngine);
    _settings.removeListener(_onSettings);
    _gallery?.removeListener(_refreshCount);
    _stopCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  void _onEngine() {
    if (mounted) setState(() {});
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    final gallery = await FaceGallery.open();
    if (!mounted) return;
    _gallery = gallery..addListener(_refreshCount);
    await _refreshCount();
    await _requestCamera();
  }

  Future<void> _refreshCount() async {
    final n = await _gallery?.count() ?? 0;
    if (mounted) setState(() => _galleryCount = n);
  }

  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _permissionDenied = true);
      return;
    }
    setState(() => _permissionDenied = false);
    await _startCamera();
  }

  Future<void> _startCamera() async {
    if (_starting || _controller != null || _permissionDenied) return;
    _starting = true;
    try {
      _cameras = _cameras.isEmpty ? await availableCameras() : _cameras;
      if (_cameras.isEmpty) return;
      final wanted = _frontCamera
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final description = _cameras.firstWhere(
        (c) => c.lensDirection == wanted,
        orElse: () => _cameras.first,
      );
      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.startImageStream(_onFrame);
    } catch (e) {
      if (mounted) _snack('The camera is unavailable. $e');
    } finally {
      _starting = false;
    }
  }

  Future<void> _stopCamera() async {
    final controller = _controller;
    _controller = null;
    // Reset the coach with the camera. Leaving the last frame's status and stability behind
    // meant re-entering the tab showed the previous visit's reading over a dead preview.
    _stableSince = null;
    _lastUri = null;
    if (mounted) setState(() => _status = CaptureStatus.noFace);
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
    await controller.dispose();
  }

  Future<void> _switchCamera() async {
    _frontCamera = !_frontCamera;
    await _stopCamera();
    if (mounted) setState(() {});
    await _startCamera();
  }

  // ---- the live coach ----

  void _onFrame(CameraImage image) {
    // The coach keeps reading frames while a search runs. Dropping them until the engine
    // came back froze the boxes and the status on whatever the last frame had said, which
    // is what made the camera look stopped. `_engine.run` already serialises the calls.
    if (_frameBusy || !_engine.isReady) return;
    final now = DateTime.now();
    if (now.difference(_lastFrameAt) < IdentifyScreen.frameInterval) return;
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

      final faces = await _engine.run(() => faceDetection(
            uri,
            const FaceDetectionParam(checkPose: true, checkLandmarks: true),
          ));
      if (!mounted) return;

      final width = live.width.toDouble();
      final height = live.height.toDouble();
      final status = _statusFor(faces, width, height);
      _lastUri = uri;
      _trackStability(faces, status, width, height);

      final fire = status == CaptureStatus.ok &&
          _settings.autoCapture &&
          _stableSince != null &&
          DateTime.now().difference(_stableSince!) >= IdentifyScreen.autoStable;

      // While a search is running the status says so; everything else keeps moving.
      if (mounted && !_busy) setState(() => _status = status);
      if (fire && !_busy) {
        _stableSince = null;
        await _run(uri);
      }
    } catch (_) {
      // A dropped frame is not worth reporting; the next one will do.
    }
  }

  CaptureStatus _statusFor(List<FaceBox> faces, double width, double height) {
    if (faces.isEmpty) return CaptureStatus.noFace;
    if (faces.length > 1) return CaptureStatus.manyFaces;
    final face = faces.first;
    if (width > 0 && face.width < width * 0.28) return CaptureStatus.moveCloser;
    final luminance = face.faceLuminance;
    if (luminance != null && luminance > 0.001 && luminance <= 0.25) {
      return CaptureStatus.tooDark;
    }
    return CaptureStatus.ok;
  }

  /// Auto only fires once the face has held still, so it does not shoot mid-movement.
  void _trackStability(
    List<FaceBox> faces,
    CaptureStatus status,
    double width,
    double height,
  ) {
    if (status != CaptureStatus.ok || faces.isEmpty) {
      _stableSince = null;
      _lastCenter = null;
      return;
    }
    final box = faces.first;
    final center = Offset((box.x1 + box.x2) / 2, (box.y1 + box.y2) / 2);
    final previous = _lastCenter;
    final moved = previous == null ||
        (previous.dx - center.dx).abs() > width * 0.06 ||
        (previous.dy - center.dy).abs() > height * 0.06;
    if (moved || _stableSince == null) _stableSince = DateTime.now();
    _lastCenter = center;
  }

  // ---- identify / attributes ----

  Future<void> _captureNow() async {
    if (_busy) return;
    final uri = _lastUri;
    if (uri == null || _status == CaptureStatus.noFace) {
      _snack(FaceGallery.noFace);
      return;
    }
    await _run(uri);
  }

  Future<void> _pickPhoto() async {
    if (_busy) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    await _run(picked.path);
  }

  Future<void> _run(String uri) async {
    final gallery = _gallery;
    if (gallery == null) return;
    setState(() {
      _busy = true;
      _status = widget.attributeMode
          ? CaptureStatus.attributes
          : CaptureStatus.identifying;
    });
    try {
      if (widget.attributeMode) {
        final result =
            await gallery.attributes(uri, limits: _settings.limits);
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AttributeResultScreen(result: result),
          ),
        );
        return;
      }

      final outcome = await gallery.identify(
        uri,
        _settings.limits,
        livenessOn: _settings.liveness,
      );
      if (!mounted) return;
      switch (outcome) {
        case IdentifyDone(:final result):
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
          );
        case IdentifyRejected(:final reason, :final report):
          if (report == null) {
            _snack(reason);
          } else {
            // Stays busy while the status is open, so auto does not fire behind it.
            await StatusCard.showAsDialog(
              context,
              title: 'Identify stopped',
              reason: reason,
              report: report,
            );
          }
      }
    } finally {
      _stableSince = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _status = CaptureStatus.noFace;
        });
      }
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 4)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (ready)
          CoverCameraPreview(controller: controller)
        else
          Container(color: Colors.black),
        _scrim(),
        SafeArea(
          child: Column(
            children: [
              _topBar(),
              if (_message != null) _messageBox(_message!),
              const Spacer(),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              _bottomBar(),
            ],
          ),
        ),
      ],
    );
  }

  /// The one thing standing between the user and a working camera, if anything is.
  String? get _message {
    if (_permissionDenied) {
      return 'This demo needs the camera to find a face.';
    }
    if (!_engine.isReady) return _engine.stateMessage;
    return null;
  }

  Widget _scrim() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent, Colors.black54],
            stops: [0, 0.4, 1],
          ),
        ),
      );

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Text(
            widget.attributeMode ? 'Attribute' : 'Identify',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Pill(Ui.facesCount(_galleryCount), color: Colors.black45),
          const Spacer(),
          if (!widget.attributeMode)
            Pill(
              'Threshold ${Ui.score(_settings.threshold)}',
              color: Colors.black45,
            ),
        ],
      ),
    );
  }

  Widget _messageBox(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            if (_permissionDenied)
              TextButton(
                onPressed: _requestCamera,
                child: const Text('Allow camera'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        children: [
          Pill(
            _status.text,
            color: _status.good ? Ui.statusMatch : Colors.black54,
            fontSize: 13,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _roundButton(
                icon: Icons.photo_library_outlined,
                tooltip: 'Pick a photo',
                onPressed: _busy ? null : _pickPhoto,
              ),
              _shutter(),
              _roundButton(
                icon: Icons.cameraswitch_outlined,
                tooltip: 'Switch camera',
                onPressed: _busy ? null : _switchCamera,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Auto', style: TextStyle(color: Colors.white)),
              Switch(
                value: _settings.autoCapture,
                onChanged: (on) {
                  _settings.autoCapture = on;
                  _stableSince = null;
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shutter() {
    final enabled = _engine.isReady && !_busy;
    return GestureDetector(
      onTap: enabled ? _captureNow : null,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? Colors.white : Colors.white38,
          border: Border.all(color: Colors.white70, width: 4),
        ),
        child: Icon(
          widget.attributeMode ? Icons.auto_awesome : Icons.search,
          size: 30,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(backgroundColor: Colors.white24),
      icon: Icon(icon, color: Colors.white),
    );
  }
}
