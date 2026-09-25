import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/models/geo_point.dart';
import '../../../core/models/hospital.dart';
import '../../../core/models/incident.dart';
import '../../../core/models/resource_item.dart';
import '../../../core/models/volunteer.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/tactical_map.dart';
import '../../hospital/presentation/hospital_providers.dart';
import '../../incidents/presentation/incident_providers.dart';
import '../../resources/presentation/resource_providers.dart';
import '../../volunteer/presentation/volunteer_providers.dart';

/// Live map (design system §4.5): every incident, responder, hospital and
/// resource on one surface, with critical clusters pulsing for attention.
class LiveMapScreen extends ConsumerStatefulWidget {
  const LiveMapScreen({super.key});

  @override
  ConsumerState<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends ConsumerState<LiveMapScreen> {
  final Set<MapPinType> _visibleLayers = <MapPinType>{
    MapPinType.incident,
    MapPinType.volunteer,
    MapPinType.hospital,
    MapPinType.resource,
  };
  String? _selectedIncidentId;
  double _zoomLevel = 1;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AsyncValue<List<Incident>> incidents = ref.watch(incidentsProvider);
    final List<Incident> incidentList = incidents.valueOrNull ?? const <Incident>[];
    final List<VolunteerProfile> volunteers =
        ref.watch(volunteerMatchesProvider(const MatchQuery(center: kOpsCenter)))
                .valueOrNull ??
            const <VolunteerProfile>[];
    final List<Hospital> hospitals =
        ref.watch(hospitalsProvider).valueOrNull ?? const <Hospital>[];
    final List<ResourceItem> resources =
        ref.watch(inventoryProvider).valueOrNull ?? const <ResourceItem>[];

    final List<MapPin> pins = _buildPins(
      incidents: incidentList,
      volunteers: volunteers,
      hospitals: hospitals,
      resources: resources,
    );

    final Incident? selected = _findById(incidentList, _selectedIncidentId);

    return Scaffold(
      body: Column(
        children: <Widget>[
          const OfflineBanner(),
          AppTopBar(
            title: context.tr('map.title'),
            subtitle: '${_visibleIncidentCount(incidentList)} active · '
                '${volunteers.length} responders · ${hospitals.length} hospitals',
            onBack: () => context.go('/home'),
            actions: <Widget>[
              AppIconButton(
                icon: Icons.search,
                tooltip: context.tr('common.search'),
                onPressed: () => _showSearchSheet(context, incidentList),
              ),
              AppIconButton(
                icon: Icons.my_location,
                tooltip: context.tr('map.yourLocation'),
                onPressed: () => setState(() {
                  _zoomLevel = 1.6;
                  _selectedIncidentId = null;
                }),
              ),
            ],
          ),
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: TacticalMap(
                    pins: pins,
                    center: kOpsCenter,
                    metresPerPixel: 14 / _zoomLevel,
                    selectedPinId: _selectedIncidentId,
                    onPinTap: _onPinTap,
                  ),
                ),
                Positioned(
                  left: AppSizes.md,
                  right: AppSizes.md,
                  top: AppSizes.md,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: MapPinType.values
                          .where((MapPinType type) => type != MapPinType.user)
                          .map(
                            (MapPinType type) => Padding(
                              padding: const EdgeInsets.only(right: AppSizes.sm),
                              child: LegendChip(
                                label: _layerLabel(context, type),
                                color: type.color,
                                selected: _visibleLayers.contains(type),
                                onTap: () => setState(() {
                                  if (_visibleLayers.contains(type)) {
                                    _visibleLayers.remove(type);
                                  } else {
                                    _visibleLayers.add(type);
                                  }
                                }),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ),
                Positioned(
                  left: AppSizes.md,
                  right: AppSizes.md,
                  bottom: AppSizes.md,
                  child: Column(
                    children: <Widget>[
                      if (selected != null) _SelectedIncidentCard(incident: selected),
                      const SizedBox(height: AppSizes.sm),
                      AppCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.md,
                          vertical: AppSizes.sm,
                        ),
                        onTap: () => _showNearbySheet(context),
                        semanticLabel: 'Show nearby incidents list',
                        child: Row(
                          children: <Widget>[
                            const AppIconTile(
                              icon: Icons.list_alt_outlined,
                              color: AppColors.primary,
                              size: 34,
                            ),
                            const SizedBox(width: AppSizes.md),
                            Expanded(
                              child: Text(
                                '${incidentList.length} incidents in view — tap for the ranked list',
                                style: AppText.bodyStrong,
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_up),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: AppSizes.md,
                  bottom: 120,
                  child: Column(
                    children: <Widget>[
                      _MapControl(
                        icon: Icons.add,
                        tooltip: 'Zoom in',
                        onTap: () => setState(() => _zoomLevel = (_zoomLevel * 1.4).clamp(0.6, 3)),
                      ),
                      const SizedBox(height: AppSizes.sm),
                      _MapControl(
                        icon: Icons.remove,
                        tooltip: 'Zoom out',
                        onTap: () => setState(() => _zoomLevel = (_zoomLevel / 1.4).clamp(0.6, 3)),
                      ),
                    ],
                  ),
                ),
                if (incidents.isLoading)
                  Positioned(
                    top: 70,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: StatusChip(
                        label: 'Refreshing feed…',
                        color: palette.textSecondary,
                        icon: Icons.sync,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<MapPin> _buildPins({
    required List<Incident> incidents,
    required List<VolunteerProfile> volunteers,
    required List<Hospital> hospitals,
    required List<ResourceItem> resources,
  }) {
    final List<MapPin> pins = <MapPin>[];

    if (_visibleLayers.contains(MapPinType.incident)) {
      for (final Incident incident in incidents) {
        pins.add(
          MapPin(
            id: incident.id,
            type: MapPinType.incident,
            point: incident.point,
            label: incident.title,
            subtitle: '${incident.severity.label} · ${incident.victimsCount} trapped',
            urgency: incident.severity.key,
            isCriticalCluster: incident.severity == UrgencyLevel.critical ||
                incident.isSlaBreached,
          ),
        );
      }
    }

    if (_visibleLayers.contains(MapPinType.volunteer)) {
      for (final VolunteerProfile volunteer in volunteers) {
        pins.add(
          MapPin(
            id: volunteer.id,
            type: MapPinType.volunteer,
            point: volunteer.point,
            label: volunteer.name,
            subtitle: volunteer.availability.label,
          ),
        );
      }
    }

    if (_visibleLayers.contains(MapPinType.hospital)) {
      for (final Hospital hospital in hospitals) {
        pins.add(
          MapPin(
            id: hospital.id,
            type: MapPinType.hospital,
            point: hospital.point,
            label: hospital.name,
            subtitle: '${hospital.bedsAvailable} beds · ${hospital.icuAvailable} ICU',
          ),
        );
      }
    }

    if (_visibleLayers.contains(MapPinType.resource)) {
      for (final ResourceItem item in resources) {
        final GeoPoint? point = item.point;
        if (point == null) continue;
        pins.add(
          MapPin(
            id: item.id,
            type: MapPinType.resource,
            point: point,
            label: item.name,
            subtitle: '${item.quantity.toStringAsFixed(0)} ${item.unit}',
          ),
        );
      }
    }

    pins.add(
      const MapPin(
        id: 'me',
        type: MapPinType.user,
        point: kOpsCenter,
        label: 'You',
      ),
    );

    return pins;
  }

  Incident? _findById(List<Incident> incidents, String? id) {
    if (id == null) return null;
    for (final Incident incident in incidents) {
      if (incident.id == id) return incident;
    }
    return null;
  }

  void _onPinTap(MapPin pin) {
    if (pin.type == MapPinType.incident) {
      setState(() => _selectedIncidentId = pin.id);
      return;
    }
    _showInfoSheet(
      context,
      title: pin.label,
      message: pin.subtitle ?? '',
      icon: pin.type.icon,
      color: pin.type.color,
    );
  }

  void _showNearbySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (BuildContext context, ScrollController controller) {
          final List<Incident> ranked = ref.read(activeIncidentsProvider);
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(AppSizes.xl, 0, AppSizes.xl, AppSizes.xxl),
            children: <Widget>[
              Text('Nearby incidents', style: AppText.title),
              const SizedBox(height: 2),
              Text(
                'Ranked by severity, then distance (AI triage order).',
                style: AppText.caption.copyWith(
                  color: AppPalette.of(context).textSecondary,
                ),
              ),
              const SizedBox(height: AppSizes.md),
              if (ranked.isEmpty)
                const EmptyState(
                  icon: Icons.check_circle_outline,
                  title: 'No active incidents',
                  message: 'Nothing needs dispatch in your area right now.',
                )
              else
                for (final Incident incident in ranked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.sm),
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSizes.sm),
                      onTap: () {
                        setState(() => _selectedIncidentId = incident.id);
                        Navigator.of(context).pop();
                      },
                      child: _RankedIncidentRow(incident: incident),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  void _showSearchSheet(BuildContext context, List<Incident> incidents) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSizes.xl, 0, AppSizes.xl, AppSizes.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.tr('common.search'), style: AppText.title),
            const SizedBox(height: AppSizes.md),
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.tr('map.searchHint'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (String value) {
                Navigator.of(sheetContext).pop();
                _showInfoSheet(
                  context,
                  title: 'Search: $value',
                  message: '${incidents.length} incidents match your area. '
                      'Server-side search covers locations, incidents and people.',
                  icon: Icons.search,
                  color: AppColors.primary,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoSheet(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color color,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSizes.xl, 0, AppSizes.xl, AppSizes.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                AppIconTile(icon: icon, color: color),
                const SizedBox(width: AppSizes.md),
                Expanded(child: Text(title, style: AppText.title)),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            Text(message, style: AppText.body),
            const SizedBox(height: AppSizes.lg),
            AppButton(
              label: context.tr('common.close'),
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      ),
    );
  }

  String _layerLabel(BuildContext context, MapPinType type) =>
      context.tr(type.legendKey);

  int _visibleIncidentCount(List<Incident> incidents) =>
      incidents.where((Incident i) => i.isActive).length;
}

class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        child: SizedBox(
          height: 42,
          width: 42,
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, size: 20, color: palette.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// The floating "5 people trapped — High Priority" callout from the design.
class _SelectedIncidentCard extends StatelessWidget {
  const _SelectedIncidentCard({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final double metres = incident.point.distanceTo(kOpsCenter);

    return AppCard(
      semanticLabel: '${incident.title}, ${incident.severity.label} priority',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconTile(icon: Icons.warning_amber_rounded, color: incident.severity.color),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(incident.title, style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      '${incident.victimsCount} ${context.tr('dash.peopleTrapped')} · '
                      '${Formatters.distance(metres)} · '
                      '${Formatters.relativeTime(incident.createdAt)}',
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              PriorityBadge(urgency: incident.severity),
            ],
          ),
          if (incident.needLabels.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSizes.sm),
            Wrap(
              spacing: AppSizes.sm,
              runSpacing: AppSizes.xs,
              children: incident.needLabels
                  .map(
                    (String need) => StatusChip(
                      label: need,
                      color: AppColors.primary,
                      icon: Icons.check_circle_outline,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  label: 'Assign help',
                  icon: Icons.volunteer_activism_outlined,
                  compact: true,
                  onPressed: () => context.go('/volunteers'),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              AppButton(
                label: 'Route',
                icon: Icons.alt_route_outlined,
                compact: true,
                expand: false,
                variant: AppButtonVariant.secondary,
                onPressed: () => context.go('/volunteers'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RankedIncidentRow extends StatelessWidget {
  const _RankedIncidentRow({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context) {
    final double metres = incident.point.distanceTo(kOpsCenter);
    return Row(
      children: <Widget>[
        AppIconTile(
          icon: Icons.warning_amber_rounded,
          color: incident.severity.color,
          size: 36,
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(incident.title, style: AppText.bodyStrong),
              const SizedBox(height: 2),
              Text(
                '${incident.severity.label} · ${incident.victimsCount} at risk · '
                '${Formatters.distance(metres)} · ${incident.code}',
                style: AppText.caption.copyWith(
                  color: AppPalette.of(context).textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (incident.isSlaBreached)
          const Icon(Icons.timer_off_outlined, size: 18, color: AppColors.critical)
        else
          const Icon(Icons.chevron_right, size: 18),
      ],
    );
  }
}
