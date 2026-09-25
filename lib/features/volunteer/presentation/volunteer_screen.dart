import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/models/incident.dart';
import '../../../core/models/volunteer.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/tactical_map.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../incidents/presentation/incident_providers.dart';
import 'volunteer_providers.dart';

/// Volunteer matching (design system §4.6) + the volunteer's own task board.
///
/// Coordinators/authorities dispatch from the ranked list; volunteers see the
/// same list plus "My assignments" with the full status lifecycle
/// (accept → en route → on scene → resolved).
class VolunteerScreen extends ConsumerStatefulWidget {
  const VolunteerScreen({super.key});

  @override
  ConsumerState<VolunteerScreen> createState() => _VolunteerScreenState();
}

class _VolunteerScreenState extends ConsumerState<VolunteerScreen> {
  double _radiusKm = 5;
  String? _skill;
  String? _selectedVolunteerId;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final UserRole role = ref.watch(effectiveRoleProvider);
    final MatchQuery query = MatchQuery(center: kOpsCenter, radiusKm: _radiusKm, skill: _skill);
    final AsyncValue<List<VolunteerProfile>> matches =
        ref.watch(volunteerMatchesProvider(query));
    final MatchSummary summary = ref.watch(matchSummaryProvider);
    final List<VolunteerProfile> list = matches.valueOrNull ?? const <VolunteerProfile>[];
    final VolunteerProfile? selected = _selected(list);
    final bool isVolunteer = role == UserRole.volunteer;

    return Scaffold(
      body: Column(
        children: <Widget>[
          const OfflineBanner(),
          SafeArea(
            bottom: false,
            child: AppResponsiveBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(context.tr('vol.title'), style: AppText.headline),
                            const SizedBox(height: 2),
                            Text(
                              'AI-ranked by distance, skills and availability',
                              style: AppText.caption.copyWith(color: palette.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => context.go('/map'),
                        icon: const Icon(Icons.map_outlined),
                        tooltip: context.tr('nav.map'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.sm),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (final double radius in <double>[2, 5, 10])
                          Padding(
                            padding: const EdgeInsets.only(right: AppSizes.sm),
                            child: AppChoiceChip(
                              label: '${radius.toStringAsFixed(0)} km',
                              selected: _radiusKm == radius,
                              onSelected: () => setState(() => _radiusKm = radius),
                            ),
                          ),
                        const SizedBox(width: AppSizes.sm),
                        for (final String skill in <String>['Medical', 'Rescue', 'Logistics'])
                          Padding(
                            padding: const EdgeInsets.only(right: AppSizes.sm),
                            child: AppChoiceChip(
                              label: skill,
                              color: AppColors.success,
                              selected: _skill == skill,
                              onSelected: () => setState(
                                () => _skill = _skill == skill ? null : skill,
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
              onRefresh: () => ref.read(myAssignmentsProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.lg,
                  AppSizes.md,
                  AppSizes.lg,
                  AppSizes.xxl,
                ),
                children: <Widget>[
                  if (summary.hasMatch) ...<Widget>[
                    _BestMatchBanner(summary: summary),
                    const SizedBox(height: AppSizes.md),
                  ],
                  matches.when(
                    data: (List<VolunteerProfile> data) {
                      if (data.isEmpty) {
                        return EmptyState(
                          icon: Icons.person_search_outlined,
                          title: 'No volunteers in range',
                          message: 'Widen the radius or clear the skill filter. '
                              'Escalation will broadcast to all responders.',
                          actionLabel: 'Widen to 10 km',
                          onAction: () => setState(() => _radiusKm = 10),
                        );
                      }
                      return Column(
                        children: data
                            .map(
                              (VolunteerProfile volunteer) => Padding(
                                padding: const EdgeInsets.only(bottom: AppSizes.md),
                                child: _VolunteerCard(
                                  volunteer: volunteer,
                                  selected: volunteer.id == _selectedVolunteerId,
                                  onSelect: () => setState(
                                    () => _selectedVolunteerId = volunteer.id,
                                  ),
                                  onAssign: () => _assign(volunteer),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      );
                    },
                    loading: () => const AppCard(child: LoadingView(label: 'Ranking responders…')),
                    error: (Object error, StackTrace _) => AppCard(
                      child: ErrorView(
                        message: error.toString(),
                        onRetry: () => ref.invalidate(volunteerMatchesProvider(query)),
                      ),
                    ),
                  ),
                  if (selected != null) ...<Widget>[
                    const SizedBox(height: AppSizes.sm),
                    _RecommendedRouteCard(
                      volunteer: selected,
                      onViewRoute: () => _showRoute(context, selected),
                    ),
                  ],
                  const SizedBox(height: AppSizes.xl),
                  if (isVolunteer) const _MyAssignmentsSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  VolunteerProfile? _selected(List<VolunteerProfile> list) {
    if (list.isEmpty) return null;
    if (_selectedVolunteerId == null) {
      return list.first;
    }
    for (final VolunteerProfile volunteer in list) {
      if (volunteer.id == _selectedVolunteerId) return volunteer;
    }
    return list.first;
  }

  Future<void> _assign(VolunteerProfile volunteer) async {
    final List<Incident> incidents = ref.read(activeIncidentsProvider);
    if (incidents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active incident to assign to.')),
      );
      return;
    }
    final Incident target = incidents.first;

    final Assignment assignment =
        await ref.read(dispatchControllerProvider).assign(
              incidentId: target.id,
              volunteer: volunteer,
            );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${volunteer.name} offered the task · '
          'ETA ${assignment.etaMinutes ?? volunteer.etaMinutes ?? 0} min',
        ),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => context.go('/map'),
        ),
      ),
    );
  }

  void _showRoute(BuildContext context, VolunteerProfile volunteer) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (BuildContext context, ScrollController controller) =>
            ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(AppSizes.xl, 0, AppSizes.xl, AppSizes.xxl),
          children: <Widget>[
            Text('Safe route to assignment', style: AppText.title),
            const SizedBox(height: AppSizes.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              child: SizedBox(
                height: 260,
                child: TacticalMap(
                  center: kOpsCenter,
                  metresPerPixel: 12,
                  showRadar: false,
                  pins: <MapPin>[
                    MapPin(
                      id: volunteer.id,
                      type: MapPinType.volunteer,
                      point: volunteer.point,
                      label: volunteer.name,
                      subtitle: volunteer.availability.label,
                    ),
                    MapPin(
                      id: 'target',
                      type: MapPinType.incident,
                      point: ref.read(activeIncidentsProvider).isEmpty
                          ? kOpsCenter
                          : ref.read(activeIncidentsProvider).first.point,
                      label: 'Incident',
                      urgency: UrgencyLevel.high.key,
                      isCriticalCluster: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            AppCard(
              child: Column(
                children: <Widget>[
                  KeyValueRow(
                    label: 'Distance',
                    value: Formatters.distance(volunteer.distanceMetres ?? 0),
                  ),
                  KeyValueRow(
                    label: 'ETA',
                    value: '${volunteer.etaMinutes ?? 0} min',
                  ),
                  const KeyValueRow(
                    label: 'Hazards avoided',
                    value: '2 (flooded underpass, debris)',
                  ),
                  const KeyValueRow(label: 'Route safety score', value: '96%'),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            AppButton(
              label: 'Start navigation',
              icon: Icons.navigation_outlined,
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Navigation started (hazard-aware).')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BestMatchBanner extends StatelessWidget {
  const _BestMatchBanner({required this.summary});

  final MatchSummary summary;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return AppCard(
      tint: palette.tint(AppColors.success),
      child: Row(
        children: <Widget>[
          const AppIconTile(icon: Icons.verified_outlined, color: AppColors.success),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(context.tr('vol.bestMatch'), style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  '${summary.count} ${context.tr('vol.within')} '
                  '${summary.radiusKm.toStringAsFixed(0)} km'
                  '${summary.etaMinutes == null ? '' : ' · fastest ETA ${summary.etaMinutes} min'}',
                  style: AppText.caption.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VolunteerCard extends StatelessWidget {
  const _VolunteerCard({
    required this.volunteer,
    required this.selected,
    required this.onSelect,
    required this.onAssign,
  });

  final VolunteerProfile volunteer;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return AppCard(
      onTap: onSelect,
      semanticLabel: '${volunteer.name}, ${volunteer.availability.label}, '
          '${volunteer.distanceLabel} away',
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              AppAvatar(
                name: volunteer.name,
                size: 46,
                statusColor: volunteer.availability.color,
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            volunteer.name,
                            style: AppText.bodyStrong,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (volunteer.isVerified) ...<Widget>[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, size: 14, color: AppColors.primary),
                        ],
                        if (volunteer.matchRank == 1) ...<Widget>[
                          const SizedBox(width: AppSizes.sm),
                          const StatusChip(label: 'BEST', color: AppColors.success),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      <String>[
                        if (volunteer.skills.isNotEmpty) volunteer.skills.join(' · '),
                        '${volunteer.distanceLabel} away',
                        if (volunteer.rating > 0) '★ ${volunteer.rating}',
                      ].join(' · '),
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              StatusChip(
                label: volunteer.availability.label,
                color: volunteer.availability.color,
                icon: Icons.circle,
              ),
              const SizedBox(width: AppSizes.sm),
              if (volunteer.etaMinutes != null)
                StatusChip(
                  label: 'ETA ${volunteer.etaMinutes} min',
                  color: AppColors.primary,
                  icon: Icons.timer_outlined,
                ),
              const Spacer(),
              AppButton(
                label: context.tr('vol.assign'),
                compact: true,
                expand: false,
                icon: Icons.send_and_archive_outlined,
                onPressed: onAssign,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecommendedRouteCard extends ConsumerWidget {
  const _RecommendedRouteCard({
    required this.volunteer,
    required this.onViewRoute,
  });

  final VolunteerProfile volunteer;
  final VoidCallback onViewRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = AppPalette.of(context);
    final List<Incident> incidents = ref.watch(activeIncidentsProvider);
    final Incident? target = incidents.isEmpty ? null : incidents.first;
    final RouteQuery? query = target == null
        ? null
        : RouteQuery(origin: volunteer.point, destination: target.point);

    if (query == null) return const SizedBox.shrink();

    final AsyncValue<RoutePlan> route = ref.watch(routePlanProvider(query));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const AppIconTile(icon: Icons.alt_route_outlined, color: AppColors.primary),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(context.tr('vol.recommendedRoute'), style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    route.when(
                      data: (RoutePlan plan) => Text(
                        '${plan.callout} · ${plan.hazardsAvoided} hazards avoided',
                        style: AppText.caption.copyWith(color: palette.textSecondary),
                      ),
                      loading: () => Text(
                        'Computing safest route…',
                        style: AppText.caption.copyWith(color: palette.textSecondary),
                      ),
                      error: (Object error, StackTrace _) => Text(
                        'Route unavailable — showing distance estimate',
                        style: AppText.caption.copyWith(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
              AppButton(
                label: context.tr('vol.viewRoute'),
                compact: true,
                expand: false,
                variant: AppButtonVariant.secondary,
                onPressed: onViewRoute,
              ),
            ],
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
    final AsyncValue<List<Assignment>> assignments = ref.watch(myAssignmentsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: context.tr('vol.myTasks'),
          actionLabel: 'History',
          onAction: () => context.go('/reports'),
        ),
        assignments.when(
          data: (List<Assignment> list) {
            final List<Assignment> active = list
                .where((Assignment a) =>
                    a.status.isActive || a.status == AssignmentStatus.offered)
                .toList(growable: false);
            if (active.isEmpty) {
              return AppCard(
                child: Text(
                  context.tr('vol.noTasks'),
                  style: AppText.body.copyWith(color: palette.textSecondary),
                ),
              );
            }
            return Column(
              children: active
                  .map(
                    (Assignment assignment) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSizes.md),
                      child: _AssignmentCard(
                        assignment: assignment,
                        onAdvance: (AssignmentStatus status) => ref
                            .read(myAssignmentsProvider.notifier)
                            .advance(assignment.id, status),
                      ),
                    ),
                  )
                  .toList(growable: false),
            );
          },
          loading: () => const AppCard(child: LoadingView()),
          error: (Object error, StackTrace _) => AppCard(
            child: ErrorView(
              message: error.toString(),
              onRetry: () => ref.read(myAssignmentsProvider.notifier).refresh(),
            ),
          ),
        ),
      ],
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({required this.assignment, required this.onAdvance});

  final Assignment assignment;
  final ValueChanged<AssignmentStatus> onAdvance;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AssignmentStatus next = _nextStatus(assignment.status);

    return AppCard(
      semanticLabel: 'Assignment ${assignment.incidentTitle ?? ''} '
          '${assignment.status.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  assignment.incidentTitle ?? 'Assigned incident',
                  style: AppText.bodyStrong,
                ),
              ),
              StatusChip(
                label: assignment.status.label,
                color: assignment.status.color,
                filled: true,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.xs,
            children: <Widget>[
              PriorityBadge(urgency: assignment.incidentSeverity, compact: true),
              if (assignment.etaMinutes != null)
                StatusChip(
                  label: 'ETA ${assignment.etaMinutes} min',
                  color: AppColors.primary,
                  icon: Icons.timer_outlined,
                ),
              if (assignment.distanceKm != null)
                StatusChip(
                  label: '${assignment.distanceKm!.toStringAsFixed(1)} km',
                  color: AppColors.warning,
                  icon: Icons.route_outlined,
                ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  label: next.label,
                  compact: true,
                  variant: next == AssignmentStatus.resolved
                      ? AppButtonVariant.success
                      : AppButtonVariant.primary,
                  onPressed: () => onAdvance(next),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              AppButton(
                label: 'Navigate',
                compact: true,
                expand: false,
                variant: AppButtonVariant.secondary,
                icon: Icons.navigation_outlined,
                onPressed: () => context.go('/map'),
              ),
            ],
          ),
          if (assignment.status == AssignmentStatus.offered)
            Padding(
              padding: const EdgeInsets.only(top: AppSizes.sm),
              child: Text(
                'Offer expires in 10 minutes — after that AIDRA re-matches automatically.',
                style: AppText.caption.copyWith(color: palette.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  AssignmentStatus _nextStatus(AssignmentStatus current) => switch (current) {
        AssignmentStatus.offered => AssignmentStatus.accepted,
        AssignmentStatus.accepted => AssignmentStatus.enRoute,
        AssignmentStatus.enRoute => AssignmentStatus.onScene,
        AssignmentStatus.onScene => AssignmentStatus.resolved,
        _ => AssignmentStatus.accepted,
      };
}
