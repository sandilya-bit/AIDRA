import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/di/providers.dart';
import '../../../core/models/geo_point.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/aidra_logo.dart';
import '../../../core/widgets/app_widgets.dart';
import 'auth_providers.dart';

/// Registration (design system §4.2 footer → Sign Up).
///
/// Collects the details each role needs: every account needs a name and
/// contact, coordinators (NGO / hospital / authority) additionally need an
/// organization — the same rule the API and the `users_org_role_consistency`
/// constraint enforce server-side.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _fullName = TextEditingController();
  final TextEditingController _contact = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _organization = TextEditingController();

  UserRole _role = UserRole.victim;
  bool _obscure = true;
  bool _shareLocation = true;

  @override
  void initState() {
    super.initState();
    _role = ref.read(appSettingsProvider).role;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _contact.dispose();
    _password.dispose();
    _organization.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final AuthState auth = ref.watch(authControllerProvider);

    // Navigation on success is handled by the router's auth redirect.
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: AppTopBar(
          title: context.tr('auth.createAccount'),
          subtitle: context.tr('auth.registerHint'),
          onBack: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: AppResponsiveBody(
          maxWidth: 520,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Center(child: AidraLockup(logoSize: 64, showTagline: false)),
                  const SizedBox(height: AppSizes.lg),
                  TextFormField(
                    controller: _fullName,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: context.tr('auth.fullName'),
                      prefixIcon: const Icon(Icons.person_outline),
                      border: const OutlineInputBorder(),
                    ),
                    validator: Validators.fullName,
                  ),
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: _contact,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: context.tr('auth.emailOrPhone'),
                      prefixIcon: const Icon(Icons.alternate_email),
                      border: const OutlineInputBorder(),
                    ),
                    validator: Validators.emailOrPhone,
                  ),
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: context.tr('auth.password'),
                      helperText: 'At least 8 characters',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        icon: Icon(
                          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: Validators.password,
                  ),
                  const SizedBox(height: AppSizes.lg),
                  Text(
                    context.tr('auth.chooseRole').toUpperCase(),
                    style: AppText.label.copyWith(color: palette.textSecondary),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  Wrap(
                    spacing: AppSizes.sm,
                    runSpacing: AppSizes.sm,
                    children: UserRole.values.map((UserRole role) {
                      return AppChoiceChip(
                        label: role.shortLabel,
                        icon: role.icon,
                        selected: role == _role,
                        onSelected: () => setState(() => _role = role),
                      );
                    }).toList(growable: false),
                  ),
                  if (_role.requiresOrganization) ...<Widget>[
                    const SizedBox(height: AppSizes.md),
                    TextFormField(
                      controller: _organization,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: context.tr('auth.organization'),
                        hintText: 'Red Crescent Hyderabad',
                        prefixIcon: const Icon(Icons.apartment_outlined),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (String? value) => _role.requiresOrganization
                          ? Validators.required(value, label: 'Organization')
                          : null,
                    ),
                  ],
                  const SizedBox(height: AppSizes.md),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.md,
                      vertical: AppSizes.xs,
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _shareLocation,
                      onChanged: (bool value) => setState(() => _shareLocation = value),
                      title: Text('Share live location', style: AppText.bodyStrong),
                      subtitle: Text(
                        'Used only to match you with nearby incidents.',
                        style: AppText.caption.copyWith(color: palette.textSecondary),
                      ),
                    ),
                  ),
                  if (auth.error != null) ...<Widget>[
                    const SizedBox(height: AppSizes.md),
                    AppCard(
                      tint: AppColors.dangerSoft,
                      padding: const EdgeInsets.all(AppSizes.md),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                          const SizedBox(width: AppSizes.sm),
                          Expanded(
                            child: Text(
                              auth.error!,
                              style: AppText.caption.copyWith(color: AppColors.danger),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSizes.lg),
                  AppButton(
                    label: context.tr('auth.createAccount'),
                    icon: Icons.check_circle_outline,
                    isLoading: auth.isBusy,
                    onPressed: auth.isBusy ? null : _submit,
                  ),
                  const SizedBox(height: AppSizes.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        context.tr('splash.haveAccount'),
                        style: AppText.body.copyWith(color: palette.textSecondary),
                      ),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: Text(
                          context.tr('auth.login'),
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

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final bool success = await ref.read(authControllerProvider.notifier).register(
          fullName: _fullName.text,
          emailOrPhone: _contact.text,
          password: _password.text,
          role: _role,
          organizationName: _organization.text,
        );

    if (!success || !mounted) return;

    await ref.read(appSettingsProvider.notifier).setRole(_role);
    // Persist the coarse location so the first dashboard render has a centre.
    if (_shareLocation) {
      final LocalStoreWriter writer = LocalStoreWriter(ref);
      await writer.writeLocation(const GeoPoint(17.3850, 78.4867));
    }
    if (mounted) {
      context.go('/home');
    }
  }
}

/// Tiny helper that keeps `LocalStore` writes out of the widget body.
class LocalStoreWriter {
  const LocalStoreWriter(this._ref);

  final WidgetRef _ref;

  Future<void> writeLocation(GeoPoint point) async {
    await _ref.read(localStoreProvider).setJson('profile.last_location', point.toJson());
  }
}
