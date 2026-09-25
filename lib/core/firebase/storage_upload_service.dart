import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import '../config/app_config.dart';
import '../models/emergency_report.dart';

/// Uploads local [MediaAttachment] files captured during a report to
/// Firebase Storage and returns updated attachment objects with
/// [MediaAttachment.storagePath] and [MediaAttachment.uploaded] set.
///
/// Storage path convention:
///   aidra-media/{reportId}/{attachmentId}.{ext}
///
/// Any failure silently returns the original attachment unchanged — the
/// offline queue will retry the REST submission and the Storage upload can
/// be attempted again by the backend when the file is referenced.
class StorageUploadService {
  StorageUploadService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  static const String _bucket = 'aidra-media';

  final FirebaseStorage _storage;

  /// Uploads all non-uploaded attachments for [reportId] and returns the
  /// updated list. Already-uploaded attachments are passed through unchanged.
  Future<List<MediaAttachment>> uploadAttachments(
    String reportId,
    List<MediaAttachment> attachments,
  ) async {
    if (!AppConfig.useFirebase) return attachments;
    final List<MediaAttachment> results = <MediaAttachment>[];
    for (final MediaAttachment attachment in attachments) {
      results.add(await _uploadOne(reportId, attachment));
    }
    return results;
  }

  Future<MediaAttachment> _uploadOne(
    String reportId,
    MediaAttachment attachment,
  ) async {
    if (attachment.uploaded || attachment.localPath == null) return attachment;
    try {
      final File file = File(attachment.localPath!);
      if (!file.existsSync()) return attachment;

      final String ext = _extension(attachment.mimeType);
      final String storagePath = '$_bucket/$reportId/${attachment.id}.$ext';

      final Reference ref = _storage.ref(storagePath);
      await ref.putFile(
        file,
        SettableMetadata(contentType: attachment.mimeType),
      );
      final String downloadUrl = await ref.getDownloadURL();

      return MediaAttachment(
        id: attachment.id,
        kind: attachment.kind,
        mimeType: attachment.mimeType,
        storagePath: downloadUrl,
        localPath: attachment.localPath,
        sizeBytes: attachment.sizeBytes,
        duration: attachment.duration,
        uploaded: true,
      );
    } catch (_) {
      // Upload failed — return original; backend can request re-upload.
      return attachment;
    }
  }

  static String _extension(String mimeType) {
    switch (mimeType) {
      case 'video/mp4':
        return 'mp4';
      case 'image/png':
        return 'png';
      case 'audio/m4a':
      case 'audio/mpeg':
        return 'm4a';
      case 'image/jpeg':
      default:
        return 'jpg';
    }
  }
}
