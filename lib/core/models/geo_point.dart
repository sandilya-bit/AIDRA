import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'parse.dart';

/// A WGS-84 coordinate. Mirrors `geography(Point,4326)` in the database design.
@immutable
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude, {this.accuracyMetres});

  final double latitude;
  final double longitude;
  final double? accuracyMetres;

  static const GeoPoint unknown = GeoPoint(0, 0);

  bool get isUsable => latitude != 0 || longitude != 0;

  /// Haversine great-circle distance — the same maths the matching engine's
  /// radius filter uses (DB design §4.5 / FR-301).
  double distanceTo(GeoPoint other) {
    const double earthRadius = 6371000; // metres
    final double dLat = _rad(other.latitude - latitude);
    final double dLng = _rad(other.longitude - longitude);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(latitude)) *
            math.cos(_rad(other.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
        if (accuracyMetres != null) 'accuracy_m': accuracyMetres,
      };

  static GeoPoint fromJson(Map<String, dynamic> json) => GeoPoint(
        parseDouble(json['latitude']),
        parseDouble(json['longitude']),
        accuracyMetres: json['accuracy_m'] == null
            ? null
            : parseDouble(json['accuracy_m']),
      );

  static double _rad(double degrees) => degrees * math.pi / 180;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() =>
      '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
}

/// Pin classes rendered on the live map (design system §4.5, FR-701).
enum MapPinType { incident, volunteer, hospital, resource, user }

extension MapPinTypeX on MapPinType {
  Color get color => switch (this) {
        MapPinType.incident => const Color(0xFFF03D3D),
        MapPinType.volunteer => const Color(0xFF1B6FF1),
        MapPinType.hospital => const Color(0xFF1DB97A),
        MapPinType.resource => const Color(0xFFF5A623),
        MapPinType.user => const Color(0xFF7C4DFF),
      };

  IconData get icon => switch (this) {
        MapPinType.incident => Icons.warning_amber_rounded,
        MapPinType.volunteer => Icons.person_pin_circle_outlined,
        MapPinType.hospital => Icons.local_hospital_outlined,
        MapPinType.resource => Icons.inventory_2_outlined,
        MapPinType.user => Icons.my_location,
      };

  String get legendKey => switch (this) {
        MapPinType.incident => 'map.legend.incidents',
        MapPinType.volunteer => 'map.legend.volunteers',
        MapPinType.hospital => 'map.legend.hospitals',
        MapPinType.resource => 'map.legend.resources',
        MapPinType.user => 'map.yourLocation',
      };
}

/// A single marker on the tactical map.
@immutable
class MapPin {
  const MapPin({
    required this.id,
    required this.type,
    required this.point,
    required this.label,
    this.subtitle,
    this.urgency,
    this.isCriticalCluster = false,
  });

  final String id;
  final MapPinType type;
  final GeoPoint point;
  final String label;
  final String? subtitle;
  final String? urgency;
  final bool isCriticalCluster;
}
