import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/aidra_logo.dart';
import '../../../core/widgets/app_widgets.dart';
import 'auth_providers.dart';

/// Splash / welcome screen (design system §4.1).
///
/// Doubles as the session gate: once `restoreSession()` resolves, an
/// authenticated user is routed straight to the shell.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  Widget build(BuildContext context) {
    // Session restore is in flight: `authControllerProvider` drives the
    // redirect, which routes an existing session straight to the shell.
    final bool restoring = ref.watch(authControllerProvider).status == AuthStatus.unknown;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const _SplashBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.xl,
                          vertical: AppSizes.xl,
                        ),
                        child: Column(
                          children: <Widget>[
                            const Spacer(flex: 2),
                            const AidraLockup(
                              logoSize: 104,
                              onNavy: true,
                              tagline: 'Connecting Help Before It\'s Too Late.',
                            ),
                            const Spacer(flex: 3),
                            AppButton(
                              label: context.tr('splash.getStarted'),
                              onPressed: () => context.go('/register'),
                              icon: Icons.arrow_forward_rounded,
                            ),
                            const SizedBox(height: AppSizes.md),
                            _AlreadyHaveAccount(
                              onLogin: () => context.go('/login'),
                            ),
                            const SizedBox(height: AppSizes.sm),
                            if (restoring)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  const SizedBox(
                                    height: 14,
                                    width: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.whiteMuted,
                                    ),
                                  ),
                                  const SizedBox(width: AppSizes.sm),
                                  Text(
                                    'Restoring your session…',
                                    style: AppText.caption
                                        .copyWith(color: AppColors.whiteMuted),
                                  ),
                                ],
                              )
                            else
                              Text(
                                'Multi-language · Works offline · AI coordinated',
                                textAlign: TextAlign.center,
                                style: AppText.caption.copyWith(color: AppColors.whiteMuted),
                              ),
                            const SizedBox(height: AppSizes.lg),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AlreadyHaveAccount extends StatelessWidget {
  const _AlreadyHaveAccount({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          context.tr('splash.haveAccount'),
          style: AppText.body.copyWith(color: AppColors.whiteMuted),
        ),
        TextButton(
          onPressed: onLogin,
          child: Text(
            context.tr('splash.login'),
            style: AppText.bodyStrong.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// Navy gradient with a low-opacity rescue silhouette — replaces the raster
/// hero from the design sheet without shipping binary assets.
class _SplashBackdrop extends StatelessWidget {
  const _SplashBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.navyGradient),
      child: CustomPaint(painter: _RescueSilhouettePainter()),
    );
  }
}

class _RescueSilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint silhouette = Paint()..color = AppColors.whiteSoft;
    final double groundY = size.height * 0.86;

    // Distant skyline of damaged structures.
    final List<double> heights = <double>[0.16, 0.24, 0.12, 0.30, 0.20, 0.14, 0.26];
    final double step = size.width / heights.length;
    for (int i = 0; i < heights.length; i++) {
      final double buildingHeight = size.height * heights[i];
      final Rect rect = Rect.fromLTWH(
        i * step + 4,
        groundY - buildingHeight,
        step - 8,
        buildingHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = AppColors.whiteSoft,
      );
    }

    // Ground line
    canvas.drawRect(
      Rect.fromLTWH(0, groundY, size.width, size.height - groundY),
      Paint()..color = const Color(0x14FFFFFF),
    );

    // Rescuer + citizen silhouettes holding hands (the brand story).
    final double figureHeight = size.height * 0.18;
    _figure(canvas, Offset(size.width * 0.44, groundY), figureHeight, silhouette);
    _figure(canvas, Offset(size.width * 0.56, groundY), figureHeight * 0.88, silhouette);

    // Water reflection band
    canvas.drawRect(
      Rect.fromLTWH(0, groundY + (size.height - groundY) * 0.5, size.width, 2),
      Paint()..color = const Color(0x1AFFFFFF),
    );
  }

  void _figure(Canvas canvas, Offset feet, double height, Paint paint) {
    final double headRadius = height * 0.16;
    canvas.drawCircle(
      Offset(feet.dx, feet.dy - height + headRadius),
      headRadius,
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(feet.dx, feet.dy - height * 0.5),
          width: height * 0.34,
          height: height * 0.52,
        ),
        Radius.circular(height * 0.12),
      ),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(feet.dx - height * 0.02, feet.dy - height * 0.3, height * 0.04, height * 0.3),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RescueSilhouettePainter oldDelegate) => false;
}
