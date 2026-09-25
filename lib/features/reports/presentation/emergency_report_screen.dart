import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/models/emergency_report.dart';
import '../../../core/models/geo_point.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/tactical_map.dart';
import 'report_providers.dart';

/// Emergency reporting (design system §4.4).
///
/// Text · Voice · Image · Video capture, GPS location, an urgency selector and
/// a submit path that works with zero connectivity.
class EmergencyReportScreen extends ConsumerStatefulWidget {
  const EmergencyReportScreen({super.key});

  @override
  ConsumerState<EmergencyReportScreen> createState() =>
      _EmergencyReportScreenState();
}

class _EmergencyReportScreenState extends ConsumerState<EmergencyReportScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _description = TextEditingController();

  ReportInputType _inputType = ReportInputType.text;
  UrgencyLevel _urgency = UrgencyLevel.high;
  GeoPoint _point = const GeoPoint(AppConfig.defaultLatitude, AppConfig.defaultLongitude);
  final List<MediaAttachment> _attachments = <MediaAttachment>[];
  bool _isRecording = false;
  String? _transcript;
  bool _isSubmitting = false;
  int _peopleAtRisk = 1;
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isLocating = false;
  String? _recordingPath;

  @override
  void dispose() {
    _description.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: AppTopBar(
          title: context.tr('report.title'),
          subtitle: 'AI triage runs the moment you submit',
          onBack: () => context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: AppResponsiveBody(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.only(top: AppSizes.lg, bottom: AppSizes.xxl),
              children: <Widget>[
                Text(context.tr('report.howToReport'), style: AppText.subtitle),
                const SizedBox(height: AppSizes.sm),
                _InputTypePicker(
                  selected: _inputType,
                  onChanged: (ReportInputType type) => setState(() {
                    _inputType = type;
                    if (type != ReportInputType.voice) _isRecording = false;
                  }),
                ),
                const SizedBox(height: AppSizes.lg),
                if (_inputType == ReportInputType.voice)
                  _VoiceRecorder(
                    isRecording: _isRecording,
                    transcript: _transcript,
                    onToggle: _toggleRecording,
                  ),
                if (_inputType == ReportInputType.image ||
                    _inputType == ReportInputType.video)
                  _MediaCapture(
                    kind: _inputType,
                    attachments: _attachments,
                    onCapture: _captureMedia,
                    onRemove: (String id) => setState(
                      () => _attachments.removeWhere((MediaAttachment a) => a.id == id),
                    ),
                  ),
                if (_inputType == ReportInputType.voice ||
                    _inputType == ReportInputType.image ||
                    _inputType == ReportInputType.video)
                  const SizedBox(height: AppSizes.lg),
                TextFormField(
                  controller: _description,
                  maxLines: 4,
                  maxLength: Validators.maxReportLength,
                  textCapitalization: TextCapitalization.sentences,
                  validator: Validators.reportDescription,
                  decoration: InputDecoration(
                    labelText: context.tr('report.describe'),
                    hintText: context.tr('report.descriptionHint'),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                _PeopleAtRiskStepper(
                  value: _peopleAtRisk,
                  onChanged: (int value) => setState(() => _peopleAtRisk = value),
                ),
                const SizedBox(height: AppSizes.lg),
                _LocationCard(
                  point: _point,
                  onRefresh: _refreshLocation,
                ),
                const SizedBox(height: AppSizes.lg),
                Text(context.tr('report.urgency'), style: AppText.subtitle),
                const SizedBox(height: 2),
                Text(
                  context.tr('report.urgencyHint'),
                  style: AppText.caption.copyWith(color: palette.textSecondary),
                ),
                const SizedBox(height: AppSizes.sm),
                Wrap(
                  spacing: AppSizes.sm,
                  runSpacing: AppSizes.sm,
                  children: UrgencyLevel.values
                      .map(
                        (UrgencyLevel level) => AppChoiceChip(
                          label: level.label,
                          color: level.color,
                          selected: level == _urgency,
                          onSelected: () => setState(() => _urgency = level),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: AppSizes.lg),
                AppCard(
                  tint: palette.tint(AppColors.purple),
                  child: Row(
                    children: <Widget>[
                      const AppIconTile(icon: Icons.auto_awesome, color: AppColors.purple),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: Text(
                          'The AI urgency engine verifies every report and can escalate it '
                          'to a higher severity. Critical reports are escalated automatically '
                          'if no responder accepts within 5 minutes.',
                          style: AppText.caption.copyWith(color: palette.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                AppButton(
                  label: context.tr('report.submit'),
                  icon: Icons.send_rounded,
                  isLoading: _isSubmitting,
                  onPressed: _isSubmitting ? null : _submit,
                ),
                const SizedBox(height: AppSizes.sm),
                Center(
                  child: Text(
                    'Works offline — the report is queued and sent automatically.',
                    style: AppText.caption.copyWith(color: palette.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Stop recording
      final String? path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _recordingPath = path;
        _transcript = 'Voice note recorded at ${path?.split('/').last ?? 'audio.m4a'}';
        if (_description.text.isEmpty && path != null) {
          _description.text = _transcript!;
        }
      });
      // Add voice attachment
      if (path != null) {
        final File file = File(path);
        final int size = file.existsSync() ? file.lengthSync() : 0;
        setState(() {
          _attachments.add(
            MediaAttachment(
              id: const Uuid().v4(),
              kind: ReportInputType.voice,
              mimeType: 'audio/m4a',
              localPath: path,
              sizeBytes: size,
            ),
          );
        });
      }
    } else {
      // Start recording
      final bool hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied.')),
          );
        }
        return;
      }
      final Directory tempDir = await getTemporaryDirectory();
      final String filePath =
          '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
        path: filePath,
      );
      setState(() => _isRecording = true);
    }
  }

  Future<void> _captureMedia() async {
    XFile? file;
    try {
      if (_inputType == ReportInputType.video) {
        file = await _imagePicker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(seconds: 30),
        );
      } else {
        file = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
          maxWidth: 1920,
          maxHeight: 1920,
        );
      }
    } catch (_) {
      // Camera not available — fall back to gallery.
      try {
        if (_inputType == ReportInputType.video) {
          file = await _imagePicker.pickVideo(source: ImageSource.gallery);
        } else {
          file = await _imagePicker.pickImage(source: ImageSource.gallery);
        }
      } catch (_) {
        // Gallery also unavailable (simulator / web).
      }
    }

    if (file == null) return;
    if (!mounted) return;

    final String mimeType =
        _inputType == ReportInputType.video ? 'video/mp4' : 'image/jpeg';
    int sizeBytes = 0;
    try {
      sizeBytes = await File(file.path).length();
    } catch (_) {}

    setState(() {
      _attachments.add(
        MediaAttachment(
          id: const Uuid().v4(),
          kind: _inputType,
          mimeType: mimeType,
          localPath: file!.path,
          sizeBytes: sizeBytes,
        ),
      );
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('report.attachmentReady'))),
      );
    }
  }

  Future<void> _refreshLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are disabled.')),
          );
        }
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permissions are permanently denied. Enable them in Settings.',
              ),
            ),
          );
        }
        return;
      }
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        _point = GeoPoint(
          position.latitude,
          position.longitude,
          accuracyMetres: position.accuracy,
        );
      });
    } catch (_) {
      // GPS unavailable — keep last known point.
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSubmitting = true);

    final EmergencyReport saved = await ref.read(reportsProvider.notifier).submit(
          description: _description.text.trim(),
          inputType: _inputType,
          urgency: _urgency,
          point: _point,
          hazardType: _inferHazard(_description.text),
          peopleAtRisk: _peopleAtRisk,
          transcript: _transcript,
          attachments: _attachments,
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    final bool queued = saved.isPendingSync;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _SubmitResultSheet(
        report: saved,
        queued: queued,
      ),
    );

    if (mounted) context.go('/reports');
  }

  String _inferHazard(String text) {
    final String value = text.toLowerCase();
    if (value.contains('flood') || value.contains('water')) return 'flood';
    if (value.contains('fire') || value.contains('smoke')) return 'fire';
    if (value.contains('collaps') || value.contains('debris')) return 'structural_collapse';
    if (value.contains('road') || value.contains('traffic')) return 'road_blockage';
    if (value.contains('injur') || value.contains('bleed')) return 'medical';
    return 'other';
  }
}

class _InputTypePicker extends StatelessWidget {
  const _InputTypePicker({required this.selected, required this.onChanged});

  final ReportInputType selected;
  final ValueChanged<ReportInputType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ReportInputType.values.map((ReportInputType type) {
        final bool isSelected = type == selected;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: AppSizes.sm),
            child: Semantics(
              button: true,
              selected: isSelected,
              label: '${type.label} report',
              child: InkWell(
                onTap: () => onChanged(type),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  constraints: const BoxConstraints(minHeight: 74),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppPalette.of(context).tint(AppColors.primary)
                        : AppPalette.of(context).surface,
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppPalette.of(context).border,
                      width: isSelected ? 1.6 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        type.icon,
                        color: isSelected
                            ? AppColors.primary
                            : AppPalette.of(context).textSecondary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        type.label,
                        style: AppText.caption.copyWith(
                          color: isSelected
                              ? AppColors.primary
                              : AppPalette.of(context).textPrimary,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _VoiceRecorder extends StatelessWidget {
  const _VoiceRecorder({
    required this.isRecording,
    required this.transcript,
    required this.onToggle,
  });

  final bool isRecording;
  final String? transcript;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final Color color = isRecording ? AppColors.danger : AppColors.primary;

    return AppCard(
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconTile(icon: isRecording ? Icons.stop_circle_outlined : Icons.mic_none, color: color),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Text(
                  isRecording ? context.tr('report.recording') : context.tr('report.useVoice'),
                  style: AppText.bodyStrong,
                ),
              ),
              AppButton(
                label: isRecording ? 'Stop' : 'Record',
                variant: isRecording ? AppButtonVariant.danger : AppButtonVariant.secondary,
                compact: true,
                expand: false,
                onPressed: onToggle,
              ),
            ],
          ),
          if (transcript != null) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Row(
              children: <Widget>[
                const Icon(Icons.graphic_eq, size: 16, color: AppColors.purple),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ASR: $transcript',
                    style: AppText.caption.copyWith(color: palette.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaCapture extends StatelessWidget {
  const _MediaCapture({
    required this.kind,
    required this.attachments,
    required this.onCapture,
    required this.onRemove,
  });

  final ReportInputType kind;
  final List<MediaAttachment> attachments;
  final VoidCallback onCapture;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconTile(icon: kind.icon, color: AppColors.primary),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Text(
                  kind == ReportInputType.video
                      ? 'Record a short clip (max 30s)'
                      : 'Capture a photo of the situation',
                  style: AppText.bodyStrong,
                ),
              ),
              AppButton(
                label: 'Capture',
                compact: true,
                expand: false,
                icon: Icons.add_a_photo_outlined,
                onPressed: onCapture,
              ),
            ],
          ),
          if (attachments.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Wrap(
              spacing: AppSizes.sm,
              runSpacing: AppSizes.sm,
              children: attachments
                  .map(
                    (MediaAttachment attachment) => Chip(
                      avatar: Icon(
                        attachment.kind.icon,
                        size: 16,
                        color: palette.textPrimary,
                      ),
                      label: Text(
                        attachment.localPath?.split('/').last ?? 'attachment',
                        style: AppText.caption,
                      ),
                      onDeleted: () => onRemove(attachment.id),
                      deleteIcon: const Icon(Icons.close, size: 14),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _PeopleAtRiskStepper extends StatelessWidget {
  const _PeopleAtRiskStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('People at risk', style: AppText.bodyStrong),
              const SizedBox(height: 2),
              Text(
                'Affects severity weighting and resource forecasting',
                style: AppText.caption.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Fewer people',
        ),
        SizedBox(
          width: 34,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: AppText.title,
          ),
        ),
        IconButton(
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'More people',
        ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.point, required this.onRefresh});

  final GeoPoint point;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.my_location, size: 17, color: AppColors.primary),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(context.tr('report.currentLocation'), style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      point.toString() +
                          (point.accuracyMetres == null
                              ? ''
                              : ' · ±${point.accuracyMetres!.round()} m'),
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh location',
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            child: SizedBox(
              height: 150,
              child: TacticalMap(
                center: point,
                metresPerPixel: 8,
                interactive: false,
                pins: <MapPin>[
                  MapPin(
                    id: 'self',
                    type: MapPinType.user,
                    point: point,
                    label: context.tr('map.yourLocation'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Simulated AI triage result sheet — mirrors the payload the real
/// `/reports` endpoint returns (`ai_severity_score`, `ai_confidence`).
class _SubmitResultSheet extends StatelessWidget {
  const _SubmitResultSheet({required this.report, required this.queued});

  final EmergencyReport report;
  final bool queued;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final UrgencyLevel aiSeverity = _localTriageSeverity(report);
    final double confidence = _localTriageConfidence(report);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizes.xl, AppSizes.sm, AppSizes.xl, AppSizes.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconTile(
                icon: queued ? Icons.cloud_off_outlined : Icons.check_circle_outline,
                color: queued ? AppColors.warning : AppColors.success,
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      queued ? 'Saved offline' : 'Report submitted',
                      style: AppText.title,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      queued
                          ? context.tr('report.queuedOffline')
                          : context.tr('report.submitted'),
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          AppCard(
            tint: palette.tint(AppColors.purple),
            padding: const EdgeInsets.all(AppSizes.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.auto_awesome, size: 16, color: AppColors.purple),
                    const SizedBox(width: 6),
                    Text(
                      context.tr('report.aiTriage').toUpperCase(),
                      style: AppText.label.copyWith(color: AppColors.purple),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.sm),
                KeyValueRow(
                  label: 'Predicted severity',
                  value: '${aiSeverity.level} · ${aiSeverity.label}',
                  valueColor: aiSeverity.color,
                ),
                KeyValueRow(
                  label: 'Your selection',
                  value: report.urgencyUser.label,
                ),
                KeyValueRow(
                  label: context.tr('report.confidence'),
                  value: '${(confidence * 100).round()}%',
                ),
                KeyValueRow(label: 'Report ID', value: report.code),
                if (report.peopleAtRisk != null)
                  KeyValueRow(label: 'People at risk', value: '${report.peopleAtRisk}'),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          AppButton(
            label: 'View my reports',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// Demo triage heuristic standing in for the Urgency Detection Engine.
  /// Production uses `POST /reports` → AI service (PRD Volume II §5.A).
  UrgencyLevel _localTriageSeverity(EmergencyReport report) {
    final String text = report.description.toLowerCase();
    final int people = report.peopleAtRisk ?? 0;
    int score = report.urgencyUser.rank;

    const List<String> criticalTerms = <String>[
      'trapped', 'drowning', 'collapse', 'unconscious', 'bleeding', 'children',
    ];
    const List<String> highTerms = <String>['injur', 'fire', 'stranded', 'rising', 'gas'];

    for (final String term in criticalTerms) {
      if (text.contains(term)) score += 1;
    }
    for (final String term in highTerms) {
      if (text.contains(term)) score += 1;
    }
    if (people >= 5) score += 1;
    if (score >= 4) return UrgencyLevel.critical;
    if (score == 3) return UrgencyLevel.high;
    if (score == 2) return UrgencyLevel.medium;
    return UrgencyLevel.low;
  }

  double _localTriageConfidence(EmergencyReport report) {
    final int words = report.description.split(RegExp(r'\s+')).length;
    final double base = words >= 12 ? 0.86 : (words >= 7 ? 0.78 : 0.66);
    final double bonus = report.peopleAtRisk != null ? 0.05 : 0.0;
    return (base + bonus).clamp(0.5, 0.97);
  }
}
