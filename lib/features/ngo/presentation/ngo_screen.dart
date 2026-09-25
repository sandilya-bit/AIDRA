import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/models/incident.dart';
import '../../../core/models/resource_item.dart';
import '../../../core/models/volunteer.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/tactical_map.dart';
import '../../incidents/presentation/incident_providers.dart';
import '../../resources/presentation/resource_providers.dart';
import '../../volunteer/presentation/volunteer_providers.dart';

/// NGO coordination (design system §11.8).
///
/// Coverage map (who owns which area), field teams with live status, and the
/// inter-org request board — the anti-duplication layer from FR-403/404.
class NgoScreen extends ConsumerWidget {
  const NgoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = AppPalette.of(context);
    final List<Incident> incidents = ref.watch(activeIncidentsProvider);
    final List<VolunteerProfile> teams =
        ref.watch(volunteerMatchesProvider(const MatchQuery(center: kOpsCenter)))
                .valueOrNull ??
            const <VolunteerProfile>[];
    final AsyncValue<List<ResourceRequest>> requests =
        ref.watch(resourceRequestsProvider);
    final int openRequests =
        requests.valueOrNull?.where((ResourceRequest r) => r.isOpen).length ?? 0;

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
                        Text(context.tr('ngo.title'), style: AppText.headline),
                        const SizedBox(height: 2),
                        Text(
                          'Red Crescent Hyderabad · ${teams.length} field responders',
                          style: AppText.caption.copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.go('/resources'),
                    icon: const Icon(Icons.inventory_2_outlined),
                    tooltip: context.tr('nav.resources'),
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
                AppCard(
                  padding: const EdgeInsets.all(AppSizes.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const AppIconTile(
                            icon: Icons.map_outlined,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: AppSizes.md),
                          Expanded(
                            child: Text(
                              context.tr('ngo.coverage'),
                              style: AppText.bodyStrong,
                            ),
                          ),
                          const StatusChip(
                            label: 'OVERLAP 8%',
                            color: AppColors.warning,
                            icon: Icons.warning_amber_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSizes.md),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                        child: SizedBox(
                          height: 220,
                          child: TacticalMap(
                            center: kOpsCenter,
                            metresPerPixel: 18,
                            interactive: false,
                            pins: <MapPin>[
                              for (final Incident incident in incidents.take(6))
                                MapPin(
                                  id: 'ngo-${incident.id}',
                                  type: MapPinType.incident,
                                  point: incident.point,
                                  label: incident.title,
                                  urgency: incident.severity.key,
                                  isCriticalCluster:
                                      incident.severity == UrgencyLevel.critical,
                                ),
                              for (final VolunteerProfile team in teams.take(4))
                                MapPin(
                                  id: 'team-${team.id}',
                                  type: MapPinType.volunteer,
                                  point: team.point,
                                  label: team.name,
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSizes.sm),
                      Text(
                        'Your teams cover the riverbank corridor and two relief camps. '
                        'Goonj Relief runs the northern cluster — coordinate before '
                        'deploying there to avoid duplication.',
                        style: AppText.caption.copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                SectionHeader(
                  title: context.tr('ngo.teams'),
                  trailing: StatusChip(
                    label: '${teams.where((VolunteerProfile t) => t.availability == VolunteerAvailability.available).length} available',
                    color: AppColors.success,
                  ),
                ),
                for (final VolunteerProfile team in teams.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.sm),
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSizes.sm),
                      onTap: () => context.go('/volunteers'),
                      semanticLabel: '${team.name}, ${team.availability.label}',
                      child: Row(
                        children: <Widget>[
                          AppAvatar(
                            name: team.name,
                            size: 40,
                            statusColor: team.availability.color,
                          ),
                          const SizedBox(width: AppSizes.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(team.name, style: AppText.bodyStrong),
                                const SizedBox(height: 2),
                                Text(
                                  '${team.skills.join(' · ')} · '
                                  '${team.distanceLabel} · '
                                  '${team.completedAssignments} completed',
                                  style: AppText.caption
                                      .copyWith(color: palette.textSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          AppButton(
                            label: context.tr('ngo.deploy'),
                            compact: true,
                            expand: false,
                            variant: AppButtonVariant.secondary,
                            onPressed: () => context.go('/volunteers'),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: AppSizes.lg),
                SectionHeader(
                  title: context.tr('ngo.requests'),
                  actionLabel: context.tr('dash.viewAll'),
                  onAction: () => context.go('/resources'),
                  trailing: StatusChip(
                    label: '$openRequests open',
                    color: openRequests > 0 ? AppColors.warning : AppColors.success,
                  ),
                ),
                requests.when(
                  data: (List<ResourceRequest> list) {
                    if (list.isEmpty) {
                      return AppCard(
                        child: Text(
                          'No requests on the board.',
                          style: AppText.body.copyWith(color: palette.textSecondary),
                        ),
                      );
                    }
                    return AppCard(
                      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
                      child: Column(
                        children: <Widget>[
                          for (final ResourceRequest request in list.take(4))
                            AppListRow(
                              leading: AppIconTile(
                                icon: Icons.swap_horiz,
                                color: request.urgency.color,
                              ),
                              title:
                                  '${request.code} · ${request.requestingOrgName}',
                              subtitle: <String>[
                                request.status.label,
                                request.lines.map((ResourceRequestLine l) => l.summary).join(', '),
                                if (request.neededBy != null)
                                  'needed by ${Formatters.clock(request.neededBy!)}',
                              ].join(' · '),
                              trailing: PriorityBadge(
                                urgency: request.urgency,
                                compact: true,
                              ),
                              onTap: () => context.go('/resources'),
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
                const SizedBox(height: AppSizes.lg),
                AppCard(
                  tint: palette.tint(AppColors.success),
                  child: Row(
                    children: <Widget>[
                      const AppIconTile(icon: Icons.handshake_outlined, color: AppColors.success),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('Mutual aid enabled', style: AppText.bodyStrong),
                            const SizedBox(height: 2),
                            Text(
                              'You can draw on partner NGO stock and volunteers '
                              'inside the affected polygon.',
                              style: AppText.caption.copyWith(color: palette.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
