import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/constants/app_enums.dart';
import '../../core/models/app_user.dart';
import '../../core/widgets/app_widgets.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/notifications/presentation/notification_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';

/// Bottom-navigation shell (design system §4.3: Home · Map · Reports · More).
///
/// Uses a custom bar rather than `NavigationBar` so the pill highlight and
/// badge behave exactly like the reference, and so the app stays resilient to
/// Material theme-object renames across Flutter releases.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int unread = ref.watch(unreadNotificationCountProvider);
    final Duration? idleWarning =
        ref.watch(authControllerProvider).idleWarning;

    return Scaffold(
      body: Column(
        children: <Widget>[
          // Auto-logout is announced before it happens, so a coordinator mid
          // handover is never dropped without warning.
          if (idleWarning != null) _SessionWarning(remaining: idleWarning),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: _AppBottomNav(
        currentIndex: navigationShell.currentIndex,
        unreadCount: unread,
        onSelect: (int index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

/// "You will be signed out soon" bar with a one-tap reprieve.
class _SessionWarning extends ConsumerWidget {
  const _SessionWarning({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      liveRegion: true,
      child: Material(
        color: AppColors.warningSoft,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md,
              vertical: AppSizes.xs,
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.timer_outlined,
                  size: 18,
                  color: AppColors.warning,
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    context.tr('auth.sessionWarning'),
                    style: AppText.caption,
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).keepAlive(),
                  child: Text(
                    context.tr('auth.staySignedIn'),
                    style: AppText.caption.copyWith(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppBottomNav extends StatelessWidget {
  const _AppBottomNav({
    required this.currentIndex,
    required this.onSelect,
    required this.unreadCount,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    final List<_NavItem> items = <_NavItem>[
      _NavItem(
        label: context.tr('nav.home'),
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
      ),
      _NavItem(
        label: context.tr('nav.map'),
        icon: Icons.map_outlined,
        activeIcon: Icons.map_rounded,
      ),
      _NavItem(
        label: context.tr('nav.reports'),
        icon: Icons.assignment_outlined,
        activeIcon: Icons.assignment_rounded,
      ),
      _NavItem(
        label: context.tr('nav.more'),
        icon: Icons.grid_view_outlined,
        activeIcon: Icons.grid_view_rounded,
        badge: unreadCount,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List<Widget>.generate(items.length, (int index) {
            final _NavItem item = items[index];
            final bool selected = index == currentIndex;

            return Expanded(
              child: Semantics(
                button: true,
                selected: selected,
                label: item.label,
                child: InkWell(
                  onTap: () => onSelect(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Stack(
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            Icon(
                              selected ? item.activeIcon : item.icon,
                              size: 22,
                              color: selected
                                  ? AppColors.primary
                                  : palette.textSecondary,
                            ),
                            if (item.badge > 0)
                              Positioned(
                                right: -8,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.danger,
                                    borderRadius: BorderRadius.circular(
                                      AppSizes.radiusPill,
                                    ),
                                  ),
                                  child: Text(
                                    item.badge > 9 ? '9+' : '${item.badge}',
                                    style: AppText.label.copyWith(
                                      color: Colors.white,
                                      fontSize: 8,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          style: AppText.label.copyWith(
                            color: selected ? AppColors.primary : palette.textSecondary,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badge = 0,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final int badge;
}

/// "More" tab: role-aware destination list plus the profile card.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = AppPalette.of(context);
    final UserRole role = ref.watch(effectiveRoleProvider);
    final AppUser? user = ref.watch(currentUserProvider);

    final List<_MoreEntry> entries = <_MoreEntry>[
      _MoreEntry(
        label: context.tr('nav.volunteers'),
        subtitle: 'Match, dispatch and track responders',
        icon: Icons.volunteer_activism_outlined,
        color: AppColors.warning,
        route: '/volunteers',
      ),
      _MoreEntry(
        label: context.tr('hosp.title'),
        subtitle: 'Live capacity and casualty pre-alerts',
        icon: Icons.local_hospital_outlined,
        color: AppColors.success,
        route: '/hospital',
      ),
      _MoreEntry(
        label: context.tr('res.title'),
        subtitle: 'Inventory, burn rate and inter-org requests',
        icon: Icons.inventory_2_outlined,
        color: AppColors.primary,
        route: '/resources',
      ),
      _MoreEntry(
        label: context.tr('ngo.title'),
        subtitle: 'Coverage map and field teams',
        icon: Icons.diversity_3_outlined,
        color: AppColors.purple,
        route: '/ngo',
      ),
      _MoreEntry(
        label: context.tr('notif.title'),
        subtitle: 'Assignments, escalations and area alerts',
        icon: Icons.campaign_outlined,
        color: AppColors.danger,
        route: '/notifications',
      ),
      _MoreEntry(
        label: context.tr('dash.chatSupport'),
        subtitle: 'Assist and human coordinator handoff',
        icon: Icons.support_agent_outlined,
        color: AppColors.purple,
        route: '/support',
      ),
    ];

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        const OfflineBanner(),
        AppResponsiveBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppCard(
                onTap: () => context.go('/profile'),
                semanticLabel: 'Open profile and settings',
                child: Row(
                  children: <Widget>[
                    AppAvatar(
                      name: user?.fullName ?? 'AIDRA User',
                      size: 50,
                      statusColor: AppColors.success,
                    ),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            user?.fullName ?? 'AIDRA User',
                            style: AppText.title,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${role.label} · ${user?.organizationName ?? 'AIDRA network'}',
                            style: AppText.caption.copyWith(color: palette.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              for (final _MoreEntry entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm),
                  child: AppCard(
                    padding: const EdgeInsets.all(AppSizes.sm),
                    onTap: () => context.go(entry.route),
                    semanticLabel: entry.label,
                    child: Row(
                      children: <Widget>[
                        AppIconTile(icon: entry.icon, color: entry.color, size: 40),
                        const SizedBox(width: AppSizes.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(entry.label, style: AppText.bodyStrong),
                              const SizedBox(height: 2),
                              Text(
                                entry.subtitle,
                                style: AppText.caption.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSizes.lg),
              Text(
                'AIDRA ${role.shortLabel} workspace · works offline',
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSizes.xxl),
            ],
          ),
        ),
      ],
    );
  }
}

class _MoreEntry {
  const _MoreEntry({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.route,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
}
