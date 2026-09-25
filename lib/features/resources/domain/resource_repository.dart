import '../../../core/models/resource_item.dart';

/// Resource management boundary (FR-501–503, FR-403).
abstract class ResourceRepository {
  Future<List<ResourceItem>> fetchInventory({String? ownerOrgId});

  Future<List<ResourceRequest>> fetchRequests();

  Future<List<Shelter>> fetchShelters();

  /// Record a movement (dispatch/consume/transfer) — always append-only.
  Future<ResourceItem> recordMovement({
    required String resourceId,
    required double quantity,
    required String movementType,
    String? note,
  });

  Future<ResourceRequest> updateRequestStatus(
    String requestId,
    RequestStatus status,
  );
}
