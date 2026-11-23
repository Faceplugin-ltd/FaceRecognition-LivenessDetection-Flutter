/// FacePlugin Face Recognition SDK for Flutter.
///
/// Public entry point: detection, template extraction, VideoWorker tracking,
/// live-frame ingestion, and a ready-made [FaceCapture] UI widget.
library;

export 'src/face_box.dart';
export 'src/models.dart';
export 'src/live_frame.dart';
export 'src/channel.dart';
export 'src/video_worker.dart';
export 'src/capture_logic.dart';
export 'src/capture_overlay.dart';
export 'src/cover_camera_preview.dart';
export 'src/face_capture.dart';
export 'src/identify_session.dart';
export 'src/result_details.dart';
export 'license_status.dart';

// The app layer: the same engine, gallery, thresholds and call reports as the
// Android and iOS apps. Depend on these instead of rebuilding them per app.
export 'kit/call_report.dart';
export 'kit/face_engine.dart';
export 'kit/face_gallery.dart';
export 'kit/face_limits.dart';
export 'kit/gallery_db.dart' show GalleryTemplate;
export 'kit/gallery_types.dart';
