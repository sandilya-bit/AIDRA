import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Vector rendition of the AIDRA mark: a shield (protection) carrying a medical
/// cross (health) with a chevron "A" (action & hope), drawn with a blue→teal
/// gradient. Rendered as a painter so it stays crisp at every size and ships
/// without binary assets.
class AidraLogo extends StatelessWidget {
  const AidraLogo({super.key, this.size = 72, this.glow = false});

  /// Square edge length of the shield.
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'AIDRA logo',
      image: true,
      child: Container(
        decoration: glow
            ? const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(color: AppColors.primarySoft, blurRadius: 32, spreadRadius: 6),
                ],
              )
            : null,
        child: SizedBox(
          height: size,
          width: size,
          child: CustomPaint(painter: _ShieldPainter()),
        ),
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Path shield = Path()
      ..moveTo(w * 0.5, 0)
      ..cubicTo(w * 0.72, h * 0.06, w * 0.94, h * 0.10, w, h * 0.17)
      ..lineTo(w, h * 0.54)
      ..cubicTo(w, h * 0.80, w * 0.72, h * 0.95, w * 0.5, h)
      ..cubicTo(w * 0.28, h * 0.95, 0, h * 0.80, 0, h * 0.54)
      ..lineTo(0, h * 0.17)
      ..cubicTo(w * 0.06, h * 0.10, w * 0.28, h * 0.06, w * 0.5, 0)
      ..close();

    canvas.drawPath(
      shield,
      Paint()
        ..shader = AppColors.brandGradient.createShader(
          Rect.fromLTWH(0, 0, w, h),
        ),
    );

    // Inner highlight gives the mark the same depth as the brand sheet.
    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.045
        ..color = AppColors.whiteSoft,
    );

    // Chevron "A"
    final Path chevron = Path()
      ..moveTo(w * 0.5, h * 0.17)
      ..lineTo(w * 0.66, h * 0.44)
      ..lineTo(w * 0.59, h * 0.44)
      ..lineTo(w * 0.5, h * 0.26)
      ..lineTo(w * 0.41, h * 0.44)
      ..lineTo(w * 0.34, h * 0.44)
      ..close();
    canvas.drawPath(chevron, Paint()..color = Colors.white);

    // Cross
    final double barThickness = w * 0.16;
    final Paint cross = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.66),
          width: barThickness,
          height: h * 0.34,
        ),
        Radius.circular(barThickness * 0.35),
      ),
      cross,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.66),
          width: w * 0.38,
          height: barThickness,
        ),
        Radius.circular(barThickness * 0.35),
      ),
      cross,
    );
  }

  @override
  bool shouldRepaint(_ShieldPainter oldDelegate) => false;
}

/// Logo + wordmark lockup used on the splash, login and register screens.
class AidraLockup extends StatelessWidget {
  const AidraLockup({
    super.key,
    this.logoSize = 78,
    this.onNavy = false,
    this.showTagline = true,
    this.tagline,
  });

  final double logoSize;
  final bool onNavy;
  final bool showTagline;
  final String? tagline;

  @override
  Widget build(BuildContext context) {
    final Color titleColor = onNavy ? Colors.white : AppColors.navy;
    final Color subColor = onNavy ? AppColors.whiteMuted : AppColors.lightTextSecondary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AidraLogo(size: logoSize, glow: onNavy),
        const SizedBox(height: 14),
        Text(
          'AIDRA',
          style: TextStyle(
            fontSize: logoSize * 0.46,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: titleColor,
          ),
        ),
        if (showTagline) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            tagline ?? 'Connecting Help Before It\'s Too Late.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: subColor,
            ),
          ),
        ],
      ],
    );
  }
}
