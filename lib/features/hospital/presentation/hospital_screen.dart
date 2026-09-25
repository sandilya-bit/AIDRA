import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/hospital.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import 'hospital_providers.dart';

/// Hospital coordination (design system §11.5).
///
/// Live capacity grid, casualty pre-alert inbox with the 5-minute acknowledge
/// SLA, and load-balanced receiving suggestions for inbound casualties.
class HospitalScreen extends ConsumerWidget {
  const HospitalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = AppPalette.of(context);
    final AsyncValue<List<Hospital>> hospitals = ref.watch(hospitalsProvider);

    return Scaffold(
      body: Column(
        children: <Widget>[
          const OfflineBanner(),
          SafeArea(
            bottom: false,
            child: AppResponsiveBody(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(context.tr('hosp.title'), style: AppText.headline),
                        const SizedBox(height: 2),
                        Text(
                          'Capacity freshness, casualty routing and pre-alerts',
                          style: AppText.caption.copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      ref.read(hospitalsProvider.notifier).refresh();
                      ref.invalidate(preAlertsProvider);
                    },
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh capacity',
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.lg,
                AppSizes.md,
                AppSizes.lg,
                AppSizes.xxl,
              ),
              children: <Widget>[
                const _PreAlertInbox(),
                const SizedBox(height: AppSizes.lg),
                SectionHeader(
                  title: context.tr('hosp.capacity'),
                  actionLabel: context.tr('profile.syncNow'),
                  onAction: () => ref.read(hospitalsProvider.notifier).refresh(),
                ),
                hospitals.when(
                  data: (List<Hospital> list) => Column(
                    children: list
                        .map(
                          (Hospital hospital) => Padding(
                            padding: const EdgeInsets.only(bottom: AppSizes.md),
                            child: _HospitalCard(hospital: hospital),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  loading: () => const AppCard(child: LoadingView(label: 'Reading capacity…')),
                  error: (Object error, StackTrace _) => AppCard(
                    child: ErrorView(
                      message: error.toString(),
                      onRetry: () => ref.read(hospitalsProvider.notifier).refresh(),
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                const _ReceivingSuggestions(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreAlertInbox extends ConsumerWidget {
  const _PreAlertInbox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = AppPalette.of(context);
    final AsyncValue<List<CasualtyPreAlert>> alerts = ref.watch(preAlertsProvider);

    return alerts.when(
      data: (List<CasualtyPreAlert> list) {
        if (list.isEmpty) {
          return AppCard(
            child: Row(
              children: <Widget>[
                const AppIconTile(icon: Icons.inbox_outlined, color: AppColors.success),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Text(
                    'No inbound casualties right now.',
                    style: AppText.body.copyWith(color: palette.textSecondary),
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SectionHeader(
              title: context.tr('hosp.preAlerts'),
              trailing: StatusChip(
                label: '${list.where((CasualtyPreAlert a) => !a.isAcknowledged).length} pending',
                color: AppColors.danger,
              ),
            ),
            for (final CasualtyPreAlert alert in list)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.md),
                child: _PreAlertCard(
                  alert: alert,
                  onAcknowledge: () =>
                      ref.read(preAlertsProvider.notifier).acknowledge(alert.id),
                ),
              ),
          ],
        );
      },
      loading: () => const AppCard(child: LoadingView()),
      error: (Object error, StackTrace _) => AppCard(
        child: ErrorView(message: error.toString()),
      ),
    );
  }
}

class _PreAlertCard extends StatelessWidget {
  const _PreAlertCard({required this.alert, required this.onAcknowledge});

  final CasualtyPreAlert alert;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final Duration? eta = alert.etaIn;
    final int critical = alert.triageTags['critical'] ?? 0;
    final int serious = alert.triageTags['serious'] ?? 0;

    return AppCard(
      tint: alert.isAcknowledged ? null : palette.tint(alert.severity.color),
      semanticLabel: 'Pre-alert: ${alert.patientCount} patients for ${alert.hospitalName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconTile(icon: Icons.emergency_share_outlined, color: alert.severity.color),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${alert.patientCount} ${context.tr('hosp.patients')} → ${alert.hospitalName}',
                      style: AppText.bodyStrong,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${alert.incidentTitle ?? 'Incident'} · sent ${Formatters.relativeTime(alert.sentAt)}',
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              PriorityBadge(urgency: alert.severity, compact: true),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.xs,
            children: <Widget>[
              if (eta != null)
                StatusChip(
                  label: '${context.tr('hosp.eta')} ${eta.inMinutes} min',
                  color: AppColors.primary,
                  icon: Icons.timer_outlined,
                ),
              if (critical > 0)
                StatusChip(label: '$critical critical', color: AppColors.critical),
              if (serious > 0)
                StatusChip(label: '$serious serious', color: AppColors.warning),
              if (alert.isAckSlaBreached)
                const StatusChip(label: 'Ack SLA breached', color: AppColors.danger),
            ],
          ),
          if (alert.conditionSummary != null) ...<Widget>[
            const SizedBox(height: AppSizes.sm),
            Text(
              alert.conditionSummary!,
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
          ],
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  label: alert.isAcknowledged
                      ? 'Acknowledged'
                      : context.tr('hosp.acknowledge'),
                  variant: alert.isAcknowledged
                      ? AppButtonVariant.secondary
                      : AppButtonVariant.success,
                  compact: true,
                  icon: alert.isAcknowledged ? Icons.check : Icons.check_circle_outline,
                  onPressed: alert.isAcknowledged ? null : onAcknowledge,
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              AppButton(
                label: 'Prepare team',
                variant: AppButtonVariant.secondary,
                compact: true,
                expand: false,
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Trauma team notified.')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HospitalCard extends ConsumerWidget {
  const _HospitalCard({required this.hospital});

  final Hospital hospital;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = AppPalette.of(context);

    return AppCard(
      semanticLabel: '${hospital.name}, ${hospital.bedsAvailable} beds available',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconTile(
                icon: Icons.local_hospital_outlined,
                color: hospital.isFull ? AppColors.danger : AppColors.success,
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(hospital.name, style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        hospital.statusLabel,
                        if (hospital.distanceMetres != null)
                          Formatters.distance(hospital.distanceMetres!),
                        if (hospital.traumaLevel != null)
                          'Trauma L${hospital.traumaLevel}',
                        hospital.isCapacityFresh ? 'fresh' : 'stale',
                      ].join(' · '),
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: hospital.isAccepting ? 'OPEN' : 'FULL',
                color: hospital.isAccepting ? AppColors.success : AppColors.danger,
                filled: true,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          CapacityBar(
            label: context.tr('hosp.beds'),
            used: hospital.bedsTotal - hospital.bedsAvailable,
            total: hospital.bedsTotal,
            color: hospital.bedsAvailable < hospital.bedsTotal * 0.15
                ? AppColors.danger
                : AppColors.primary,
          ),
          const SizedBox(height: AppSizes.sm),
          CapacityBar(
            label: context.tr('hosp.icu'),
            used: hospital.icuTotal - hospital.icuAvailable,
            total: hospital.icuTotal,
            color: hospital.icuAvailable <= 2 ? AppColors.danger : AppColors.purple,
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              Expanded(
                child: KeyValueRow(
                  label: context.tr('hosp.oxygen'),
                  value: '${hospital.oxygenUnits}',
                ),
              ),
              Expanded(
                child: KeyValueRow(
                  label: 'Ventilators',
                  value: '${hospital.ventilatorsAvailable}',
                ),
              ),
              Expanded(
                child: KeyValueRow(
                  label: context.tr('hosp.blood'),
                  value: '${hospital.totalBloodUnits} u',
                ),
              ),
            ],
          ),
          if (hospital.inboundCasualties > 0) ...<Widget>[
            const SizedBox(height: AppSizes.sm),
            StatusChip(
              label: '${hospital.inboundCasualties} inbound'
                  '${hospital.etaMinutes == null ? '' : ' · ETA ${hospital.etaMinutes} min'}',
              color: AppColors.warning,
              icon: Icons.airport_shuttle_outlined,
            ),
          ],
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  label: 'Update beds',
                  variant: AppButtonVariant.secondary,
                  compact: true,
                  onPressed: () => _showCapacitySheet(context, ref),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: AppButton(
                  label: hospital.isAccepting ? 'Set on diversion' : 'Resume intake',
                  compact: true,
                  variant: hospital.isAccepting
                      ? AppButtonVariant.danger
                      : AppButtonVariant.success,
                  onPressed: () => ref
                      .read(hospitalsProvider.notifier)
                      .updateCapacity(
                        hospitalId: hospital.id,
                        isAccepting: !hospital.isAccepting,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            hospital.capacityUpdatedAt == null
                ? 'Never reported — routing will prefer fresher hospitals'
                : 'Updated ${Formatters.relativeTime(hospital.capacityUpdatedAt!)}',
            style: AppText.caption.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }

  void _showCapacitySheet(BuildContext context, WidgetRef ref) {
    int beds = hospital.bedsAvailable;
    int icu = hospital.icuAvailable;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.xl,
            AppSizes.sm,
            AppSizes.xl,
            AppSizes.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Update capacity · ${hospital.name}', style: AppText.title),
              const SizedBox(height: AppSizes.lg),
              _StepperRow(
                label: context.tr('hosp.beds'),
                value: beds,
                max: hospital.bedsTotal,
                onChanged: (int value) => setSheetState(() => beds = value),
              ),
              const SizedBox(height: AppSizes.md),
              _StepperRow(
                label: context.tr('hosp.icu'),
                value: icu,
                max: hospital.icuTotal,
                onChanged: (int value) => setSheetState(() => icu = value),
              ),
              const SizedBox(height: AppSizes.lg),
              AppButton(
                label: context.tr('common.save'),
                onPressed: () {
                  ref.read(hospitalsProvider.notifier).updateCapacity(
                        hospitalId: hospital.id,
                        bedsAvailable: beds,
                        icuAvailable: icu,
                      );
                  Navigator.of(sheetContext).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: AppText.bodyStrong)),
        IconButton(
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Decrease',
        ),
        SizedBox(
          width: 44,
          child: Text('$value', textAlign: TextAlign.center, style: AppText.title),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'Increase',
        ),
      ],
    );
  }
}

class _ReceivingSuggestions extends ConsumerWidget {
  const _ReceivingSuggestions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const ReceivingQuery query = ReceivingQuery(patientCount: 4, needsIcu: true);
    final AsyncValue<List<Hospital>> suggestions =
        ref.watch(receivingHospitalsProvider(query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: 'AI routing — 4 casualties, ICU required',
          trailing: const StatusChip(
            label: 'BALANCED',
            color: AppColors.purple,
            icon: Icons.auto_awesome,
          ),
        ),
        suggestions.when(
          data: (List<Hospital> list) {
            if (list.isEmpty) {
              return AppCard(
                tint: AppPalette.of(context).tint(AppColors.danger),
                child: Text(
                  'No hospital can currently take this load. Escalate to the '
                  'authority desk and consider field stabilisation.',
                  style: AppText.body.copyWith(color: AppColors.danger),
                ),
              );
            }
            return AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
              child: Column(
                children: <Widget>[
                  for (final Hospital hospital in list.take(3))
                    AppListRow(
                      leading: AppIconTile(
                        icon: Icons.local_hospital_outlined,
                        color: AppColors.success,
                      ),
                      title: hospital.name,
                      subtitle: '${hospital.bedsAvailable} beds · '
                          '${hospital.icuAvailable} ICU · '
                          '${hospital.isCapacityFresh ? 'fresh data' : 'stale data'}',
                      trailing: const Icon(Icons.arrow_forward, size: 16),
                      onTap: () => context.go('/map'),
                    ),
                ],
              ),
            );
          },
          loading: () => const AppCard(child: LoadingView()),
          error: (Object error, StackTrace _) => AppCard(
            child: ErrorView(message: error.toString()),
          ),
        ),
      ],
    );
  }
}
