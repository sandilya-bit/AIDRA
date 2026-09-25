import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_enums.dart';
import '../../../core/di/providers.dart';
import '../../../core/models/resource_item.dart';
import '../data/resource_repository_impl.dart';
import '../domain/resource_repository.dart';

final Provider<ResourceRepository> resourceRepositoryProvider =
    Provider<ResourceRepository>(
  (Ref ref) => ResourceRepositoryImpl(
    apiClient: ref.watch(apiClientProvider),
    store: ref.watch(localStoreProvider),
  ),
);

final AsyncNotifierProvider<InventoryController, List<ResourceItem>>
    inventoryProvider =
    AsyncNotifierProvider<InventoryController, List<ResourceItem>>(
  InventoryController.new,
);

class InventoryController extends AsyncNotifier<List<ResourceItem>> {
  @override
  Future<List<ResourceItem>> build() =>
      ref.watch(resourceRepositoryProvider).fetchInventory();

  Future<void> refresh() async {
    state = const AsyncValue<List<ResourceItem>>.loading();
    state = await AsyncValue.guard(
      () => ref.read(resourceRepositoryProvider).fetchInventory(),
    );
  }

  /// Dispatch or consume stock. The local ledger updates immediately; the
  /// transaction is replayed to the server when connectivity allows.
  Future<void> recordMovement({
    required String resourceId,
    required double quantity,
    required String movementType,
    String? note,
  }) async {
    try {
      final ResourceItem updated =
          await ref.read(resourceRepositoryProvider).recordMovement(
                resourceId: resourceId,
                quantity: quantity,
                movementType: movementType,
                note: note,
              );
      final List<ResourceItem>? current = state.valueOrNull;
      if (current != null) {
        state = AsyncValue<List<ResourceItem>>.data(
          current
              .map((ResourceItem r) => r.id == updated.id ? updated : r)
              .toList(growable: false),
        );
      }
    } catch (error, stackTrace) {
      state = AsyncValue<List<ResourceItem>>.error(error, stackTrace);
    }
  }
}

final AsyncNotifierProvider<ResourceRequestsController, List<ResourceRequest>>
    resourceRequestsProvider =
    AsyncNotifierProvider<ResourceRequestsController, List<ResourceRequest>>(
  ResourceRequestsController.new,
);

class ResourceRequestsController extends AsyncNotifier<List<ResourceRequest>> {
  @override
  Future<List<ResourceRequest>> build() =>
      ref.watch(resourceRepositoryProvider).fetchRequests();

  Future<void> updateStatus(String requestId, RequestStatus status) async {
    final ResourceRequest updated =
        await ref.read(resourceRepositoryProvider).updateRequestStatus(requestId, status);
    final List<ResourceRequest>? current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue<List<ResourceRequest>>.data(
        current
            .map((ResourceRequest r) => r.id == updated.id ? updated : r)
            .toList(growable: false),
      );
    }
  }
}

final FutureProvider<List<Shelter>> sheltersProvider =
    FutureProvider<List<Shelter>>(
  (Ref ref) => ref.watch(resourceRepositoryProvider).fetchShelters(),
);

/// Items at or below their minimum threshold — the low-stock alert list.
final Provider<List<ResourceItem>> lowStockProvider =
    Provider<List<ResourceItem>>((Ref ref) {
  final List<ResourceItem> items =
      ref.watch(inventoryProvider).valueOrNull ?? const <ResourceItem>[];
  return items.where((ResourceItem r) => r.isLowStock).toList(growable: false);
});

/// Inventory grouped by category for the summary chips.
final Provider<Map<ResourceCategory, double>> inventoryByCategoryProvider =
    Provider<Map<ResourceCategory, double>>((Ref ref) {
  final List<ResourceItem> items =
      ref.watch(inventoryProvider).valueOrNull ?? const <ResourceItem>[];
  final Map<ResourceCategory, double> totals = <ResourceCategory, double>{};
  for (final ResourceItem item in items) {
    totals[item.category] = (totals[item.category] ?? 0) + item.quantity;
  }
  return totals;
});
