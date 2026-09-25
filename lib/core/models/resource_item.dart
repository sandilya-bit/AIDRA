import '../constants/app_enums.dart';
import 'geo_point.dart';
import 'parse.dart';

/// Inventory line (DB `resources`, FR-501/502).
class ResourceItem {
  const ResourceItem({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.quantity,
    this.ownerOrgId,
    this.ownerOrgName,
    this.point,
    this.reservedQuantity = 0,
    this.minThreshold = 0,
    this.visibility = 'shared',
    this.status = 'active',
    this.consumedLast24h = 0,
    this.expiresAt,
    this.updatedAt,
    this.distanceMetres,
  });

  final String id;
  final String name;
  final ResourceCategory category;
  final String unit;
  final double quantity;
  final double reservedQuantity;
  final double minThreshold;
  final String? ownerOrgId;
  final String? ownerOrgName;
  final GeoPoint? point;
  final String visibility; // org | shared | public
  final String status; // active | depleted | quarantined | expired
  final double consumedLast24h;
  final DateTime? expiresAt;
  final DateTime? updatedAt;
  final double? distanceMetres;

  double get availableQuantity => (quantity - reservedQuantity).clamp(0, quantity);

  bool get isLowStock => quantity <= minThreshold;

  /// Days of cover at the current 24 h burn rate (Resource Forecasting input).
  double? get daysOfCover =>
      consumedLast24h <= 0 ? null : quantity / consumedLast24h;

  static ResourceItem fromJson(Map<String, dynamic> json) => ResourceItem(
        id: parseString(json['id'], 'res-${json.hashCode}'),
        name: parseString(json['name'], 'Resource'),
        category: enumFromKey(
          ResourceCategory.values,
          json['category']?.toString(),
          ResourceCategory.other,
        ),
        unit: parseString(json['unit'], 'unit'),
        quantity: parseDouble(json['quantity']),
        reservedQuantity: parseDouble(json['reserved_quantity']),
        minThreshold: parseDouble(json['min_threshold']),
        ownerOrgId: json['owner_org_id']?.toString(),
        ownerOrgName: json['owner_org_name']?.toString(),
        point: json['latitude'] == null
            ? null
            : GeoPoint(parseDouble(json['latitude']), parseDouble(json['longitude'])),
        visibility: parseString(json['visibility'], 'shared'),
        status: parseString(json['status'], 'active'),
        consumedLast24h: parseDouble(json['consumed_24h']),
        expiresAt: parseDateOrNull(json['expires_at']),
        updatedAt: parseDateOrNull(json['updated_at']),
        distanceMetres: json['distance_m'] == null ? null : parseDouble(json['distance_m']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'category': category.key,
        'unit': unit,
        'quantity': quantity,
        'reserved_quantity': reservedQuantity,
        'min_threshold': minThreshold,
        'owner_org_id': ownerOrgId,
        'visibility': visibility,
        'status': status,
        'consumed_24h': consumedLast24h,
        if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      };

  ResourceItem copyWith({double? quantity, double? reservedQuantity, double? consumedLast24h}) =>
      ResourceItem(
        id: id,
        name: name,
        category: category,
        unit: unit,
        quantity: quantity ?? this.quantity,
        reservedQuantity: reservedQuantity ?? this.reservedQuantity,
        minThreshold: minThreshold,
        ownerOrgId: ownerOrgId,
        ownerOrgName: ownerOrgName,
        point: point,
        visibility: visibility,
        status: status,
        consumedLast24h: consumedLast24h ?? this.consumedLast24h,
        expiresAt: expiresAt,
        updatedAt: updatedAt,
        distanceMetres: distanceMetres,
      );
}

/// Inter-organization request board entry (FR-403).
class ResourceRequest {
  const ResourceRequest({
    required this.id,
    required this.code,
    required this.requestingOrgId,
    required this.requestingOrgName,
    required this.lines,
    required this.urgency,
    required this.status,
    required this.createdAt,
    this.fulfillingOrgId,
    this.fulfillingOrgName,
    this.incidentId,
    this.incidentTitle,
    this.neededBy,
    this.dispatchedAt,
    this.fulfilledAt,
    this.notes,
  });

  final String id;
  final String code;
  final String requestingOrgId;
  final String requestingOrgName;
  final String? fulfillingOrgId;
  final String? fulfillingOrgName;
  final String? incidentId;
  final String? incidentTitle;
  final List<ResourceRequestLine> lines;
  final UrgencyLevel urgency;
  final RequestStatus status;
  final DateTime? neededBy;
  final DateTime createdAt;
  final DateTime? dispatchedAt;
  final DateTime? fulfilledAt;
  final String? notes;

  bool get isOpen => status == RequestStatus.open || status == RequestStatus.approved;

  bool get isOverdue {
    final DateTime? due = neededBy;
    return due != null && due.isBefore(DateTime.now()) && isOpen;
  }

  ResourceRequest copyWith({RequestStatus? status, DateTime? dispatchedAt, DateTime? fulfilledAt}) =>
      ResourceRequest(
        id: id,
        code: code,
        requestingOrgId: requestingOrgId,
        requestingOrgName: requestingOrgName,
        fulfillingOrgId: fulfillingOrgId,
        fulfillingOrgName: fulfillingOrgName,
        incidentId: incidentId,
        incidentTitle: incidentTitle,
        lines: lines,
        urgency: urgency,
        status: status ?? this.status,
        neededBy: neededBy,
        createdAt: createdAt,
        dispatchedAt: dispatchedAt ?? this.dispatchedAt,
        fulfilledAt: fulfilledAt ?? this.fulfilledAt,
        notes: notes,
      );

  static ResourceRequest fromJson(Map<String, dynamic> json) => ResourceRequest(
        id: parseString(json['id'], 'rr-${json.hashCode}'),
        code: parseString(json['request_code'], 'REQ-0000'),
        requestingOrgId: parseString(json['requesting_org_id']),
        requestingOrgName: parseString(json['requesting_org_name'], 'Requesting org'),
        fulfillingOrgId: json['fulfilling_org_id']?.toString(),
        fulfillingOrgName: json['fulfilling_org_name']?.toString(),
        incidentId: json['incident_id']?.toString(),
        incidentTitle: json['incident_title']?.toString(),
        lines: parseMapList(json['items'])
            .map(ResourceRequestLine.fromJson)
            .toList(growable: false),
        urgency: enumFromKey(
          UrgencyLevel.values,
          json['urgency']?.toString(),
          UrgencyLevel.high,
        ),
        status: enumFromKey(
          RequestStatus.values,
          json['status']?.toString(),
          RequestStatus.open,
        ),
        neededBy: parseDateOrNull(json['needed_by']),
        createdAt: parseDate(json['created_at']),
        dispatchedAt: parseDateOrNull(json['dispatched_at']),
        fulfilledAt: parseDateOrNull(json['fulfilled_at']),
        notes: json['notes']?.toString(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'request_code': code,
        'requesting_org_id': requestingOrgId,
        'fulfilling_org_id': fulfillingOrgId,
        'incident_id': incidentId,
        'items': lines.map((ResourceRequestLine l) => l.toJson()).toList(growable: false),
        'urgency': urgency.key,
        'status': status.key,
        if (neededBy != null) 'needed_by': neededBy!.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}

class ResourceRequestLine {
  const ResourceRequestLine({
    required this.name,
    required this.category,
    required this.unit,
    required this.quantity,
  });

  final String name;
  final ResourceCategory category;
  final String unit;
  final double quantity;

  String get summary => '${quantity.toStringAsFixed(0)} $unit $name';

  static ResourceRequestLine fromJson(Map<String, dynamic> json) =>
      ResourceRequestLine(
        name: parseString(json['name'], 'Supply'),
        category: enumFromKey(
          ResourceCategory.values,
          json['category']?.toString(),
          ResourceCategory.other,
        ),
        unit: parseString(json['unit'], 'unit'),
        quantity: parseDouble(json['quantity']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'category': category.key,
        'unit': unit,
        'quantity': quantity,
      };
}

/// Shelter (playbook recovery phase + FR-1001 offline cache).
class Shelter {
  const Shelter({
    required this.id,
    required this.name,
    required this.point,
    required this.capacity,
    this.occupancy = 0,
    this.status = 'open',
    this.amenities = const <String, bool>{},
    this.contactPhone,
  });

  final String id;
  final String name;
  final GeoPoint point;
  final int capacity;
  final int occupancy;
  final String status; // open | full | closed | standby
  final Map<String, bool> amenities;
  final String? contactPhone;

  int get freeCapacity => (capacity - occupancy).clamp(0, capacity);

  bool get hasSpace => freeCapacity > 0 && status == 'open';

  static Shelter fromJson(Map<String, dynamic> json) => Shelter(
        id: parseString(json['id'], 's-${json.hashCode}'),
        name: parseString(json['name'], 'Shelter'),
        point: GeoPoint(
          parseDouble(json['latitude']),
          parseDouble(json['longitude']),
        ),
        capacity: parseInt(json['capacity']),
        occupancy: parseInt(json['occupancy']),
        status: parseString(json['status'], 'open'),
        amenities: parseMap(json['amenities']).map(
          (String key, dynamic value) =>
              MapEntry<String, bool>(key, parseBool(value)),
        ),
        contactPhone: json['contact_phone']?.toString(),
      );
}
