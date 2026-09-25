import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/emergency_report.dart';
import '../../../core/models/geo_point.dart';
import '../../../core/models/hospital.dart';
import '../../../core/models/incident.dart';
import '../../../core/models/resource_item.dart';
import '../../../core/models/volunteer.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../hospital/presentation/hospital_providers.dart';
import '../../incidents/presentation/incident_providers.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../reports/presentation/report_providers.dart';
import '../../resources/presentation/resource_providers.dart';
import '../../volunteer/presentation/volunteer_providers.dart';

/// Reference point for distance callouts until a GPS fix is available.
const GeoPoint kDemoCenter =
    GeoPoint(AppConfig.defaultLatitude, AppConfig.defaultLongitude);

/// Home dashboard (design system §4.3).
///
/// One screen, five role personalities: victims see the active emergency and
/// their own reports; volunteers see their tasks and availability; NGO,
/// hospital and authority roles get the coordination view with KPI cards.
class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserRole role = ref.watch(effectiveRoleProvider);
    final AppUser? user = ref.watch(currentUserProvider);
    final AsyncValue<List<Incident>> incidents = ref.watch(incidentsProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(incidentsProvider.notifier).refresh(),
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          const OfflineBanner(),
          AppResponsiveBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _DashboardHeader(
                  name: user?.fullName ?? 'AIDRA User',
                  role: role,
                  unreadCount: ref.watch(unreadNotificationCountProvider),
                  onNotificationTap: () => context.go('/notifications'),
                  onProfileTap: () => context.go('/profile'),
                ),
                const SizedBox(height: AppSizes.lg),
                const _EventBanner(),
                _QuickActions(role: role),
                const SizedBox(height: AppSizes.lg),
                ..._roleSections(role, incidents),
                const SizedBox(height: AppSizes.xxl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _roleSections(UserRole role, AsyncValue<List<Incident>> incidents) {
    switch (role) {
      case UserRole.victim:
        return _victimSections(incidents);
      case UserRole.volunteer:
        return _volunteerSections(incidents);
      case UserRole.ngo:
        return _coordinatorSections(incidents, ngoMode: true);
      case UserRole.hospital:
        return _hospitalSections(incidents);
      case UserRole.authority:
      case UserRole.superAdmin:
        return _coordinatorSections(incidents, ngoMode: false);
    }
  }

  // --------------------------------------------------------------- victims

  List<Widget> _victimSections(AsyncValue<List<Incident>> incidents) {
    return <Widget>[
      const _FocusIncidentCard(),
      const _SectionGap(),
      const _MyReportsSection(),
      const SizedBox(height: AppSizes.md),
      const _NearbyHeader(target: '/map'),
      _IncidentList(
        incidents: incidents,
        limit: 3,
        onTapRoute: '/map',
      ),
    ];
  }

  // ------------------------------------------------------------ volunteers

  List<Widget> _volunteerSections(AsyncValue<List<Incident>> incidents) {
    return <Widget>[
      const _AvailabilityCard(),
      const SizedBox(height: AppSizes.lg),
      const _MyAssignmentsSection(),
      const SizedBox(height: AppSizes.md),
      const _NearbyHeader(target: '/map'),
      _IncidentList(
        incidents: incidents,
        limit: 3,
        emergencyFirst: true,
        onTapRoute: '/volunteers',
      ),
    ];
  }

  // ------------------------------------------------- coordinators & admin

  List<Widget> _coordinatorSections(
    AsyncValue<List<Incident>> incidents, {
    required bool ngoMode,
  }) {
    return <Widget>[
      const _KpiGrid(),
      const SizedBox(height: AppSizes.lg),
      if (ngoMode) ...<Widget>[
        const _NgoSummaryCard(),
        const SizedBox(height: AppSizes.lg),
      ],
      const _RecentIncidentsHeader(),
      _IncidentList(
        incidents: incidents,
        limit: 5,
        onTapRoute: '/map',
      ),
    ];
  }

  // -------------------------------------------------------------- hospital

  List<Widget> _hospitalSections(AsyncValue<List<Incident>> incidents) {
    return <Widget>[
      const _HospitalCapacityCard(),
      const SizedBox(height: AppSizes.md),
      const _PreAlertSummaryCard(),
      const SizedBox(height: AppSizes.lg),
      const _RecentIncidentsHeader(),
      _IncidentList(
        incidents: incidents,
        limit: 4,
        emergencyFirst: true,
        onTapRoute: '/map',
      ),
    ];
  }
}

class _SectionGap extends StatelessWidget {
  const _SectionGap();

  @override
  Widget build(BuildContext context) => const SizedBox(height: AppSizes.lg);
}

// ------------------------------------------------------------------ header

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.name,
    required this.role,
    required this.unreadCount,
    required this.onNotificationTap,
    required this.onProfileTap,
  });

  final String name;
  final UserRole role;
  final int unreadCount;
  final VoidCallback onNotificationTap;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.tr(Formatters.greetingKey(DateTime.now())),
                style: AppText.body.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(name, style: AppText.headline),
              const SizedBox(height: 6),
              Wrap(
                spacing: AppSizes.sm,
                runSpacing: AppSizes.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  StatusChip(
                    label: role.shortLabel,
                    color: AppColors.primary,
                    icon: role.icon,
                  ),
                  Text(
                    role.greeting,
                    style: AppText.caption.copyWith(color: palette.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
        AppIconButton(
          icon: Icons.notifications_none,
          tooltip: context.tr('nav.notifications'),
          badgeCount: unreadCount,
          onPressed: onNotificationTap,
        ),
        InkWell(
          onTap: onProfileTap,
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: AppAvatar(name: name, statusColor: AppColors.success),
          ),
        ),
      ],
    );
  }
}

/// Cluster/event banner (Amber/Red) — PRD Volume II §4.2.
class _EventBanner extends ConsumerWidget {
  const _EventBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<DisasterEvent>> events = ref.watch(eventsProvider);
    final List<DisasterEvent>? list = events.valueOrNull;
    if (list == null || list.isEmpty) return const SizedBox.shrink();

    final DisasterEvent active = list.first;
    final bool red = active.eventClass == 'red';
    final Color color = red ? AppColors.critical : AppColors.warning;
    final AppPalette palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.lg),
      child: AppCard(
        tint: palette.tint(color),
        onTap: () => context.go('/map'),
        semanticLabel: 'Active event: ${active.name}',
        child: Row(
          children: <Widget>[
            AppIconTile(icon: Icons.crisis_alert, color: color),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'EVENT ${active.eventClass.toUpperCase()} · '
                    '${active.playbook ?? active.hazardType} playbook',
                    style: AppText.label.copyWith(color: color),
                  ),
                  const SizedBox(height: 4),
                  Text(active.name, style: AppText.bodyStrong),
                  const SizedBox(height: 2),
                  Text(
                    '${active.incidentCount} incidents · '
                    '${Formatters.compact(active.populationAffected ?? 0)} people in the area',
                    style: AppText.caption.copyWith(color: palette.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ quick actions

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final int columns = AppBreakpoints.quickActionColumns(context);
    final bool isCoordinator = role == UserRole.ngo ||
        role == UserRole.authority ||
        role == UserRole.superAdmin;

    final List<Widget> tiles = <Widget>[
      QuickActionTile(
        label: context.tr('dash.reportEmergency'),
        icon: Icons.emergency_outlined,
        color: AppColors.danger,
        onTap: () => context.go('/reports/new'),
      ),
      QuickActionTile(
        label: context.tr('dash.nearbyIncidents'),
        icon: Icons.location_on_outlined,
        color: AppColors.primary,
        onTap: () => context.go('/map'),
      ),
      if (role == UserRole.volunteer)
        QuickActionTile(
          label: context.tr('vol.title'),
          icon: Icons.volunteer_activism_outlined,
          color: AppColors.warning,
          onTap: () => context.go('/volunteers'),
        )
      else
        QuickActionTile(
          label: context.tr('dash.resources'),
          icon: Icons.inventory_2_outlined,
          color: AppColors.success,
          onTap: () => context.go('/resources'),
        ),
      if (role == UserRole.hospital)
        QuickActionTile(
          label: context.tr('hosp.title'),
          icon: Icons.local_hospital_outlined,
          color: AppColors.purple,
          onTap: () => context.go('/hospital'),
        )
      else if (isCoordinator)
        QuickActionTile(
          label: context.tr('nav.notifications'),
          icon: Icons.campaign_outlined,
          color: AppColors.purple,
          onTap: () => context.go('/notifications'),
        )
      else
        QuickActionTile(
          label: context.tr('dash.chatSupport'),
          icon: Icons.support_agent_outlined,
          color: AppColors.purple,
          onTap: () => context.go('/support'),
        ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: columns,
      mainAxisSpacing: AppSizes.md,
      crossAxisSpacing: AppSizes.md,
      childAspectRatio: columns == 2 ? 1.45 : 1.15,
      children: tiles,
    );
  }
}

// ------------------------------------------------------- victim: emergency

class _FocusIncidentCard extends ConsumerWidget {
  const _FocusIncidentCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Incident>> incidents = ref.watch(incidentsProvider);
    final List<Incident> active = ref.watch(activeIncidentsProvider);
    final Incident? focus = active.isEmpty ? null : active.first;
    if (incidents.isLoading) {
      return const AppCard(child: LoadingView());
    }
    if (focus == null) return const SizedBox.shrink();
    return _ActiveEmergencyCard(incident: focus);
  }
}

class _ActiveEmergencyCard extends StatelessWidget {
  const _ActiveEmergencyCard({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final double metres = incident.point.distanceTo(kDemoCenter);

    return AppCard(
      onTap: () => context.go('/map'),
      semanticLabel: 'Active emergency: ${incident.title}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const AppIconTile(icon: Icons.warning_amber_rounded, color: AppColors.danger),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.tr('dash.activeEmergency').toUpperCase(),
                      style: AppText.label.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(incident.title, style: AppText.title),
                  ],
                ),
              ),
              PriorityBadge(urgency: incident.severity),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              Icon(Icons.place_outlined, size: 15, color: palette.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${incident.addressText ?? 'Reported location'} · '
                  '${Formatters.distance(metres)}',
                  style: AppText.caption.copyWith(color: palette.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.xs,
            children: <Widget>[
              if (incident.victimsCount > 0)
                StatusChip(
                  label: '${incident.victimsCount} ${context.tr('dash.peopleTrapped')}',
                  color: AppColors.danger,
                  icon: Icons.groups_outlined,
                ),
              StatusChip(
                label: incident.status.label,
                color: AppColors.primary,
                icon: Icons.timelapse_outlined,
              ),
              if (incident.isSlaBreached)
                const StatusChip(
                  label: 'SLA breached',
                  color: AppColors.critical,
                  icon: Icons.timer_off_outlined,
                ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  label: context.tr('dash.viewDetails'),
                  variant: AppButtonVariant.secondary,
                  compact: true,
                  onPressed: () => context.go('/map'),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: AppButton(
                  label: 'Assign help',
                  icon: Icons.volunteer_activism_outlined,
                  compact: true,
                  onPressed: () => context.go('/volunteers'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------- victim: my reports

class _MyReportsSection extends ConsumerWidget {
  const _MyReportsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = AppPalette.of(context);
    final List<EmergencyReport> reports = ref.watch(myReportsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: context.tr('report.myReports'),
          actionLabel: context.tr('dash.viewAll'),
          onAction: () => context.go('/reports'),
        ),
        if (reports.isEmpty)
          AppCard(
            child: Row(
              children: <Widget>[
                const AppIconTile(icon: Icons.assignment_outlined, color: AppColors.primary),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Text(
                    context.tr('report.empty'),
                    style: AppText.body.copyWith(color: palette.textSecondary),
                  ),
                ),
              ],
            ),
          )
        else
          for (final EmergencyReport report in reports.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: AppCard(
                padding: const EdgeInsets.all(AppSizes.md),
                onTap: () => context.go('/reports'),
                semanticLabel: 'Report ${report.code}: ${report.description}',
                child: Row(
                  children: <Widget>[
                    AppIconTile(
                      icon: report.inputType.icon,
                      color: report.status.color,
                    ),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            report.description,
                            style: AppText.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${report.code} · ${report.status.label}',
                            style: AppText.caption.copyWith(color: palette.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (report.aiConfidence != null)
                      StatusChip(
                        label: 'AI ${(report.aiConfidence! * 100).round()}%',
                        color: AppColors.purple,
                      )
                    else
                      const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

// ------------------------------------------------------ volunteer sections

class _AvailabilityCard extends ConsumerWidget {
  const _AvailabilityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VolunteerAvailability availability = ref.watch(myAvailabilityProvider);
    final AppPalette palette = AppPalette.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconTile(icon: Icons.toggle_on_outlined, color: availability.color),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Responder status', style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      'You are ${availability.label.toLowerCase()} for dispatch',
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: availability == VolunteerAvailability.available,
                onChanged: (bool value) => ref
                    .read(myAvailabilityProvider.notifier)
                    .setAvailability(
                      value
                          ? VolunteerAvailability.available
                          : VolunteerAvailability.unavailable,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.sm,
            children: VolunteerAvailability.values
                .where((VolunteerAvailability a) => a != VolunteerAvailability.offline)
                .map(
                  (VolunteerAvailability item) => AppChoiceChip(
                    label: item.label,
                    color: item.color,
                    selected: item == availability,
                    onSelected: () =>
                        ref.read(myAvailabilityProvider.notifier).setAvailability(item),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _MyAssignmentsSection extends ConsumerWidget {
  const _MyAssignmentsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = AppPalette.of(context);
    final List<Assignment> tasks = ref.watch(myAssignmentsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: context.tr('vol.myTasks'),
          actionLabel: context.tr('dash.viewAll'),
          onAction: () => context.go('/volunteers'),
        ),
        if (tasks.isEmpty)
          AppCard(
            child: Row(
              children: <Widget>[
                const AppIconTile(icon: Icons.task_alt, color: AppColors.success),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Text(
                    context.tr('vol.noTasks'),
                    style: AppText.body.copyWith(color: palette.textSecondary),
                  ),
                ),
              ],
            ),
          )
        else
          for (final Assignment task in tasks.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: AppCard(
                onTap: () => context.go('/volunteers'),
                semanticLabel: 'Assignment: ${task.incidentTitle}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            task.incidentTitle ?? 'Assigned incident',
                            style: AppText.bodyStrong,
                          ),
                        ),
                        StatusChip(label: task.status.label, color: task.status.color),
                      ],
                    ),
                    const SizedBox(height: AppSizes.sm),
                    Text(
                      'ETA ${task.etaMinutes ?? '—'} min · ${task.distanceKm ?? '—'} km · '
                      '${task.incidentSeverity.label} priority',
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

// ------------------------------------------------------------ shared bits

class _NearbyHeader extends StatelessWidget {
  const _NearbyHeader({required this.target});

  final String target;

  @override
  Widget build(BuildContext context) {
    return SectionHeader(
      title: context.tr('dash.nearbyIncidents'),
      actionLabel: context.tr('dash.viewAll'),
      onAction: () => context.go(target),
    );
  }
}

class _RecentIncidentsHeader extends StatelessWidget {
  const _RecentIncidentsHeader();

  @override
  Widget build(BuildContext context) {
    return SectionHeader(
      title: context.tr('dash.recentIncidents'),
      actionLabel: context.tr('dash.viewAll'),
      onAction: () => context.go('/reports'),
    );
  }
}

class _IncidentList extends StatelessWidget {
  const _IncidentList({
    required this.incidents,
    required this.onTapRoute,
    this.limit = 4,
    this.emergencyFirst = false,
  });

  final AsyncValue<List<Incident>> incidents;
  final String onTapRoute;
  final int limit;
  final bool emergencyFirst;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return incidents.when(
      data: (List<Incident> list) {
        final List<Incident> ordered = List<Incident>.of(list)
          ..sort((Incident a, Incident b) {
            if (emergencyFirst) {
              final int bySeverity = b.severity.rank.compareTo(a.severity.rank);
              if (bySeverity != 0) return bySeverity;
            }
            return b.createdAt.compareTo(a.createdAt);
          });
        final List<Incident> visible = ordered.take(limit).toList(growable: false);
        if (visible.isEmpty) {
          return AppCard(
            child: Text(
              context.tr('common.empty'),
              style: AppText.body.copyWith(color: palette.textSecondary),
            ),
          );
        }
        return AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < visible.length; i++) ...<Widget>[
                if (i > 0) Divider(height: 1, color: palette.border),
                IncidentRow(
                  incident: visible[i],
                  onTap: () => context.go(onTapRoute),
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const AppCard(child: LoadingView()),
      error: (Object error, StackTrace _) => AppCard(
        child: ErrorView(
          message: error.toString(),
        ),
      ),
    );
  }
}

/// Reusable incident row — dashboard, live map sheet and reports screen.
class IncidentRow extends StatelessWidget {
  const IncidentRow({
    super.key,
    required this.incident,
    this.onTap,
    this.showDistance = true,
  });

  final Incident incident;
  final VoidCallback? onTap;
  final bool showDistance;

  @override
  Widget build(BuildContext context) {
    final double metres = incident.point.distanceTo(kDemoCenter);

    return AppListRow(
      onTap: onTap,
      leading: AppIconTile(
        icon: Icons.warning_amber_rounded,
        color: incident.severity.color,
      ),
      title: incident.title,
      subtitle: <String>[
        incident.severity.label,
        if (incident.victimsCount > 0) '${incident.victimsCount} trapped',
        if (showDistance) Formatters.distance(metres),
        Formatters.relativeTime(incident.createdAt),
      ].join(' · '),
      trailing: incident.isSlaBreached
          ? const Icon(Icons.timer_off_outlined, color: AppColors.critical, size: 18)
          : const Icon(Icons.chevron_right, size: 18),
    );
  }
}

// ---------------------------------------------------------------- KPIs

class _KpiGrid extends ConsumerWidget {
  const _KpiGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<IncidentKpis> kpis = ref.watch(kpisProvider);
    final int columns =
        MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet ? 4 : 2;

    return kpis.when(
      data: (IncidentKpis data) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: columns,
        mainAxisSpacing: AppSizes.md,
        crossAxisSpacing: AppSizes.md,
        childAspectRatio: columns == 2 ? 1.3 : 1.05,
        children: <Widget>[
          StatCard(
            label: context.tr('dash.activeIncidents'),
            value: '${data.activeIncidents}',
            icon: Icons.warning_amber_rounded,
            color: AppColors.danger,
            deltaLabel: '+${data.incidentDelta}',
            deltaUp: false,
          ),
          StatCard(
            label: context.tr('dash.peopleInNeed'),
            value: Formatters.compact(data.peopleInNeed),
            icon: Icons.groups_outlined,
            color: AppColors.primary,
            deltaLabel: '${data.peopleDeltaPercent.toStringAsFixed(0)}%',
          ),
          StatCard(
            label: context.tr('dash.volunteersActive'),
            value: '${data.volunteersActive}',
            icon: Icons.volunteer_activism_outlined,
            color: AppColors.success,
            deltaLabel: '${data.volunteerDeltaPercent.toStringAsFixed(0)}%',
          ),
          StatCard(
            label: context.tr('dash.resourcesAvailable'),
            value: '${data.resourcesAvailable}',
            icon: Icons.inventory_2_outlined,
            color: AppColors.warning,
            deltaLabel: '+${data.resourceDelta}',
          ),
        ],
      ),
      loading: () => const AppCard(child: LoadingView(label: 'Computing KPIs…')),
      error: (Object error, StackTrace _) => AppCard(
        child: ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(kpisProvider),
        ),
      ),
    );
  }
}

class _NgoSummaryCard extends ConsumerWidget {
  const _NgoSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ResourceRequest>> requests =
        ref.watch(resourceRequestsProvider);
    final int open = requests.valueOrNull
            ?.where((ResourceRequest r) => r.isOpen)
            .length ??
        0;

    return AppCard(
      onTap: () => context.go('/resources'),
      child: Row(
        children: <Widget>[
          const AppIconTile(icon: Icons.diversity_3_outlined, color: AppColors.success),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(context.tr('ngo.title'), style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  '$open open supply requests · coverage overlap 8%',
                  style: AppText.caption.copyWith(
                    color: AppPalette.of(context).textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ hospital bits

class _HospitalCapacityCard extends ConsumerWidget {
  const _HospitalCapacityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Hospital>> hospitals = ref.watch(hospitalsProvider);

    return hospitals.when(
      data: (List<Hospital> list) {
        if (list.isEmpty) {
          return const AppCard(child: EmptyState(icon: Icons.local_hospital_outlined, title: 'No hospitals linked'));
        }
        final int beds = list.fold<int>(0, (int sum, Hospital h) => sum + h.bedsAvailable);
        final int icu = list.fold<int>(0, (int sum, Hospital h) => sum + h.icuAvailable);
        final int inbound = list.fold<int>(0, (int sum, Hospital h) => sum + h.inboundCasualties);

        return AppCard(
          onTap: () => context.go('/hospital'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const AppIconTile(
                    icon: Icons.local_hospital_outlined,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Text(context.tr('hosp.capacity'), style: AppText.bodyStrong),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              Row(
                children: <Widget>[
                  Expanded(child: KeyValueRow(label: context.tr('hosp.beds'), value: '$beds')),
                  Expanded(child: KeyValueRow(label: context.tr('hosp.icu'), value: '$icu')),
                  Expanded(
                    child: KeyValueRow(
                      label: 'Inbound',
                      value: '$inbound',
                      valueColor: inbound > 0 ? AppColors.warning : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                '${list.where((Hospital h) => h.isCapacityFresh).length}/${list.length} '
                'hospitals reporting in the last 30 min',
                style: AppText.caption.copyWith(
                  color: AppPalette.of(context).textSecondary,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const AppCard(child: LoadingView(label: 'Reading capacity…')),
      error: (Object error, StackTrace _) => AppCard(
        child: ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(hospitalsProvider),
        ),
      ),
    );
  }
}

class _PreAlertSummaryCard extends ConsumerWidget {
  const _PreAlertSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CasualtyPreAlert>> alerts = ref.watch(preAlertsProvider);

    return alerts.when(
      data: (List<CasualtyPreAlert> list) {
        final int pending =
            list.where((CasualtyPreAlert a) => !a.isAcknowledged).length;
        return AppCard(
          onTap: () => context.go('/hospital'),
          child: Row(
            children: <Widget>[
              AppIconTile(
                icon: Icons.notifications_active_outlined,
                color: pending > 0 ? AppColors.danger : AppColors.success,
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(context.tr('hosp.preAlerts'), style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      pending == 0
                          ? 'All pre-alerts acknowledged'
                          : '$pending awaiting acknowledgement',
                      style: AppText.caption.copyWith(
                        color: AppPalette.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (Object error, StackTrace _) => const SizedBox.shrink(),
    );
  }
}
