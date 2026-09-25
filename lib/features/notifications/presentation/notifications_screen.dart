import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/models/app_notification.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import 'notification_providers.dart';

/// Notification inbox (design system §11.12) — P0 first, then newest, with
/// quiet-hours exceptions made visible ("bypassed quiet hours").
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = AppPalette.of(context);
    final AsyncValue<List<AppNotification>> notifications =
        ref.watch(notificationsProvider);
    final int unread = ref.watch(unreadNotificationCountProvider);
    final List<Broadcast> broadcasts =
        ref.watch(broadcastsProvider).valueOrNull ?? const <Broadcast>[];

    return Scaffold(
      body: Column(
        children: <Widget>[
          const OfflineBanner(),
          SafeArea(
            bottom: false,
            child: AppResponsiveBody(
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(context.tr('notif.title'), style: AppText.headline),
                            const SizedBox(height: 2),
                            Text(
                              unread == 0
                                  ? 'You are all caught up'
                                  : '$unread ${context.tr('notif.unread')}',
                              style: AppText.caption.copyWith(color: palette.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (unread > 0)
                        AppButton(
                          label: context.tr('notif.markAllRead'),
                          variant: AppButtonVariant.secondary,
                          compact: true,
                          expand: false,
                          onPressed: () =>
                              ref.read(notificationsProvider.notifier).markAllRead(),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.lg,
                  AppSizes.md,
                  AppSizes.lg,
                  AppSizes.xxl,
                ),
                children: <Widget>[
                  if (broadcasts.isNotEmpty) ...<Widget>[
                    SectionHeader(title: 'Authority broadcasts'),
                    for (final Broadcast broadcast in broadcasts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSizes.md),
                        child: AppCard(
                          tint: palette.tint(broadcast.severity.color),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  AppIconTile(
                                    icon: Icons.campaign_outlined,
                                    color: broadcast.severity.color,
                                  ),
                                  const SizedBox(width: AppSizes.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(broadcast.title, style: AppText.bodyStrong),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Sent ${Formatters.relativeTime(broadcast.sentAt)} · '
                                          '${Formatters.compact(broadcast.recipientCount)} recipients · '
                                          '${broadcast.languages.join('/')}',
                                          style: AppText.caption
                                              .copyWith(color: palette.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSizes.sm),
                              Text(
                                broadcast.localizedMessage(
                                  Localizations.localeOf(context).languageCode,
                                ),
                                style: AppText.body,
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSizes.md),
                  ],
                  const _NotificationPreferencesCard(),
                  const SizedBox(height: AppSizes.lg),
                  notifications.when(
                    data: (List<AppNotification> list) {
                      if (list.isEmpty) {
                        return EmptyState(
                          icon: Icons.notifications_none,
                          title: context.tr('notif.empty'),
                          message: 'Assignments, escalations and area alerts land here.',
                        );
                      }
                      return Column(
                        children: list
                            .map(
                              (AppNotification notification) => Padding(
                                padding: const EdgeInsets.only(bottom: AppSizes.md),
                                child: _NotificationCard(
                                  notification: notification,
                                  onTap: () {
                                    ref
                                        .read(notificationsProvider.notifier)
                                        .markRead(notification.id);
                                    final String? link = notification.deepLink;
                                    if (link != null) context.go(link);
                                  },
                                ),
                              ),
                            )
                            .toList(growable: false),
                      );
                    },
                    loading: () => const AppCard(child: LoadingView()),
                    error: (Object error, StackTrace _) => AppCard(
                      child: ErrorView(
                        message: error.toString(),
                        onRetry: () =>
                            ref.read(notificationsProvider.notifier).refresh(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return AppCard(
      onTap: onTap,
      tint: notification.isRead ? null : palette.tint(notification.priority.color),
      semanticLabel: '${notification.priority.label} ${notification.title}. '
          '${notification.body}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppIconTile(icon: notification.icon, color: notification.priority.color),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(notification.title, style: AppText.bodyStrong),
                    ),
                    if (!notification.isRead)
                      Container(
                        height: 8,
                        width: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(notification.body, style: AppText.body),
                const SizedBox(height: AppSizes.sm),
                Wrap(
                  spacing: AppSizes.sm,
                  runSpacing: AppSizes.xs,
                  children: <Widget>[
                    StatusChip(
                      label: notification.priority.label,
                      color: notification.priority.color,
                    ),
                    StatusChip(
                      label: notification.channel.name,
                      color: palette.textSecondary,
                      icon: notification.channel.icon,
                    ),
                    if (notification.priority.bypassesQuietHours)
                      const StatusChip(
                        label: 'BYPASSED QUIET HOURS',
                        color: AppColors.purple,
                        icon: Icons.nightlight_off_outlined,
                      ),
                    Text(
                      Formatters.relativeTime(notification.createdAt),
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationPreferencesCard extends ConsumerWidget {
  const _NotificationPreferencesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NotificationPreferences prefs = ref.watch(notificationPreferencesProvider);
    final AppPalette palette = AppPalette.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const AppIconTile(icon: Icons.tune, color: AppColors.primary),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Delivery channels', style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      'P0/P1 alerts bypass quiet hours',
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: prefs.push,
            onChanged: (bool value) => ref
                .read(notificationPreferencesProvider.notifier)
                .update(prefs.copyWith(push: value)),
            title: Text('Push notifications', style: AppText.body),
            secondary: const Icon(Icons.notifications_active_outlined),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: prefs.sms,
            onChanged: (bool value) => ref
                .read(notificationPreferencesProvider.notifier)
                .update(prefs.copyWith(sms: value)),
            title: Text('SMS fallback', style: AppText.body),
            secondary: const Icon(Icons.sms_outlined),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: prefs.quietHoursEnabled,
            onChanged: (bool value) => ref
                .read(notificationPreferencesProvider.notifier)
                .update(prefs.copyWith(quietHoursEnabled: value)),
            title: Text('Quiet hours (22:00 – 06:00)', style: AppText.body),
            secondary: const Icon(Icons.nightlight_outlined),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: prefs.criticalBypass,
            onChanged: (bool value) => ref
                .read(notificationPreferencesProvider.notifier)
                .update(prefs.copyWith(criticalBypass: value)),
            title: Text('Critical alerts always bypass', style: AppText.body),
            subtitle: Text(
              'Life-safety notifications override quiet hours',
              style: AppText.caption.copyWith(color: palette.textSecondary),
            ),
            secondary: const Icon(Icons.priority_high),
          ),
        ],
      ),
    );
  }
}
