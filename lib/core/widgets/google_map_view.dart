import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/theme/app_colors.dart';
import '../config/app_config.dart';
import '../models/geo_point.dart';
import 'tactical_map.dart';

/// Interactive Google Maps integration with custom markers, clustering circles,
/// safe route polylines, and live GPS centering.
///
/// If [AppConfig.hasGoogleMapsKey] is false or Google Maps is unavailable,
/// it gracefully delegates to [TacticalMap] so the app works seamlessly offline.
class GoogleMapView extends StatefulWidget {
  const GoogleMapView({
    super.key,
    required this.pins,
    this.center = const GeoPoint(17.3850, 78.4867),
    this.zoom = 13.0,
    this.onPinTap,
    this.selectedPinId,
    this.routePoints = const <GeoPoint>[],
    this.hazardRadiusMetres = 500,
    this.showUserLocation = true,
  });

  final List<MapPin> pins;
  final GeoPoint center;
  final double zoom;
  final ValueChanged<MapPin>? onPinTap;
  final String? selectedPinId;
  final List<GeoPoint> routePoints;
  final double hazardRadiusMetres;
  final bool showUserLocation;

  @override
  State<GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends State<GoogleMapView> {
  Completer<GoogleMapController>? _controllerCompleter;
  GoogleMapController? _mapController;
  GeoPoint? _liveUserLocation;
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _controllerCompleter = Completer<GoogleMapController>();
    if (widget.showUserLocation) {
      _initLocationTracking();
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initLocationTracking() async {
    try {
      final LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        final Position pos = await Geolocator.getCurrentPosition();
        if (mounted) {
          setState(() {
            _liveUserLocation = GeoPoint(pos.latitude, pos.longitude);
          });
        }
        _positionStream = Geolocator.getPositionStream().listen((Position update) {
          if (mounted) {
            setState(() {
              _liveUserLocation = GeoPoint(update.latitude, update.longitude);
            });
          }
        });
      }
    } catch (_) {
      // Non-fatal if location permissions are denied or service is off
    }
  }

  @override
  Widget build(BuildContext context) {
    // If no Google Maps key is supplied at build time, fall back gracefully to TacticalMap
    if (!AppConfig.hasGoogleMapsKey) {
      return TacticalMap(
        pins: widget.pins,
        center: _liveUserLocation ?? widget.center,
        selectedPinId: widget.selectedPinId,
        onPinTap: widget.onPinTap,
        showUserLocation: widget.showUserLocation,
      );
    }

    final CameraPosition initialPosition = CameraPosition(
      target: LatLng(widget.center.latitude, widget.center.longitude),
      zoom: widget.zoom,
    );

    final Set<Marker> markers = _buildMarkers();
    final Set<Circle> circles = _buildCircles();
    final Set<Polyline> polylines = _buildPolylines();

    return Stack(
      children: <Widget>[
        GoogleMap(
          initialCameraPosition: initialPosition,
          onMapCreated: (GoogleMapController controller) {
            _mapController = controller;
            if (!_controllerCompleter!.isCompleted) {
              _controllerCompleter!.complete(controller);
            }
          },
          markers: markers,
          circles: circles,
          polylines: polylines,
          myLocationEnabled: widget.showUserLocation,
          myLocationButtonEnabled: false,
          compassEnabled: true,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            heroTag: 'recenter_location_btn',
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.primary,
            onPressed: _recenterToLiveLocation,
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  Set<Marker> _buildMarkers() {
    final Set<Marker> markers = <Marker>{};

    for (final MapPin pin in widget.pins) {
      final double hue = _hueForType(pin.type);
      markers.add(
        Marker(
          markerId: MarkerId(pin.id),
          position: LatLng(pin.point.latitude, pin.point.longitude),
          infoWindow: InfoWindow(
            title: pin.label,
            snippet: pin.subtitle,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          onTap: widget.onPinTap == null ? null : () => widget.onPinTap!(pin),
        ),
      );
    }

    return markers;
  }

  Set<Circle> _buildCircles() {
    final Set<Circle> circles = <Circle>{};

    for (final MapPin pin in widget.pins) {
      if (pin.isCriticalCluster) {
        circles.add(
          Circle(
            circleId: CircleId('critical_${pin.id}'),
            center: LatLng(pin.point.latitude, pin.point.longitude),
            radius: widget.hazardRadiusMetres,
            fillColor: AppColors.danger.withAlpha(50),
            strokeColor: AppColors.danger,
            strokeWidth: 2,
          ),
        );
      }
    }

    return circles;
  }

  Set<Polyline> _buildPolylines() {
    if (widget.routePoints.length < 2) return <Polyline>{};

    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('safe_navigation_route'),
        points: widget.routePoints
            .map((GeoPoint pt) => LatLng(pt.latitude, pt.longitude))
            .toList(),
        color: AppColors.primary,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };
  }

  double _hueForType(MapPinType type) {
    switch (type) {
      case MapPinType.incident:
        return BitmapDescriptor.hueRed;
      case MapPinType.volunteer:
        return BitmapDescriptor.hueAzure;
      case MapPinType.hospital:
        return BitmapDescriptor.hueGreen;
      case MapPinType.resource:
        return BitmapDescriptor.hueOrange;
      case MapPinType.user:
        return BitmapDescriptor.hueViolet;
    }
  }

  Future<void> _recenterToLiveLocation() async {
    final GeoPoint target = _liveUserLocation ?? widget.center;
    if (_mapController != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(target.latitude, target.longitude),
          15.0,
        ),
      );
    }
  }
}
