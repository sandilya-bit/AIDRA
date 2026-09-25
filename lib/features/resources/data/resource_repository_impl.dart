import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/data/demo_data.dart';
import '../../../core/error/failure.dart';
import '../../../core/models/resource_item.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_store.dart';
import '../domain/resource_repository.dart';

/// Resource management. Every quantity change goes through
/// [recordMovement] so the local ledger mirrors the append-only
/// `resource_transactions` table server-side (DB design §7.2).
class ResourceRepositoryImpl implements ResourceRepository {
  ResourceRepositoryImpl({
    required ApiClient apiClient,
    required LocalStore store,
    Uuid? uuid,
  })  : _api = apiClient,
        _store = store,
        _uuid = uuid ?? const Uuid();

  static const String keyInventory = 'cache.resources';
  static const String keyRequests = 'cache.resource_requests';

  final ApiClient _api;
  final LocalStore _store;
  final Uuid _uuid;

  @override
  Future<List<ResourceItem>> fetchInventory({String? ownerOrgId}) async {
    if (AppConfig.useRemoteBackend) {
      try {
        final List<dynamic> items = await _api.getList(
          '/resources',
          query: <String, dynamic>{if (ownerOrgId != null) 'owner_org_id': ownerOrgId},
        );
        final List<ResourceItem> resources = items
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) =>
                ResourceItem.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
        if (resources.isNotEmpty) {
          await _persistInventory(resources);
          return resources;
        }
      } on Failure catch (_) {
        return _localInventory();
      }
    }
    return _localInventory();
  }

  @override
  Future<List<ResourceRequest>> fetchRequests() async {
    if (AppConfig.useRemoteBackend) {
      try {
        final List<dynamic> items = await _api.getList('/resources/requests');
        final List<ResourceRequest> requests = items
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) =>
                ResourceRequest.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
        if (requests.isNotEmpty) {
          await _persistRequests(requests);
          return requests;
        }
      } on Failure catch (_) {
        return _localRequests();
      }
    }
    return _localRequests();
  }

  @override
  Future<List<Shelter>> fetchShelters() async {
    if (AppConfig.useRemoteBackend) {
      try {
        final List<dynamic> items = await _api.getList('/shelters');
        final List<Shelter> shelters = items
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) => Shelter.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
        if (shelters.isNotEmpty) return shelters;
      } on Failure catch (_) {
        return DemoData.shelters();
      }
    }
    return DemoData.shelters();
  }

  @override
  Future<ResourceItem> recordMovement({
    required String resourceId,
    required double quantity,
    required String movementType,
    String? note,
  }) async {
    final List<ResourceItem> inventory = _localInventory();
    final int index = inventory.indexWhere((ResourceItem r) => r.id == resourceId);
    if (index == -1) throw const CacheFailure('Resource not found');

    final ResourceItem current = inventory[index];
    final bool outbound = movementType == 'dispatch' ||
        movementType == 'consume' ||
        movementType == 'transfer_out';
    final double delta = outbound ? -quantity.abs() : quantity.abs();
    final double nextQuantity = (current.quantity + delta).clamp(0, double.infinity);

    final ResourceItem updated = current.copyWith(
      quantity: nextQuantity,
      consumedLast24h: outbound ? current.consumedLast24h + quantity.abs() : current.consumedLast24h,
    );

    inventory[index] = updated;
    await _persistInventory(inventory);

    if (AppConfig.useRemoteBackend) {
      try {
        await _api.postJson(
          '/resources/$resourceId/transactions',
          <String, dynamic>{
            'txn_type': movementType,
            'quantity_delta': delta,
            'reason': note,
          },
          idempotencyKey: _uuid.v4(),
        );
      } on Failure catch (_) {
        // Queued for replay by the sync service.
      }
    }

    return updated;
  }

  @override
  Future<ResourceRequest> updateRequestStatus(
    String requestId,
    RequestStatus status,
  ) async {
    final List<ResourceRequest> requests = _localRequests();
    final int index = requests.indexWhere((ResourceRequest r) => r.id == requestId);
    final DateTime now = DateTime.now();

    ResourceRequest updated;
    if (index == -1) {
      updated = ResourceRequest(
        id: requestId,
        code: 'REQ-UNKNOWN',
        requestingOrgId: 'unknown',
        requestingOrgName: 'Unknown org',
        lines: const <ResourceRequestLine>[],
        urgency: UrgencyLevel.high,
        status: status,
        createdAt: now,
      );
    } else {
      updated = requests[index].copyWith(
        status: status,
        dispatchedAt: status == RequestStatus.dispatched ? now : null,
        fulfilledAt: status == RequestStatus.fulfilled ? now : null,
      );
      requests[index] = updated;
    }
    await _persistRequests(requests);

    if (AppConfig.useRemoteBackend) {
      try {
        await _api.patchJson(
          '/resources/requests/$requestId',
          <String, dynamic>{'status': status.key},
        );
      } on Failure catch (_) {
        // Queued for replay.
      }
    }

    return updated;
  }

  // ------------------------------------------------------------------ helpers

  List<ResourceItem> _localInventory() {
    final List<Map<String, dynamic>> cached = _store.getJsonList(keyInventory);
    if (cached.isEmpty) return DemoData.resources();
    return cached.map(ResourceItem.fromJson).toList(growable: false);
  }

  List<ResourceRequest> _localRequests() {
    final List<Map<String, dynamic>> cached = _store.getJsonList(keyRequests);
    if (cached.isEmpty) return DemoData.resourceRequests();
    return cached.map(ResourceRequest.fromJson).toList(growable: false);
  }

  Future<void> _persistInventory(List<ResourceItem> resources) =>
      _store.setJsonList(
        keyInventory,
        resources.map((ResourceItem r) => r.toJson()).toList(growable: false),
      );

  Future<void> _persistRequests(List<ResourceRequest> requests) =>
      _store.setJsonList(
        keyRequests,
        requests.map((ResourceRequest r) => r.toJson()).toList(growable: false),
      );
}
