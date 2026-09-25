import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/models/resource_item.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import 'resource_providers.dart';

/// Resource management (design system §11.7).
///
/// Inventory with burn-rate projections, low-stock alerts, the inter-org
/// request board, and shelter occupancy from the recovery playbooks.
class ResourcesScreen extends ConsumerStatefulWidget {
  const ResourcesScreen({super.key});

  @override
  ConsumerState<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends ConsumerState<ResourcesScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

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
                  Text(context.tr('res.title'), style: AppText.headline),
                  const SizedBox(height: 2),
                  Text(
                    'Inventory, burn rate and inter-org coordination',
                    style: AppText.caption.copyWith(color: palette.textSecondary),
                  ),
                  const SizedBox(height: AppSizes.md),
                  SegmentedTabs(
                    labels: <String>[
                      context.tr('res.inventory'),
                      context.tr('res.requests'),
                      'Shelters',
                    ],
                    selectedIndex: _tab,
                    onChanged: (int index) => setState(() => _tab = index),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: switch (_tab) {
              0 => const _InventoryTab(),
              1 => const _RequestsTab(),
              _ => const _SheltersTab(),
            },
          ),
        ],
      ),
    );
  }
}

class _InventoryTab extends ConsumerWidget {
  const _InventoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = AppPalette.of(context);
    final AsyncValue<List<ResourceItem>> inventory = ref.watch(inventoryProvider);
    final List<ResourceItem> lowStock = ref.watch(lowStockProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.md, AppSizes.lg, AppSizes.xxl),
      children: <Widget>[
        if (lowStock.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.lg),
            child: AppCard(
              tint: palette.tint(AppColors.warning),
              child: Row(
                children: <Widget>[
                  const AppIconTile(icon: Icons.inventory_outlined, color: AppColors.warning),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${context.tr('res.lowStock')} · ${lowStock.length} items',
                          style: AppText.bodyStrong,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lowStock.map((ResourceItem r) => r.name).join(', '),
                          style: AppText.caption.copyWith(color: palette.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        inventory.when(
          data: (List<ResourceItem> items) => Column(
            children: items
                .map(
                  (ResourceItem item) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.md),
                    child: _ResourceCard(item: item),
                  ),
                )
                .toList(growable: false),
          ),
          loading: () => const AppCard(child: LoadingView(label: 'Reading inventory…')),
          error: (Object error, StackTrace _) => AppCard(
            child: ErrorView(
              message: error.toString(),
              onRetry: () => ref.read(inventoryProvider.notifier).refresh(),
            ),
          ),
        ),
      ],
    );
  }
}

class _ResourceCard extends ConsumerWidget {
  const _ResourceCard({required this.item});

  final ResourceItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = AppPalette.of(context);
    final double? coverDays = item.daysOfCover;
    final Color statusColor = item.isLowStock ? AppColors.danger : AppColors.success;

    return AppCard(
      semanticLabel: '${item.name}, ${item.quantity.toStringAsFixed(0)} ${item.unit} in stock',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconTile(icon: item.category.icon, color: statusColor),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(item.name, style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        '${item.quantity.toStringAsFixed(0)} ${item.unit} ${context.tr('res.inStock')}',
                        if (item.distanceMetres != null)
                          Formatters.distance(item.distanceMetres!),
                        if (item.ownerOrgName != null) item.ownerOrgName!,
                      ].join(' · '),
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: item.isLowStock ? context.tr('res.lowStock').toUpperCase() : 'OK',
                color: statusColor,
                filled: true,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          CapacityBar(
            label: 'Against threshold ${item.minThreshold.toStringAsFixed(0)} ${item.unit}',
            used: item.quantity.round(),
            total: (item.minThreshold * 3).round().clamp(1, 1 << 30),
            color: statusColor,
          ),
          const SizedBox(height: AppSizes.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: KeyValueRow(
                  label: 'Used 24h',
                  value: '${item.consumedLast24h.toStringAsFixed(0)} ${item.unit}',
                ),
              ),
              Expanded(
                child: KeyValueRow(
                  label: 'Days of cover',
                  value: coverDays == null ? '—' : coverDays.toStringAsFixed(1),
                  valueColor: coverDays != null && coverDays < 1.5
                      ? AppColors.danger
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  label: context.tr('res.dispatch'),
                  compact: true,
                  icon: Icons.local_shipping_outlined,
                  onPressed: () => _dispatch(context, ref, item),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              AppButton(
                label: 'Consume',
                compact: true,
                expand: false,
                variant: AppButtonVariant.secondary,
                onPressed: () => ref.read(inventoryProvider.notifier).recordMovement(
                      resourceId: item.id,
                      quantity: 50,
                      movementType: 'consume',
                      note: 'Distribution point consumption',
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _dispatch(BuildContext context, WidgetRef ref, ResourceItem item) {
    final double suggested = (item.quantity * 0.25).clamp(1, item.quantity);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => Padding(
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
            Text('Dispatch ${item.name}', style: AppText.title),
            const SizedBox(height: AppSizes.sm),
            Text(
              '${suggested.toStringAsFixed(0)} ${item.unit} will be committed to the '
              'open flood-rescue incident. The movement is recorded in the ledger '
              'and forwarded to the receiving NGO.',
              style: AppText.body.copyWith(color: AppPalette.of(context).textSecondary),
            ),
            const SizedBox(height: AppSizes.lg),
            AppButton(
              label: 'Confirm dispatch',
              icon: Icons.check_circle_outline,
              onPressed: () {
                ref.read(inventoryProvider.notifier).recordMovement(
                      resourceId: item.id,
                      quantity: suggested,
                      movementType: 'dispatch',
                      note: 'Flood rescue — critical incident',
                    );
                Navigator.of(sheetContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${suggested.toStringAsFixed(0)} ${item.unit} dispatched.',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ResourceRequest>> requests =
        ref.watch(resourceRequestsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.md, AppSizes.lg, AppSizes.xxl),
      children: <Widget>[
        requests.when(
          data: (List<ResourceRequest> list) {
            if (list.isEmpty) {
              return const EmptyState(
                icon: Icons.inbox_outlined,
                title: 'No open requests',
                message: 'Inter-organization supply requests appear here.',
              );
            }
            return Column(
              children: list
                  .map(
                    (ResourceRequest request) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSizes.md),
                      child: _RequestCard(
                        request: request,
                        onAdvance: (RequestStatus status) => ref
                            .read(resourceRequestsProvider.notifier)
                            .updateStatus(request.id, status),
                      ),
                    ),
                  )
                  .toList(growable: false),
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

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onAdvance});

  final ResourceRequest request;
  final ValueChanged<RequestStatus> onAdvance;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final bool dispatched = request.status == RequestStatus.dispatched ||
        request.status == RequestStatus.fulfilled;

    return AppCard(
      semanticLabel: 'Request ${request.code} from ${request.requestingOrgName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconTile(icon: Icons.swap_horiz, color: request.urgency.color),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(request.code, style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      '${request.requestingOrgName} → '
                      '${request.fulfillingOrgName ?? 'any partner'}',
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: request.status.label,
                color: dispatched ? AppColors.success : AppColors.warning,
                filled: true,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          for (final ResourceRequestLine line in request.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: <Widget>[
                  Icon(line.category.icon, size: 16, color: palette.textSecondary),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(child: Text(line.summary, style: AppText.body)),
                ],
              ),
            ),
          const SizedBox(height: AppSizes.sm),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.xs,
            children: <Widget>[
              PriorityBadge(urgency: request.urgency, compact: true),
              if (request.incidentTitle != null)
                StatusChip(
                  label: request.incidentTitle!,
                  color: AppColors.primary,
                  icon: Icons.warning_amber_rounded,
                ),
              if (request.neededBy != null)
                StatusChip(
                  label: 'Needed by ${Formatters.clock(request.neededBy!)}',
                  color: request.isOverdue ? AppColors.danger : AppColors.warning,
                  icon: Icons.schedule,
                ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  label: dispatched ? context.tr('res.fulfil') : context.tr('res.dispatch'),
                  compact: true,
                  variant: dispatched
                      ? AppButtonVariant.success
                      : AppButtonVariant.primary,
                  onPressed: () => onAdvance(
                    dispatched ? RequestStatus.fulfilled : RequestStatus.dispatched,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              AppButton(
                label: 'Decline',
                compact: true,
                expand: false,
                variant: AppButtonVariant.ghost,
                onPressed: () => onAdvance(RequestStatus.declined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheltersTab extends ConsumerWidget {
  const _SheltersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = AppPalette.of(context);
    final AsyncValue<List<Shelter>> shelters = ref.watch(sheltersProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.md, AppSizes.lg, AppSizes.xxl),
      children: <Widget>[
        shelters.when(
          data: (List<Shelter> list) => Column(
            children: list
                .map(
                  (Shelter shelter) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.md),
                    child: AppCard(
                      semanticLabel:
                          '${shelter.name}, ${shelter.freeCapacity} places free',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              AppIconTile(
                                icon: Icons.holiday_village_outlined,
                                color: shelter.hasSpace ? AppColors.success : AppColors.danger,
                              ),
                              const SizedBox(width: AppSizes.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(shelter.name, style: AppText.bodyStrong),
                                    const SizedBox(height: 2),
                                    Text(
                                      shelter.amenities.entries
                                          .where((MapEntry<String, bool> e) => e.value)
                                          .map((MapEntry<String, bool> e) => e.key)
                                          .join(' · '),
                                      style: AppText.caption
                                          .copyWith(color: palette.textSecondary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              StatusChip(
                                label: shelter.status.toUpperCase(),
                                color: shelter.hasSpace
                                    ? AppColors.success
                                    : AppColors.danger,
                                filled: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSizes.md),
                          CapacityBar(
                            label: 'Occupancy',
                            used: shelter.occupancy,
                            total: shelter.capacity,
                            color: shelter.hasSpace ? AppColors.primary : AppColors.danger,
                          ),
                          const SizedBox(height: AppSizes.sm),
                          Text(
                            '${shelter.freeCapacity} places free · '
                            '${shelter.contactPhone ?? 'no contact on file'}',
                            style: AppText.caption.copyWith(color: palette.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          loading: () => const AppCard(child: LoadingView()),
          error: (Object error, StackTrace _) => AppCard(
            child: ErrorView(message: error.toString()),
          ),
        ),
      ],
    );
  }
}
