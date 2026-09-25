import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/di/providers.dart';
import '../../../core/models/app_user.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/presentation/auth_providers.dart';

/// Profile & settings (design system §4.13 + FR-902/1002).
///
/// Appearance (light/dark/system), language, accessibility, offline behaviour,
/// sync controls and the demo role switcher used to review every dashboard.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = AppPalette.of(context);
    final AppSettings settings = ref.watch(appSettingsProvider);
    final AppUser? user = ref.watch(currentUserProvider);
    final AuthState auth = ref.watch(authControllerProvider);
    final SyncState sync = ref.watch(syncControllerProvider);
    final LocalStoreStats stats = _stats(ref);

    return Scaffold(
      body: Column(
        children: <Widget>[
          const OfflineBanner(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                AppResponsiveBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _ProfileHeader(user: user, role: settings.role),
                      const SizedBox(height: AppSizes.lg),
                      _SyncCard(sync: sync, stats: stats),
                      const SizedBox(height: AppSizes.lg),
                      SectionHeader(title: context.tr('profile.appearance')),
                      AppCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.md,
                          vertical: AppSizes.xs,
                        ),
                        child: Column(
                          children: <Widget>[
                            SegmentedTabs(
                              labels: const <String>['System', 'Light', 'Dark'],
                              selectedIndex: settings.themeMode.index,
                              onChanged: (int index) => ref
                                  .read(appSettingsProvider.notifier)
                                  .setThemeMode(ThemeMode.values[index]),
                            ),
                            const SizedBox(height: AppSizes.sm),
                            _InfoRow(
                              icon: Icons.contrast,
                              label: 'Current mode',
                              value: settings.themeMode.name,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSizes.lg),
                      SectionHeader(title: context.tr('profile.language')),
                      AppCard(
                        padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
                        child: Column(
                          children: <Widget>[
                            for (int i = 0; i < AppConfig.supportedLocales.length; i++)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                onTap: () => ref
                                    .read(appSettingsProvider.notifier)
                                    .setLanguage(
                                      AppConfig.supportedLocales[i].languageCode,
                                    ),
                                leading: Icon(
                                  AppConfig.supportedLocales[i].languageCode ==
                                          settings.languageCode
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  color: AppConfig.supportedLocales[i].languageCode ==
                                          settings.languageCode
                                      ? AppColors.primary
                                      : palette.textSecondary,
                                ),
                                title: Text(
                                  AppConfig.supportedLanguageNames[i],
                                  style: AppText.body,
                                ),
                                subtitle: Text(
                                  'UI, notifications and broadcasts in this language',
                                  style: AppText.caption.copyWith(color: palette.textSecondary),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSizes.lg),
                      SectionHeader(title: context.tr('profile.accessibility')),
                      AppCard(
                        padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
                        child: Column(
                          children: <Widget>[
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: settings.observeLargeText,
                              onChanged: (bool value) =>
                                  ref.read(appSettingsProvider.notifier).setLargeText(value),
                              title: Text(context.tr('profile.largeText'), style: AppText.body),
                              subtitle: Text(
                                'Follows your device text size by default',
                                style: AppText.caption.copyWith(color: palette.textSecondary),
                              ),
                              secondary: const Icon(Icons.format_size),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: settings.highContrast,
                              onChanged: (bool value) =>
                                  ref.read(appSettingsProvider.notifier).setHighContrast(value),
                              title: Text(context.tr('profile.highContrast'), style: AppText.body),
                              secondary: const Icon(Icons.brightness_high_outlined),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: settings.reduceMotion,
                              onChanged: (bool value) =>
                                  ref.read(appSettingsProvider.notifier).setReduceMotion(value),
                              title: Text(context.tr('profile.reduceMotion'), style: AppText.body),
                              subtitle: Text(
                                'Stops the map radar pulse and list animations',
                                style: AppText.caption.copyWith(color: palette.textSecondary),
                              ),
                              secondary: const Icon(Icons.motion_photos_off_outlined),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSizes.lg),
                      SectionHeader(title: context.tr('profile.offline')),
                      AppCard(
                        padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
                        child: Column(
                          children: <Widget>[
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: settings.offlineModeEnabled,
                              onChanged: (bool value) =>
                                  ref.read(appSettingsProvider.notifier).setOfflineMode(value),
                              title: Text('Force offline mode', style: AppText.body),
                              subtitle: Text(
                                'Demos the queue-and-sync path without losing signal',
                                style: AppText.caption.copyWith(color: palette.textSecondary),
                              ),
                              secondary: const Icon(Icons.cloud_off_outlined),
                            ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.sync),
                              title: Text(context.tr('profile.syncNow'), style: AppText.body),
                              subtitle: Text(
                                '${sync.pending} pending · '
                                '${sync.failed} failed · '
                                'last success ${sync.lastSyncedAt == null ? 'never' : Formatters.relativeTime(sync.lastSyncedAt!)}',
                                style: AppText.caption.copyWith(color: palette.textSecondary),
                              ),
                              trailing: sync.isSyncing
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.chevron_right),
                              onTap: () async {
                                final SyncResult? result = await ref
                                    .read(syncControllerProvider.notifier)
                                    .flush(force: true);
                                if (!context.mounted || result == null) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      result.isClean
                                          ? 'Everything is synced.'
                                          : '${result.synced} sent · ${result.remaining} still queued.',
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSizes.lg),
                      SectionHeader(title: context.tr('profile.switchRole')),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Switch the active role to review each dashboard. '
                              'In production this comes from your account permissions.',
                              style: AppText.caption.copyWith(color: palette.textSecondary),
                            ),
                            const SizedBox(height: AppSizes.sm),
                            Wrap(
                              spacing: AppSizes.sm,
                              runSpacing: AppSizes.sm,
                              children: UserRole.values
                                  .map(
                                    (UserRole role) => AppChoiceChip(
                                      label: role.shortLabel,
                                      icon: role.icon,
                                      selected: role == settings.role,
                                      onSelected: () async {
                                        await ref
                                            .read(appSettingsProvider.notifier)
                                            .setRole(role);
                                        await ref
                                            .read(authControllerProvider.notifier)
                                            .switchRole(role);
                                        if (context.mounted) context.go('/home');
                                      },
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSizes.lg),
                      SectionHeader(title: context.tr('profile.account')),
                      AppCard(
                        padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
                        child: Column(
                          children: <Widget>[
                            _InfoRow(
                              icon: Icons.badge_outlined,
                              label: 'Role',
                              value: settings.role.label,
                            ),
                            _InfoRow(
                              icon: Icons.verified_user_outlined,
                              label: 'Verification',
                              value: user?.verificationState.label ?? '—',
                            ),
                            _InfoRow(
                              icon: Icons.language,
                              label: 'Language',
                              value: context.l10n.languageName,
                            ),
                            _InfoRow(
                              icon: Icons.build_outlined,
                              label: 'App version',
                              value: AppConfig.version,
                            ),
                            _InfoRow(
                              icon: Icons.cloud_outlined,
                              label: 'Backend',
                              value: AppConfig.useRemoteBackend
                                  ? 'Remote (${AppConfig.apiBaseUrl})'
                                  : 'Demo dataset (offline)',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSizes.lg),
                      AppButton(
                        label: context.tr('profile.logout'),
                        variant: AppButtonVariant.danger,
                        icon: Icons.logout,
                        isLoading: auth.isBusy,
                        onPressed: () async {
                          await ref.read(authControllerProvider.notifier).signOut();
                          if (context.mounted) context.go('/login');
                        },
                      ),
                      const SizedBox(height: AppSizes.xxl),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  LocalStoreStats _stats(WidgetRef ref) {
    final store = ref.watch(localStoreProvider);
    return LocalStoreStats(
      cachedReports: store.getJsonList('cache.reports').length,
      cachedIncidents: store.getJsonList('cache.incidents').length,
      queued: store.getJsonList('queue.outbox').length,
    );
  }
}

class LocalStoreStats {
  const LocalStoreStats({
    required this.cachedReports,
    required this.cachedIncidents,
    required this.queued,
  });

  final int cachedReports;
  final int cachedIncidents;
  final int queued;
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.role});

  final AppUser? user;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final String name = user?.fullName ?? 'AIDRA User';

    return NavySurface(
      radius: AppSizes.radiusLg,
      padding: const EdgeInsets.all(AppSizes.xl),
      child: Row(
        children: <Widget>[
          AppAvatar(
            name: name,
            size: 58,
            statusColor: (user?.isVerified ?? false)
                ? AppColors.success
                : AppColors.warning,
          ),
          const SizedBox(width: AppSizes.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name, style: AppText.title.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  user?.primaryContact ?? 'offline profile',
                  style: AppText.caption.copyWith(color: AppColors.whiteMuted),
                ),
                const SizedBox(height: AppSizes.sm),
                Row(
                  children: <Widget>[
                    StatusChip(
                      label: role.shortLabel,
                      color: AppColors.primary,
                      icon: role.icon,
                      filled: true,
                    ),
                    const SizedBox(width: AppSizes.sm),
                    StatusChip(
                      label: user?.verificationState.label ?? 'Unverified',
                      color: (user?.isVerified ?? false)
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                  ],
                ),
                if (user?.organizationName != null) ...<Widget>[
                  const SizedBox(height: AppSizes.sm),
                  Text(
                    user!.organizationName!,
                    style: AppText.caption.copyWith(color: AppColors.whiteMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.sync, required this.stats});

  final SyncState sync;
  final LocalStoreStats stats;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final Color statusColor = !sync.isOnline
        ? AppColors.warning
        : (sync.pending > 0 ? AppColors.primary : AppColors.success);

    return AppCard(
      child: Row(
        children: <Widget>[
          AppIconTile(
            icon: sync.isOnline ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            color: statusColor,
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  sync.isOnline ? 'Online' : 'Offline — working from cache',
                  style: AppText.bodyStrong,
                ),
                const SizedBox(height: 2),
                Text(
                  '${stats.cachedReports} reports · ${stats.cachedIncidents} incidents cached · '
                  '${sync.pending} queued',
                  style: AppText.caption.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          StatusChip(
            label: sync.isSyncing ? 'SYNCING' : 'IDLE',
            color: statusColor,
            filled: true,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20),
      title: Text(label, style: AppText.body),
      trailing: Text(
        value,
        style: AppText.bodyStrong,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
