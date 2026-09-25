import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/models/emergency_report.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import 'report_providers.dart';

/// "My Reports" — the victim/volunteer view of everything they filed, with the
/// AI triage verdict and sync state for each one.
class ReportsListScreen extends ConsumerStatefulWidget {
  const ReportsListScreen({super.key});

  @override
  ConsumerState<ReportsListScreen> createState() => _ReportsListScreenState();
}

class _ReportsListScreenState extends ConsumerState<ReportsListScreen> {
  ReportStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AsyncValue<List<EmergencyReport>> reports = ref.watch(reportsProvider);
    final int pending = ref.watch(pendingReportCountProvider);

    return Scaffold(
      body: Column(
        children: <Widget>[
          const OfflineBanner(),
          SafeArea(
            bottom: false,
            child: AppResponsiveBody(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.lg,
                AppSizes.lg,
                AppSizes.lg,
                AppSizes.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(context.tr('report.myReports'), style: AppText.headline),
                      ),
                      if (pending > 0)
                        StatusChip(
                          label: '$pending queued',
                          color: AppColors.warning,
                          icon: Icons.cloud_upload_outlined,
                        ),
                      const SizedBox(width: AppSizes.sm),
                      AppButton(
                        label: 'New',
                        icon: Icons.add,
                        compact: true,
                        expand: false,
                        onPressed: () => context.go('/reports/new'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.sm),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(right: AppSizes.sm),
                          child: AppChoiceChip(
                            label: 'All',
                            selected: _statusFilter == null,
                            onSelected: () => setState(() => _statusFilter = null),
                          ),
                        ),
                        ...<ReportStatus>[
                          ReportStatus.queued,
                          ReportStatus.submitted,
                          ReportStatus.triaged,
                          ReportStatus.assigned,
                          ReportStatus.resolved,
                        ].map(
                          (ReportStatus status) => Padding(
                            padding: const EdgeInsets.only(right: AppSizes.sm),
                            child: AppChoiceChip(
                              label: status.label,
                              color: status.color,
                              selected: _statusFilter == status,
                              onSelected: () => setState(() => _statusFilter = status),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(reportsProvider.notifier).refresh(),
              child: reports.when(
                data: (List<EmergencyReport> list) {
                  final List<EmergencyReport> visible = _statusFilter == null
                      ? list
                      : list.where((EmergencyReport r) => r.status == _statusFilter).toList();
                  if (visible.isEmpty) {
                    return EmptyState(
                      icon: Icons.description_outlined,
                      title: context.tr('report.empty'),
                      message: 'Reports you file appear here with live AI triage results.',
                      actionLabel: 'Report an emergency',
                      onAction: () => context.go('/reports/new'),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSizes.lg,
                      AppSizes.sm,
                      AppSizes.lg,
                      AppSizes.xxl,
                    ),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSizes.md),
                    itemBuilder: (BuildContext context, int index) {
                      final EmergencyReport report = visible[index];
                      return _ReportCard(
                        report: report,
                        onTap: () => _showDetail(context, report),
                      );
                    },
                  );
                },
                loading: () => const LoadingView(label: 'Loading reports…'),
                error: (Object error, StackTrace _) => ErrorView(
                  message: error.toString(),
                  onRetry: () => ref.read(reportsProvider.notifier).refresh(),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
            child: Text(
              'Reports sync automatically. Nothing is lost offline.',
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
          ),
          const SizedBox(height: AppSizes.sm),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, EmergencyReport report) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _ReportDetailSheet(report: report),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.onTap});

  final EmergencyReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final UrgencyLevel urgency = report.effectiveUrgency;

    return AppCard(
      onTap: onTap,
      semanticLabel: '${report.code}: ${report.description}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconTile(icon: report.inputType.icon, color: urgency.color),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      report.description,
                      style: AppText.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${report.code} · ${Formatters.relativeTime(report.createdAt)}'
                      '${report.addressText == null ? '' : ' · ${report.addressText}'}',
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PriorityBadge(urgency: urgency, compact: true),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.xs,
            children: <Widget>[
              StatusChip(
                label: report.status.label,
                color: report.status.color,
                icon: report.isPendingSync ? Icons.cloud_off_outlined : null,
              ),
              if (report.urgencyAi != null)
                StatusChip(
                  label: 'AI ${report.urgencyAi!.level} · '
                      '${((report.aiConfidence ?? 0) * 100).round()}%',
                  color: AppColors.purple,
                  icon: Icons.auto_awesome,
                ),
              if (report.needsHumanVerification)
                const StatusChip(
                  label: 'Review needed',
                  color: AppColors.warning,
                  icon: Icons.visibility_outlined,
                ),
              if (report.peopleAtRisk != null && report.peopleAtRisk! > 0)
                StatusChip(
                  label: '${report.peopleAtRisk} at risk',
                  color: AppColors.danger,
                  icon: Icons.groups_outlined,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportDetailSheet extends StatelessWidget {
  const _ReportDetailSheet({required this.report});

  final EmergencyReport report;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(AppSizes.xl, AppSizes.sm, AppSizes.xl, AppSizes.xxl),
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconTile(icon: report.inputType.icon, color: report.effectiveUrgency.color),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(report.code, style: AppText.title),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.dateTime(report.createdAt),
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              PriorityBadge(urgency: report.effectiveUrgency),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Report', style: AppText.bodyStrong),
                const SizedBox(height: AppSizes.sm),
                Text(report.description, style: AppText.body),
                if (report.transcript != null) ...<Widget>[
                  const SizedBox(height: AppSizes.sm),
                  Text(
                    'Voice transcript: ${report.transcript}',
                    style: AppText.caption.copyWith(color: palette.textSecondary),
                  ),
                ],
                const SizedBox(height: AppSizes.md),
                Divider(height: 1, color: palette.border),
                const SizedBox(height: AppSizes.sm),
                KeyValueRow(label: 'Input', value: report.inputType.label),
                KeyValueRow(label: 'Language', value: report.descriptionLanguage),
                KeyValueRow(label: 'Hazard', value: report.hazardType ?? '—'),
                KeyValueRow(
                  label: 'Location',
                  value: report.addressText ?? report.point.toString(),
                ),
                KeyValueRow(
                  label: 'Status',
                  value: report.status.label,
                  valueColor: report.status.color,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            tint: palette.tint(AppColors.purple),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.auto_awesome, size: 16, color: AppColors.purple),
                    const SizedBox(width: 6),
                    Text('AI TRIAGE', style: AppText.label.copyWith(color: AppColors.purple)),
                  ],
                ),
                const SizedBox(height: AppSizes.sm),
                KeyValueRow(
                  label: 'Predicted severity',
                  value: report.urgencyAi?.label ?? 'pending',
                  valueColor: report.urgencyAi?.color,
                ),
                KeyValueRow(
                  label: 'Your selection',
                  value: report.urgencyUser.label,
                ),
                KeyValueRow(
                  label: 'Confidence',
                  value: report.aiConfidence == null
                      ? '—'
                      : '${(report.aiConfidence! * 100).round()}%',
                ),
                KeyValueRow(label: 'Model', value: report.aiModelVersion ?? '—'),
                if (report.aiNeeds.isNotEmpty)
                  KeyValueRow(
                    label: 'Needs detected',
                    value: report.aiNeeds.entries
                        .where((MapEntry<String, bool> e) => e.value)
                        .map((MapEntry<String, bool> e) => e.key)
                        .join(', '),
                  ),
                if (report.aiEntities.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSizes.sm),
                  Text(
                    'Entities: ${report.aiEntities.entries.map((MapEntry<String, dynamic> e) => '${e.key}=${e.value}').join(' · ')}',
                    style: AppText.caption.copyWith(color: palette.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (report.isPendingSync) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            AppCard(
              tint: palette.tint(AppColors.warning),
              child: Row(
                children: <Widget>[
                  const AppIconTile(icon: Icons.cloud_upload_outlined, color: AppColors.warning),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Text(
                      'Queued on this device. It will be delivered automatically '
                      'when you are back online.',
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSizes.lg),
          AppButton(
            label: context.tr('common.close'),
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
