import '../constants/app_enums.dart';
import 'geo_point.dart';
import 'parse.dart';

/// A report exactly as the victim filed it, plus everything the AI triage
/// pipeline returned (FR-101–107, US-101–105).
class EmergencyReport {
  const EmergencyReport({
    required this.id,
    required this.code,
    required this.reporterId,
    required this.inputType,
    required this.description,
    required this.point,
    required this.urgencyUser,
    required this.status,
    required this.createdAt,
    this.reporterName,
    this.descriptionLanguage = 'en',
    this.transcript,
    this.addressText,
    this.hazardType,
    this.peopleAtRisk,
    this.urgencyAi,
    this.aiSeverityScore,
    this.aiConfidence,
    this.aiModelVersion,
    this.aiEntities = const <String, dynamic>{},
    this.aiNeeds = const <String, bool>{},
    this.attachments = const <MediaAttachment>[],
    this.assignedIncidentId,
    this.isOfflineCreated = false,
    this.syncedAt,
    this.errorMessage,
  });

  final String id;
  final String code;
  final String reporterId;
  final String? reporterName;
  final ReportInputType inputType;
  final String description;
  final String descriptionLanguage;
  final String? transcript;
  final GeoPoint point;
  final String? addressText;
  final String? hazardType;
  final int? peopleAtRisk;
  final UrgencyLevel urgencyUser;
  final UrgencyLevel? urgencyAi;
  final double? aiSeverityScore;
  final double? aiConfidence;
  final String? aiModelVersion;
  final Map<String, dynamic> aiEntities;
  final Map<String, bool> aiNeeds;
  final List<MediaAttachment> attachments;
  final ReportStatus status;
  final String? assignedIncidentId;
  final bool isOfflineCreated;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final String? errorMessage;

  /// Effective urgency shown to responders: AI verdict wins when the model has
  /// high confidence, otherwise the human-entered level is trusted (AC-T3).
  UrgencyLevel get effectiveUrgency {
    final UrgencyLevel? ai = urgencyAi;
    if (ai == null) return urgencyUser;
    final double confidence = aiConfidence ?? 0;
    return confidence >= 0.75 ? ai : urgencyUser;
  }

  bool get needsHumanVerification {
    final UrgencyLevel? ai = urgencyAi;
    if (ai == null) return false;
    return (ai.rank - urgencyUser.rank).abs() >= 2 || (aiConfidence ?? 0) < 0.6;
  }

  bool get isPendingSync =>
      status == ReportStatus.queued ||
      status == ReportStatus.submitting ||
      status == ReportStatus.failed;

  EmergencyReport copyWith({
    String? id,
    ReportStatus? status,
    UrgencyLevel? urgencyAi,
    double? aiConfidence,
    double? aiSeverityScore,
    String? aiModelVersion,
    Map<String, dynamic>? aiEntities,
    Map<String, bool>? aiNeeds,
    DateTime? syncedAt,
    String? errorMessage,
    String? assignedIncidentId,
    List<MediaAttachment>? attachments,
    bool? isOfflineCreated,
  }) {
    return EmergencyReport(
      id: id ?? this.id,
      code: code,
      reporterId: reporterId,
      reporterName: reporterName,
      inputType: inputType,
      description: description,
      descriptionLanguage: descriptionLanguage,
      transcript: transcript,
      point: point,
      addressText: addressText,
      hazardType: hazardType,
      peopleAtRisk: peopleAtRisk,
      urgencyUser: urgencyUser,
      urgencyAi: urgencyAi ?? this.urgencyAi,
      aiSeverityScore: aiSeverityScore ?? this.aiSeverityScore,
      aiConfidence: aiConfidence ?? this.aiConfidence,
      aiModelVersion: aiModelVersion ?? this.aiModelVersion,
      aiEntities: aiEntities ?? this.aiEntities,
      aiNeeds: aiNeeds ?? this.aiNeeds,
      attachments: attachments ?? this.attachments,
      status: status ?? this.status,
      assignedIncidentId: assignedIncidentId ?? this.assignedIncidentId,
      isOfflineCreated: isOfflineCreated ?? this.isOfflineCreated,
      createdAt: createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      errorMessage: errorMessage,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'report_code': code,
        'reporter_id': reporterId,
        'input_type': inputType.key,
        'description': description,
        'description_lang': descriptionLanguage,
        if (transcript != null) 'transcript': transcript,
        'latitude': point.latitude,
        'longitude': point.longitude,
        if (addressText != null) 'address_text': addressText,
        if (hazardType != null) 'hazard_type': hazardType,
        if (peopleAtRisk != null) 'people_at_risk': peopleAtRisk,
        'urgency_user': urgencyUser.key,
        if (urgencyAi != null) 'urgency_ai': urgencyAi!.key,
        if (aiSeverityScore != null) 'ai_severity_score': aiSeverityScore,
        if (aiConfidence != null) 'ai_confidence': aiConfidence,
        if (aiModelVersion != null) 'ai_model_version': aiModelVersion,
        if (aiEntities.isNotEmpty) 'ai_entities': aiEntities,
        if (aiNeeds.isNotEmpty) 'ai_needs': aiNeeds,
        'status': status.key,
        if (assignedIncidentId != null) 'incident_id': assignedIncidentId,
        'is_offline_created': isOfflineCreated,
        'created_at': createdAt.toIso8601String(),
        if (syncedAt != null) 'synced_at': syncedAt!.toIso8601String(),
        if (attachments.isNotEmpty)
          'attachments':
              attachments.map((MediaAttachment a) => a.toJson()).toList(growable: false),
      };

  static EmergencyReport fromJson(Map<String, dynamic> json) {
    return EmergencyReport(
      id: parseString(json['id'], 'r-${DateTime.now().microsecondsSinceEpoch}'),
      code: parseString(json['report_code'], 'AID-0000'),
      reporterId: parseString(json['reporter_id']),
      reporterName: json['reporter_name']?.toString(),
      inputType: enumFromKey(
        ReportInputType.values,
        json['input_type']?.toString(),
        ReportInputType.text,
      ),
      description: parseString(json['description']),
      descriptionLanguage: parseString(json['description_lang'], 'en'),
      transcript: json['transcript']?.toString(),
      point: GeoPoint(
        parseDouble(json['latitude']),
        parseDouble(json['longitude']),
        accuracyMetres: json['location_accuracy_m'] == null
            ? null
            : parseDouble(json['location_accuracy_m']),
      ),
      addressText: json['address_text']?.toString(),
      hazardType: json['hazard_type']?.toString(),
      peopleAtRisk:
          json['people_at_risk'] == null ? null : parseInt(json['people_at_risk']),
      urgencyUser: enumFromKey(
        UrgencyLevel.values,
        json['urgency_user']?.toString(),
        UrgencyLevel.medium,
      ),
      urgencyAi: json['urgency_ai'] == null
          ? null
          : enumFromKey(
              UrgencyLevel.values, json['urgency_ai']?.toString(), UrgencyLevel.medium),
      aiSeverityScore: json['ai_severity_score'] == null
          ? null
          : parseDouble(json['ai_severity_score']),
      aiConfidence:
          json['ai_confidence'] == null ? null : parseDouble(json['ai_confidence']),
      aiModelVersion: json['ai_model_version']?.toString(),
      aiEntities: parseMap(json['ai_entities']),
      aiNeeds: parseMap(json['ai_needs']).map(
        (String key, dynamic value) => MapEntry<String, bool>(key, parseBool(value)),
      ),
      attachments: parseMapList(json['attachments'])
          .map(MediaAttachment.fromJson)
          .toList(growable: false),
      status: enumFromKey(
        ReportStatus.values,
        json['status']?.toString(),
        ReportStatus.submitted,
      ),
      assignedIncidentId: json['incident_id']?.toString(),
      isOfflineCreated: parseBool(json['is_offline_created']),
      createdAt: parseDate(json['created_at']),
      syncedAt: parseDateOrNull(json['synced_at']),
      errorMessage: json['error_message']?.toString(),
    );
  }
}

/// Local media captured with a report. `localPath` is set while the file is
/// still only on the device (offline capture, FR-1001).
class MediaAttachment {
  const MediaAttachment({
    required this.id,
    required this.kind,
    required this.mimeType,
    this.storagePath,
    this.localPath,
    this.sizeBytes = 0,
    this.duration,
    this.uploaded = false,
  });

  final String id;
  final ReportInputType kind;
  final String mimeType;
  final String? storagePath;
  final String? localPath;
  final int sizeBytes;
  final Duration? duration;
  final bool uploaded;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind.key,
        'mime_type': mimeType,
        if (storagePath != null) 'storage_key': storagePath,
        if (localPath != null) 'local_path': localPath,
        'size_bytes': sizeBytes,
        if (duration != null) 'duration_sec': duration!.inSeconds,
        'uploaded': uploaded,
      };

  static MediaAttachment fromJson(Map<String, dynamic> json) => MediaAttachment(
        id: parseString(json['id'], 'm-${json.hashCode}'),
        kind: enumFromKey(
          ReportInputType.values,
          json['kind']?.toString(),
          ReportInputType.image,
        ),
        mimeType: parseString(json['mime_type'], 'application/octet-stream'),
        storagePath: json['storage_key']?.toString(),
        localPath: json['local_path']?.toString(),
        sizeBytes: parseInt(json['size_bytes']),
        duration: json['duration_sec'] == null
            ? null
            : Duration(seconds: parseInt(json['duration_sec'])),
        uploaded: parseBool(json['uploaded']),
      );
}
