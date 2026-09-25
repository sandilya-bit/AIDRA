import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/models/emergency_report.dart';
import '../../../core/models/geo_point.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/tactical_map.dart';
import 'report_providers.dart';

/// Full-screen view of a single submitted report.
/// Route: /reports/:id
class ReportDetailScreen extends ConsumerWidget {
  const ReportDetailScreen({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<EmergencyReport>> reportsAsync =
        ref.watch(reportsProvider);

    return reportsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (Object e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(e.toString())),
      ),
      data: (List<EmergencyReport> reports) {
        final EmergencyReport? report = reports
            .where((EmergencyReport r) => r.id == reportId)
            .firstOrNull;

        if (report == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Report')),
            body: const Center(child: Text('Report not found.')),
          );
        }

        return _ReportDetailView(report: report);
      },
    );
  }
}

class _ReportDetailView extends StatelessWidget {
  const _ReportDetailView({required this.report});

  final EmergencyReport report;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final UrgencyLevel urgency = report.effectiveUrgency;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: AppTopBar(
          title: report.code,
          subtitle: Formatters.dateTime(report.createdAt),
          onBack: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: AppResponsiveBody(
          child: ListView(
            padding: const EdgeInsets.only(
              top: AppSizes.lg,
              bottom: AppSizes.xxl,
            ),
            children: <Widget>[
              // ── Status + urgency header ──────────────────────────────
              AppCard(
                child: Row(
                  children: <Widget>[
                    AppIconTile(
                      icon: _urgencyIcon(urgency),
                      color: urgency.color,
                    ),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${urgency.level} — ${urgency.label} Urgency',
                            style: AppText.bodyStrong
                                .copyWith(color: urgency.color),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: <Widget>[
                              StatusChip(
                                label: report.status.label,
                                color: report.status.color,
                              ),
                              const SizedBox(width: AppSizes.sm),
                              StatusChip(
                                label: report.inputType.label,
                                color: AppColors.primary,
                                icon: report.inputType.icon,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.md),

              // ── Description ─────────────────────────────────────────
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.description_outlined,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text('Description', style: AppText.label),
                      ],
                    ),
                    const SizedBox(height: AppSizes.sm),
                    Text(report.description, style: AppText.body),
                    if (report.transcript != null) ...<Widget>[
                      const SizedBox(height: AppSizes.sm),
                      const Divider(),
                      const SizedBox(height: AppSizes.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Icon(Icons.graphic_eq,
                              size: 14, color: AppColors.purple),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Transcript: ${report.transcript}',
                              style: AppText.caption
                                  .copyWith(color: palette.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.md),

              // ── Victims + hazard ────────────────────────────────────
              if (report.peopleAtRisk != null || report.hazardType != null)
                AppCard(
                  child: Row(
                    children: <Widget>[
                      if (report.peopleAtRisk != null) ...<Widget>[
                        const AppIconTile(
                          icon: Icons.people_outline,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: AppSizes.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text('${report.peopleAtRisk} people at risk',
                                  style: AppText.bodyStrong),
                              if (report.hazardType != null)
                                Text(
                                  'Hazard: ${report.hazardType!.replaceAll('_', ' ')}',
                                  style: AppText.caption.copyWith(
                                      color: palette.textSecondary),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (report.peopleAtRisk != null || report.hazardType != null)
                const SizedBox(height: AppSizes.md),

              // ── Location ────────────────────────────────────────────
              AppCard(
                padding: const EdgeInsets.all(AppSizes.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.my_location,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text('Location', style: AppText.label),
                        const Spacer(),
                        Text(
                          report.point.toString(),
                          style: AppText.caption
                              .copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                    if (report.addressText != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        report.addressText!,
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary),
                      ),
                    ],
                    const SizedBox(height: AppSizes.sm),
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppSizes.radiusSm),
                      child: SizedBox(
                        height: 180,
                        child: TacticalMap(
                          center: report.point,
                          metresPerPixel: 6,
                          interactive: true,
                          pins: <MapPin>[
                            MapPin(
                              id: report.id,
                              type: MapPinType.incident,
                              point: report.point,
                              label: report.code,
                              urgency: report.effectiveUrgency.key,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.md),

              // ── Attachments ─────────────────────────────────────────
              if (report.attachments.isNotEmpty) ...<Widget>[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(Icons.attach_file,
                              size: 16, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Attachments (${report.attachments.length})',
                            style: AppText.label,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSizes.sm),
                      Wrap(
                        spacing: AppSizes.sm,
                        runSpacing: AppSizes.sm,
                        children: report.attachments
                            .map(
                              (MediaAttachment a) => _AttachmentTile(a),
                            )
                            .toList(growable: false),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.md),
              ],

              // ── AI Triage verdict ────────────────────────────────────
              if (report.urgencyAi != null ||
                  report.aiSeverityScore != null) ...<Widget>[
                AppCard(
                  tint: palette.tint(AppColors.purple),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(Icons.auto_awesome,
                              size: 16, color: AppColors.purple),
                          const SizedBox(width: 6),
                          Text(
                            'AI TRIAGE',
                            style: AppText.label
                                .copyWith(color: AppColors.purple),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSizes.sm),
                      if (report.urgencyAi != null)
                        KeyValueRow(
                          label: 'AI severity',
                          value:
                              '${report.urgencyAi!.level} · ${report.urgencyAi!.label}',
                          valueColor: report.urgencyAi!.color,
                        ),
                      if (report.aiSeverityScore != null)
                        KeyValueRow(
                          label: 'Severity score',
                          value:
                              report.aiSeverityScore!.toStringAsFixed(2),
                        ),
                      if (report.aiConfidence != null) ...<Widget>[
                        const SizedBox(height: AppSizes.sm),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'Confidence: ${(report.aiConfidence! * 100).round()}%',
                                style: AppText.caption
                                    .copyWith(color: palette.textSecondary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: report.aiConfidence!.clamp(0.0, 1.0),
                          color: AppColors.purple,
                          backgroundColor: palette.border,
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusXs),
                          minHeight: 6,
                        ),
                      ],
                      if (report.needsHumanVerification) ...<Widget>[
                        const SizedBox(height: AppSizes.sm),
                        Row(
                          children: <Widget>[
                            const Icon(Icons.warning_amber,
                                size: 14, color: AppColors.warning),
                            const SizedBox(width: 4),
                            Text(
                              'Flagged for human verification',
                              style: AppText.caption
                                  .copyWith(color: AppColors.warning),
                            ),
                          ],
                        ),
                      ],
                      if (report.aiModelVersion != null)
                        KeyValueRow(
                          label: 'Model',
                          value: report.aiModelVersion!,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.md),
              ],

              // ── Timeline ─────────────────────────────────────────────
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.timeline,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text('Timeline', style: AppText.label),
                      ],
                    ),
                    const SizedBox(height: AppSizes.sm),
                    KeyValueRow(
                      label: 'Submitted',
                      value: Formatters.dateTime(report.createdAt),
                    ),
                    if (report.syncedAt != null)
                      KeyValueRow(
                        label: 'Synced to server',
                        value: Formatters.dateTime(report.syncedAt!),
                      ),
                    if (report.isOfflineCreated)
                      KeyValueRow(
                        label: 'Origin',
                        value: 'Offline (queued)',
                      ),
                    if (report.assignedIncidentId != null)
                      KeyValueRow(
                        label: 'Linked incident',
                        value: report.assignedIncidentId!,
                      ),
                    KeyValueRow(label: 'Report ID', value: report.id),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _urgencyIcon(UrgencyLevel level) {
    return switch (level) {
      UrgencyLevel.critical => Icons.crisis_alert,
      UrgencyLevel.high => Icons.warning_rounded,
      UrgencyLevel.medium => Icons.warning_amber_outlined,
      UrgencyLevel.low => Icons.info_outline,
    };
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile(this.attachment);

  final MediaAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final bool isImage = attachment.kind == ReportInputType.image;
    final bool isVideo = attachment.kind == ReportInputType.video;
    final bool isVoice = attachment.kind == ReportInputType.voice;
    final bool hasFile = attachment.localPath != null &&
        File(attachment.localPath!).existsSync();

    Widget preview;
    if (isImage && hasFile) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        child: Image.file(
          File(attachment.localPath!),
          width: 80,
          height: 80,
          fit: BoxFit.cover,
        ),
      );
    } else {
      preview = Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              attachment.kind.icon,
              color: AppColors.primary,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              isVideo ? 'Video' : (isVoice ? 'Voice' : 'Image'),
              style: AppText.caption
                  .copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: <Widget>[
        preview,
        if (attachment.uploaded)
          const Positioned(
            top: 4,
            right: 4,
            child: CircleAvatar(
              radius: 8,
              backgroundColor: AppColors.success,
              child: Icon(Icons.check, size: 10, color: Colors.white),
            ),
          ),
      ],
    );
  }
}
