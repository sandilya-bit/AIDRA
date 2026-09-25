import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/aidra_logo.dart';
import '../../../core/widgets/app_widgets.dart';
import 'auth_providers.dart';

/// Login screen (design system §4.2).
///
/// Three sign-in modes: email/password, phone + OTP, and social. The OTP step
/// is simulated locally when the backend is not enabled so the full flow is
/// demoable end-to-end.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _identifier = TextEditingController();
  final TextEditingController _password = TextEditingController();

  int _mode = 0; // 0 email · 1 phone · 2 social
  bool _obscure = true;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final UserRole role = ref.watch(activeRoleProvider);

    // Navigation on success is handled by the router's auth redirect.
    return Scaffold(
      body: SafeArea(
        child: AppResponsiveBody(
          maxWidth: 460,
          padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.xl, AppSizes.lg, AppSizes.xl),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: AppSizes.lg),
                  const Center(child: AidraLockup(logoSize: 76, showTagline: true)),
                  const SizedBox(height: AppSizes.xl),
                  Text(
                    context.tr('auth.welcomeBack'),
                    textAlign: TextAlign.center,
                    style: AppText.display.copyWith(fontSize: 27),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr('auth.signInToContinue'),
                    textAlign: TextAlign.center,
                    style: AppText.body.copyWith(color: palette.textSecondary),
                  ),
                  const SizedBox(height: AppSizes.lg),
                  SegmentedTabs(
                    labels: <String>[
                      context.tr('auth.email'),
                      context.tr('auth.phone'),
                      context.tr('auth.google'),
                    ],
                    selectedIndex: _mode,
                    onChanged: (int index) => setState(() => _mode = index),
                  ),
                  const SizedBox(height: AppSizes.lg),
                  if (auth.error != null) ...<Widget>[
                    _ErrorBanner(message: auth.error!),
                    const SizedBox(height: AppSizes.md),
                  ],
                  // Outlives the action that caused it: "your session expired".
                  if (auth.notice != null) ...<Widget>[
                    _ErrorBanner(message: auth.notice!, tone: _BannerTone.info),
                    const SizedBox(height: AppSizes.md),
                  ],
                  ..._buildInputs(context),
                  const SizedBox(height: AppSizes.md),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _DemoRoleSelector(
                          role: role,
                          onChanged: (UserRole value) => ref
                              .read(appSettingsProvider.notifier)
                              .setRole(value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.lg),
                  AppButton(
                    label: _mode == 1
                        ? context.tr('common.continueLabel')
                        : context.tr('auth.login'),
                    icon: _mode == 1
                        ? Icons.sms_outlined
                        : Icons.login_rounded,
                    isLoading: auth.isBusy,
                    onPressed: auth.isBusy ? null : _submit,
                  ),
                  const SizedBox(height: AppSizes.sm),
                  Center(
                    child: TextButton(
                      onPressed: () => _openRecovery(context),
                      child: Text(
                        context.tr('auth.forgotPassword'),
                        style: AppText.bodyStrong.copyWith(color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.lg),
                  Row(
                    children: <Widget>[
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
                        child: Text(
                          context.tr('auth.orContinueWith'),
                          style: AppText.caption.copyWith(color: palette.textSecondary),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: AppSizes.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _SocialButton(
                        icon: Icons.g_mobiledata_rounded,
                        label: 'Google',
                        onTap: () => _signInWithProvider('google'),
                      ),
                      const SizedBox(width: AppSizes.md),
                      _SocialButton(
                        icon: Icons.apple,
                        label: 'Apple',
                        onTap: () => _signInWithProvider('apple'),
                      ),
                      const SizedBox(width: AppSizes.md),
                      _SocialButton(
                        icon: Icons.public,
                        label: 'Govt SSO',
                        onTap: () => _signInWithProvider('govt_sso'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.xl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        context.tr('auth.noAccount'),
                        style: AppText.body.copyWith(color: palette.textSecondary),
                      ),
                      TextButton(
                        onPressed: () => context.go('/register'),
                        child: Text(
                          context.tr('auth.signUp'),
                          style: AppText.bodyStrong.copyWith(color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildInputs(BuildContext context) {
    if (_mode == 2) {
      return <Widget>[
        Text(
          'Sign in with your Google, Apple or government identity. '
          'AIDRA only reads your name and language preference.',
          style: AppText.body.copyWith(color: AppPalette.of(context).textSecondary),
        ),
      ];
    }

    if (_mode == 1) {
      // The code is entered on its own screen (OtpScreen), which owns the
      // resend cooldown and the "already signed in" shortcut.
      return <Widget>[
        TextFormField(
          controller: _identifier,
          keyboardType: TextInputType.phone,
          autofillHints: const <String>[AutofillHints.telephoneNumber],
          decoration: InputDecoration(
            labelText: context.tr('auth.phone'),
            hintText: '+91 90000 00000',
            prefixIcon: const Icon(Icons.phone_outlined),
            border: const OutlineInputBorder(),
          ),
          validator: Validators.phone,
        ),
        const SizedBox(height: AppSizes.sm),
        Text(
          context.tr('auth.otpSentTo'),
          style: AppText.caption.copyWith(color: AppPalette.of(context).textSecondary),
        ),
      ];
    }

    return <Widget>[
      TextFormField(
        controller: _identifier,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const <String>[AutofillHints.username],
        decoration: InputDecoration(
          labelText: context.tr('auth.emailOrPhone'),
          hintText: 'you@example.com',
          prefixIcon: const Icon(Icons.alternate_email),
          border: const OutlineInputBorder(),
        ),
        validator: Validators.emailOrPhone,
      ),
      const SizedBox(height: AppSizes.md),
      TextFormField(
        controller: _password,
        obscureText: _obscure,
        autofillHints: const <String>[AutofillHints.password],
        decoration: InputDecoration(
          labelText: context.tr('auth.password'),
          prefixIcon: const Icon(Icons.lock_outline),
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: _obscure ? 'Show password' : 'Hide password',
            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        validator: Validators.password,
      ),
    ];
  }

  Future<void> _submit() async {
    final UserRole role = ref.read(activeRoleProvider);
    if (_mode == 2) {
      await _signInWithProvider('google');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final AuthController controller = ref.read(authControllerProvider.notifier);

    if (_mode == 1) {
      final PhoneVerificationResult result = await controller.requestPhoneCode(
        phone: _identifier.text,
        role: role,
      );
      if (!mounted) return;
      switch (result) {
        case PhoneVerificationResult.autoSignedIn:
          context.go('/home');
        case PhoneVerificationResult.codeSent:
          context.push('/otp');
        case PhoneVerificationResult.failed:
          break;
      }
      return;
    }

    await controller.signIn(
      emailOrPhone: _identifier.text,
      password: _password.text,
      role: role,
    );
    if (mounted && ref.read(authControllerProvider).isAuthenticated) {
      context.go('/home');
    }
  }

  Future<void> _signInWithProvider(String provider) async {
    final UserRole role = ref.read(activeRoleProvider);
    await ref
        .read(authControllerProvider.notifier)
        .signInWithProvider(provider: provider, role: role);
    if (mounted && ref.read(authControllerProvider).isAuthenticated) {
      context.go('/home');
    }
  }

  /// Account recovery lives on its own route so it can be deep-linked from a
  /// lock screen or a support message.
  void _openRecovery(BuildContext context) => context.push('/forgot-password');
}

enum _BannerTone { error, info }

/// Inline message. `liveRegion` so screen readers announce an error or a
/// "session expired" notice without the user having to hunt for it.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.tone = _BannerTone.error});

  final String message;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final bool isError = tone == _BannerTone.error;
    final Color foreground = isError ? AppColors.danger : AppColors.primary;
    return Semantics(
      liveRegion: true,
      child: AppCard(
        tint: isError ? AppColors.dangerSoft : AppColors.primarySoft,
        padding: const EdgeInsets.all(AppSizes.md),
        child: Row(
          children: <Widget>[
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: foreground,
              size: 18,
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(
                message,
                style: AppText.caption.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Semantics(
      button: true,
      label: 'Continue with $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radiusPill),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 20, color: palette.textPrimary),
              const SizedBox(width: 6),
              Text(label, style: AppText.caption),
            ],
          ),
        ),
      ),
    );
  }
}

/// Demo affordance: pick which role to sign in as. Kept visually light and
/// clearly labelled so it never reads as production UI.
class _DemoRoleSelector extends StatelessWidget {
  const _DemoRoleSelector({required this.role, required this.onChanged});

  final UserRole role;
  final ValueChanged<UserRole> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'DEMO ROLE',
          style: AppText.label.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: UserRole.values.map((UserRole item) {
              return Padding(
                padding: const EdgeInsets.only(right: AppSizes.sm),
                child: AppChoiceChip(
                  label: item.shortLabel,
                  selected: item == role,
                  icon: item.icon,
                  onSelected: () => onChanged(item),
                ),
              );
            }).toList(growable: false),
          ),
        ),
      ],
    );
  }
}
