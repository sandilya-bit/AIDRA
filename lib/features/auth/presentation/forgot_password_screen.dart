import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/aidra_logo.dart';
import '../../../core/widgets/app_widgets.dart';
import 'auth_providers.dart';

/// Account recovery (PRD FR-1102).
///
/// Sends a Firebase password-reset email. Two deliberate choices:
///
///  * **The response never varies.** Whether or not the address exists, the
///    copy is identical, so this screen cannot be used to enumerate AIDRA
///    accounts — which for a platform holding location data of vulnerable
///    people is not a theoretical concern.
///  * **Phone-only accounts are redirected, not ignored.** A user who signed up
///    with a number has no password to reset; code sign-in is their recovery
///    path, and saying so beats a dead end.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _identifier = TextEditingController();

  bool _sent = false;

  @override
  void dispose() {
    _identifier.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bool ok = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordReset(identifier: _identifier.text);
    if (!mounted) return;
    // Only advance on success — a validation error (a phone number, say) must
    // stay visible so the user can correct it.
    if (ok) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AuthState auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('auth.resetTitle')),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: AppResponsiveBody(
          maxWidth: 460,
          padding: const EdgeInsets.fromLTRB(
            AppSizes.lg,
            AppSizes.md,
            AppSizes.lg,
            AppSizes.xl,
          ),
          child: SingleChildScrollView(
            child: _sent ? _buildSent(context, palette) : _buildForm(context, palette, auth),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, AppPalette palette, AuthState auth) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSizes.md),
          const Center(child: AidraLockup(logoSize: 64)),
          const SizedBox(height: AppSizes.lg),
          Text(
            context.tr('auth.resetBody'),
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSizes.lg),
          if (auth.error != null) ...<Widget>[
            _Banner(message: auth.error!, tone: _BannerTone.error),
            const SizedBox(height: AppSizes.md),
          ],
          TextFormField(
            controller: _identifier,
            autofillHints: const <String>[AutofillHints.username],
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: context.tr('auth.emailOrPhone'),
              hintText: 'you@example.com',
              prefixIcon: const Icon(Icons.alternate_email),
              border: const OutlineInputBorder(),
            ),
            validator: Validators.emailOrPhone,
            onFieldSubmitted: (_) => unawaited(_submit()),
          ),
          const SizedBox(height: AppSizes.lg),
          AppButton(
            label: context.tr('auth.sendResetLink'),
            icon: Icons.mark_email_read_outlined,
            isLoading: auth.isBusy,
            onPressed: auth.isBusy ? null : () => unawaited(_submit()),
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            context.tr('auth.resetPhoneInstead'),
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSizes.sm),
          Center(
            child: TextButton(
              onPressed: () => context.go('/login'),
              child: Text(
                context.tr('auth.login'),
                style: AppText.bodyStrong.copyWith(color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSent(BuildContext context, AppPalette palette) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const SizedBox(height: AppSizes.xl),
        const Center(
          child: Icon(
            Icons.outgoing_mail,
            size: 56,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        Text(
          context.tr('auth.resetTitle'),
          textAlign: TextAlign.center,
          style: AppText.display.copyWith(fontSize: 24),
        ),
        const SizedBox(height: AppSizes.sm),
        Text(
          context.tr('auth.resetSent'),
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: AppSizes.xl),
        AppButton(
          label: context.tr('common.back'),
          icon: Icons.arrow_back,
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }
}

enum _BannerTone { error, info }

class _Banner extends StatelessWidget {
  const _Banner({required this.message, this.tone = _BannerTone.info});

  final String message;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final bool isError = tone == _BannerTone.error;
    return Semantics(
      liveRegion: true,
      child: AppCard(
        tint: isError ? AppColors.dangerSoft : AppColors.primarySoft,
        padding: const EdgeInsets.all(AppSizes.md),
        child: Row(
          children: <Widget>[
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              size: 18,
              color: isError ? AppColors.danger : AppColors.primary,
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(
                message,
                style: AppText.caption.copyWith(
                  color: isError ? AppColors.danger : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
