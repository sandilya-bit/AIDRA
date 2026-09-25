import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/widgets/aidra_logo.dart';
import '../../../core/widgets/app_widgets.dart';
import 'auth_providers.dart';

/// Phone OTP step (PRD FR-1101).
///
/// Sits between the login screen's Phone tab and the dashboard. Firebase sends
/// the SMS and verifies the code; AIDRA only ever sees the signed result, so
/// this screen never touches the code beyond handing it to the repository.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const Duration _resendCooldown = Duration(seconds: 30);

  final TextEditingController _code = TextEditingController();
  Timer? _countdown;
  int _secondsLeft = _resendCooldown.inSeconds;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdown?.cancel();
    _secondsLeft = _resendCooldown.inSeconds;
    _countdown = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  Future<void> _verify() async {
    final String code = _code.text.trim();
    final int required = AppConfig.useFirebase ? AppConfig.otpLength : 4;
    if (code.length < required) {
      _snack(context.tr('auth.otpInvalid'));
      return;
    }

    final bool ok = await ref
        .read(authControllerProvider.notifier)
        .confirmPendingPhoneCode(code);
    if (!mounted) return;
    if (ok) {
      context.go('/home');
    }
  }

  Future<void> _resend() async {
    final PhoneVerificationResult result =
        await ref.read(authControllerProvider.notifier).resendPhoneCode();
    if (!mounted) return;

    switch (result) {
      case PhoneVerificationResult.autoSignedIn:
        context.go('/home');
      case PhoneVerificationResult.codeSent:
        setState(_startCountdown);
      case PhoneVerificationResult.failed:
        break;
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final PhoneChallengeArgs? pending = ref.watch(pendingPhoneChallengeProvider);
    final AuthState auth = ref.watch(authControllerProvider);

    // Reached without a challenge (deep link, or the provider restarting):
    // send the user back rather than showing a dead form.
    if (pending == null) {
      return Scaffold(
        body: SafeArea(
          child: EmptyState(
            icon: Icons.sms_failed_outlined,
            title: context.tr('auth.otpTitle'),
            message: context.tr('auth.changeNumber'),
            actionLabel: context.tr('common.back'),
            onAction: () => context.go('/login'),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: AppResponsiveBody(
          maxWidth: 460,
          padding: const EdgeInsets.fromLTRB(
            AppSizes.lg,
            AppSizes.xl,
            AppSizes.lg,
            AppSizes.xl,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: AppSizes.lg),
                const Center(child: AidraLockup(logoSize: 64)),
                const SizedBox(height: AppSizes.lg),
                Text(
                  context.tr('auth.otpTitle'),
                  textAlign: TextAlign.center,
                  style: AppText.display.copyWith(fontSize: 24),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    text: '${context.tr('auth.otpSentTo')} ',
                    children: <InlineSpan>[
                      TextSpan(
                        text: pending.phone,
                        style: AppText.bodyStrong,
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: AppText.body.copyWith(color: palette.textSecondary),
                ),
                const SizedBox(height: AppSizes.lg),
                if (auth.error != null) ...<Widget>[
                  AppCard(
                    tint: AppColors.dangerSoft,
                    padding: const EdgeInsets.all(AppSizes.md),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.danger,
                          size: 18,
                        ),
                        const SizedBox(width: AppSizes.sm),
                        Expanded(
                          child: Text(
                            auth.error!,
                            style: AppText.caption
                                .copyWith(color: AppColors.danger),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),
                ],
                TextField(
                  controller: _code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  maxLength: AppConfig.otpLength,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => unawaited(_verify()),
                  style: AppText.title.copyWith(letterSpacing: 8),
                  decoration: InputDecoration(
                    labelText: context.tr('auth.otpCode'),
                    counterText: '',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (pending.isDemo) ...<Widget>[
                  const SizedBox(height: AppSizes.sm),
                  Text(
                    context.tr('auth.otpDemoHint'),
                    textAlign: TextAlign.center,
                    style:
                        AppText.caption.copyWith(color: palette.textSecondary),
                  ),
                ],
                const SizedBox(height: AppSizes.lg),
                AppButton(
                  label: context.tr('auth.verify'),
                  icon: Icons.verified_user_outlined,
                  isLoading: auth.isBusy,
                  onPressed: auth.isBusy ? null : () => unawaited(_verify()),
                ),
                const SizedBox(height: AppSizes.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: Text(
                        context.tr('auth.changeNumber'),
                        style: AppText.caption
                            .copyWith(color: palette.textSecondary),
                      ),
                    ),
                    TextButton(
                      onPressed: _secondsLeft == 0 ? () => unawaited(_resend()) : null,
                      child: Text(
                        _secondsLeft == 0
                            ? context.tr('auth.resend')
                            : '${context.tr('auth.resendIn')} ${_secondsLeft}s',
                        style: AppText.caption.copyWith(
                          color: _secondsLeft == 0
                              ? AppColors.primary
                              : palette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
