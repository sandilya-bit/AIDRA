import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../models/geo_point.dart';

/// Renders an operational map without any tile-provider dependency, so it works
/// fully offline (FR-1001) and never needs an API key.
///
/// Swapping in real tiles (Google Maps / Mapbox / `flutter_map` + OSM) is a
/// drop-in change behind this widget: keep the same [pins] input and replace
/// [_MapBackdropPainter] with the tile layer. Everything above it — pins,
/// radar, legend, selection — stays identical.
class TacticalMap extends StatefulWidget {
  const TacticalMap({
    super.key,
    required this.pins,
    this.center = const GeoPoint(17.3850, 78.4867),
    this.metresPerPixel = 14,
    this.onPinTap,
    this.selectedPinId,
    this.interactive = true,
    this.showRadar = true,
    this.showUserLocation = true,
  });

  final List<MapPin> pins;
  final GeoPoint center;

  /// Zoom: fewer metres per pixel = closer in.
  final double metresPerPixel;
  final ValueChanged<MapPin>? onPinTap;
  final String? selectedPinId;
  final bool interactive;
  final bool showRadar;
  final bool showUserLocation;

  @override
  State<TacticalMap> createState() => _TacticalMapState();
}

class _TacticalMapState extends State<TacticalMap> {
  double _zoom = 1;

  double get _scale => widget.metresPerPixel / _zoom;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 360,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 260,
        );

        final Widget canvas = SizedBox.fromSize(
          size: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  painter: _MapBackdropPainter(
                    palette: palette,
                    gridSpacing: 44 * _zoom,
                  ),
                ),
              ),
              ..._buildPins(size),
            ],
          ),
        );

        if (!widget.interactive) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(0),
            child: canvas,
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: Stack(
            children: <Widget>[
              canvas,
              Positioned(
                right: AppSizesCompact.edge,
                bottom: AppSizesCompact.edge,
                child: _ZoomControls(
                  palette: palette,
                  onZoomIn: () => setState(() => _zoom = (_zoom * 1.35).clamp(0.6, 3.2)),
                  onZoomOut: () => setState(() => _zoom = (_zoom / 1.35).clamp(0.6, 3.2)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildPins(Size size) {
    final List<Widget> widgets = <Widget>[];

    for (final MapPin pin in widget.pins) {
      final Offset offset = _project(pin.point, size);
      if (offset.dx < -80 ||
          offset.dy < -80 ||
          offset.dx > size.width + 80 ||
          offset.dy > size.height + 80) {
        continue;
      }

      final bool selected = widget.selectedPinId == pin.id;

      if (widget.showRadar && pin.isCriticalCluster) {
        widgets.add(
          Positioned(
            left: offset.dx - 60,
            top: offset.dy - 60,
            child: const IgnorePointer(child: _RadarPulse(size: 120)),
          ),
        );
      }

      widgets.add(
        Positioned(
          left: offset.dx - 17,
          top: offset.dy - 34,
          child: _MapPinMarker(
            pin: pin,
            selected: selected,
            onTap: widget.onPinTap == null ? null : () => widget.onPinTap!(pin),
          ),
        ),
      );
    }

    return widgets;
  }

  Offset _project(GeoPoint point, Size size) {
    final double metresPerDegreeLat = 111320;
    final double metresPerDegreeLng =
        111320 * math.cos(widget.center.latitude * math.pi / 180);

    final double east = (point.longitude - widget.center.longitude) * metresPerDegreeLng;
    final double north = (point.latitude - widget.center.latitude) * metresPerDegreeLat;

    return Offset(
      size.width / 2 + east / _scale,
      size.height / 2 - north / _scale,
    );
  }
}

abstract final class AppSizesCompact {
  static const double edge = 10;
}

class _MapPinMarker extends StatelessWidget {
  const _MapPinMarker({
    required this.pin,
    required this.selected,
    this.onTap,
  });

  final MapPin pin;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = pin.type.color;
    return Semantics(
      button: onTap != null,
      label: pin.subtitle == null ? pin.label : '${pin.label}, ${pin.subtitle}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedScale(
              scale: selected ? 1.15 : 1,
              duration: const Duration(milliseconds: 150),
              child: Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: AppColors.shadowStrong, blurRadius: 8),
                  ],
                ),
                child: Icon(pin.type.icon, color: Colors.white, size: 17),
              ),
            ),
            CustomPaint(
              size: const Size(10, 8),
              painter: _PinTailPainter(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinTailPainter extends CustomPainter {
  _PinTailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PinTailPainter oldDelegate) => oldDelegate.color != color;
}

/// Expanding radar rings for critical clusters (design system §4.5).
class _RadarPulse extends StatefulWidget {
  const _RadarPulse({required this.size});

  final double size;

  @override
  State<_RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<_RadarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respects the OS "reduce motion" accessibility setting.
    if (MediaQuery.of(context).disableAnimations) {
      return _rings(0.6);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) => _rings(_controller.value),
    );
  }

  Widget _rings(double t) {
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _RadarPainter(progress: t, color: AppColors.danger),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < 2; i++) {
      final double local = (progress + i * 0.5) % 1.0;
      final double radius = (size.width / 2) * local;
      final int alpha = (110 * (1 - local)).round().clamp(0, 255);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withAlpha(alpha),
      );
    }
    canvas.drawCircle(
      center,
      6,
      Paint()..color = color.withAlpha(0xCC),
    );
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.palette,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final AppPalette palette;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppSizesCompact.edge),
        border: Border.all(color: palette.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: AppColors.shadow, blurRadius: 8),
        ],
      ),
      child: Column(
        children: <Widget>[
          IconButton(
            onPressed: onZoomIn,
            icon: const Icon(Icons.add, size: 18),
            tooltip: 'Zoom in',
            color: palette.textPrimary,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          Container(height: 1, width: 28, color: palette.border),
          IconButton(
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove, size: 18),
            tooltip: 'Zoom out',
            color: palette.textPrimary,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }
}

/// Stylised street/river backdrop — deterministic so the map never "jitters".
class _MapBackdropPainter extends CustomPainter {
  _MapBackdropPainter({required this.palette, required this.gridSpacing});

  final AppPalette palette;
  final double gridSpacing;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;

    // Base
    canvas.drawRect(
      bounds,
      Paint()
        ..color = palette.isDark
            ? const Color(0xFF0F2337)
            : const Color(0xFFE8EEF5),
    );

    // Block texture
    final Paint blockPaint = Paint()
      ..color = palette.isDark
          ? const Color(0xFF16304A)
          : const Color(0xFFDCE6F1);
    for (double x = 0; x < size.width; x += gridSpacing * 1.6) {
      for (double y = 0; y < size.height; y += gridSpacing * 1.6) {
        final Rect block = Rect.fromLTWH(
          x + gridSpacing * 0.25,
          y + gridSpacing * 0.25,
          gridSpacing * 0.8,
          gridSpacing * 0.6,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(block, const Radius.circular(4)),
          blockPaint,
        );
      }
    }

    // River
    final Path river = Path()
      ..moveTo(-20, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.32,
        size.height * 0.48,
        size.width * 0.58,
        size.height * 0.62,
      )
      ..quadraticBezierTo(
        size.width * 0.82,
        size.height * 0.74,
        size.width + 20,
        size.height * 0.5,
      );
    canvas.drawPath(
      river,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26
        ..strokeCap = StrokeCap.round
        ..color = palette.isDark
            ? const Color(0xFF14405F)
            : const Color(0xFFB9D8EE),
    );

    // Roads
    final Paint roadPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = palette.isDark
          ? const Color(0xFF27455F)
          : const Color(0xFFFFFFFF);
    for (int i = 0; i < 4; i++) {
      final double y = size.height * (0.15 + i * 0.22);
      final Path road = Path()
        ..moveTo(-10, y)
        ..cubicTo(
          size.width * 0.3,
          y - 26,
          size.width * 0.6,
          y + 34,
          size.width + 10,
          y - 8,
        );
      canvas.drawPath(road, roadPaint);
    }
    for (int i = 0; i < 3; i++) {
      final double x = size.width * (0.2 + i * 0.28);
      final Path road = Path()
        ..moveTo(x, -10)
        ..cubicTo(x + 22, size.height * 0.35, x - 26, size.height * 0.65, x + 10, size.height + 10);
      canvas.drawPath(road, roadPaint);
    }

    // Park blobs
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.28),
      34,
      Paint()
        ..color = palette.isDark
            ? const Color(0xFF17402F)
            : const Color(0xFFCFE7D6),
    );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.3),
      26,
      Paint()
        ..color = palette.isDark
            ? const Color(0xFF17402F)
            : const Color(0xFFCFE7D6),
    );

    // Grid overlay (reference scale)
    final Paint gridPaint = Paint()
      ..strokeWidth = 1
      ..color = palette.isDark ? const Color(0x14FFFFFF) : const Color(0x140E2A47);
    for (double x = 0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Scale caption
    final TextPainter caption = TextPainter(
      text: TextSpan(
        text: '500 m',
        style: AppText.label.copyWith(color: palette.textSecondary),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    caption.paint(
      canvas,
      Offset(12, size.height - caption.height - 12),
    );
    canvas.drawLine(
      Offset(12, size.height - 14),
      Offset(12 + 34, size.height - 14),
      Paint()
        ..color = palette.textSecondary
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_MapBackdropPainter oldDelegate) =>
      oldDelegate.gridSpacing != gridSpacing ||
      oldDelegate.palette.isDark != palette.isDark;
}
