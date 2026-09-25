import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/theme/app_theme.dart';
import '../constants/app_enums.dart';
import '../di/providers.dart';
import '../models/geo_point.dart';
import '../sync/sync_service.dart';

/// ---------------------------------------------------------------- layout

/// Responsive breakpoints (phone / tablet / desktop-web).
abstract final class AppBreakpoints {
  static const double tablet = 700;
  static const double desktop = 1000;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tablet;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktop;

  /// Column count for card grids: 1 phone, 2 tablet, 3 desktop.
  static int gridColumns(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    if (width >= desktop) return 3;
    if (width >= tablet) return 2;
    return 1;
  }

  /// Dashboard quick-action grid is 2×2 on phones, wider on big screens.
  static int quickActionColumns(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tablet ? 4 : 2;
}

/// Constrains content on wide screens so the mobile-first design still reads
/// well in a browser (work order: responsive).
class AppResponsiveBody extends StatelessWidget {
  const AppResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.padding = AppSizes.screenPadding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// ---------------------------------------------------------------- surfaces

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSizes.lg),
    this.radius = AppSizes.radiusMd,
    this.tint,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;
  final Color? tint;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final Decoration decoration = tint != null
        ? AppDecorations.flat(palette, radius: radius).copyWith(color: tint)
        : AppDecorations.card(palette, radius: radius);

    final Widget content = Container(
      padding: padding,
      decoration: decoration,
      child: child,
    );

    if (onTap == null) return content;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: content,
        ),
      ),
    );
  }
}

/// Navy surface used by the splash screen, map header and hero sections.
class NavySurface extends StatelessWidget {
  const NavySurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSizes.lg),
    this.radius = 0,
    this.withGradient = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool withGradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.navy,
        gradient: withGradient ? AppColors.navyGradient : null,
        borderRadius: radius == 0 ? null : BorderRadius.circular(radius),
      ),
      child: DefaultTextStyle.merge(
        style: AppText.body.copyWith(color: AppColors.whiteMuted),
        child: IconTheme.merge(
          data: const IconThemeData(color: Colors.white),
          child: child,
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------- headers

class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const <Widget>[],
    this.navy = false,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool navy;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final Color titleColor = navy ? Colors.white : palette.textPrimary;
    final Color subColor = navy ? AppColors.whiteMuted : palette.textSecondary;

    final Widget row = Row(
      children: <Widget>[
        if (onBack != null)
          Padding(
            padding: const EdgeInsets.only(right: AppSizes.xs),
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              color: titleColor,
              tooltip: context.tr('common.back'),
              constraints: const BoxConstraints(
                minWidth: AppSizes.minTapTarget,
                minHeight: AppSizes.minTapTarget,
              ),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: AppText.title.copyWith(color: titleColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: AppText.caption.copyWith(color: subColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        ...actions,
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSizes.sm, AppSizes.sm, AppSizes.md, AppSizes.sm),
      decoration: BoxDecoration(
        color: navy ? AppColors.navyDeep : palette.surface,
        border: Border(
          bottom: BorderSide(color: navy ? AppColors.navySoft : palette.border),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            row,
            if (bottom != null) Padding(padding: const EdgeInsets.only(top: AppSizes.sm), child: bottom),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm, top: AppSizes.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(title, style: AppText.title),
          ),
          if (trailing != null) trailing!,
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: AppText.bodyStrong.copyWith(color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------- badges

class PriorityBadge extends StatelessWidget {
  const PriorityBadge({
    super.key,
    required this.urgency,
    this.compact = false,
    this.overrideLabel,
  });

  final UrgencyLevel urgency;
  final bool compact;
  final String? overrideLabel;

  @override
  Widget build(BuildContext context) {
    final Color color = urgency.color;
    return Semantics(
      label: '${overrideLabel ?? urgency.label} priority',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSizes.sm : AppSizes.md,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        ),
        child: Text(
          (overrideLabel ?? '${urgency.label} priority').toUpperCase(),
          style: AppText.label.copyWith(
            color: Colors.white,
            fontSize: compact ? 9 : 10,
          ),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color : palette.tint(color),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        border: Border.all(color: filled ? color : color.withAlpha(0x55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: filled ? Colors.white : color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: AppText.label.copyWith(
              color: filled ? Colors.white : color,
              fontSize: 10,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------- buttons

enum AppButtonVariant { primary, secondary, success, danger, ghost }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.expand = true,
    this.compact = false,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool expand;
  final bool compact;
  final bool isLoading;

  Color get _background => switch (variant) {
        AppButtonVariant.primary => AppColors.primary,
        AppButtonVariant.secondary => Colors.transparent,
        AppButtonVariant.success => AppColors.success,
        AppButtonVariant.danger => AppColors.danger,
        AppButtonVariant.ghost => Colors.transparent,
      };

  Color get _foreground => switch (variant) {
        AppButtonVariant.secondary => AppColors.primary,
        AppButtonVariant.ghost => AppColors.primary,
        _ => Colors.white,
      };

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final bool outlined = variant == AppButtonVariant.secondary;

    final Widget content = isLoading
        ? SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _foreground),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 18, color: _foreground),
                const SizedBox(width: AppSizes.sm),
              ],
              Text(
                label,
                style: AppText.bodyStrong.copyWith(color: _foreground),
              ),
            ],
          );

    final Widget button = Semantics(
      button: true,
      label: label,
      child: Material(
        color: outlined || variant == AppButtonVariant.ghost
            ? Colors.transparent
            : _background,
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSizes.lg : AppSizes.xl,
              vertical: compact ? AppSizes.sm : AppSizes.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSizes.radiusPill),
              border: Border.all(
                color: outlined
                    ? AppColors.primary
                    : (variant == AppButtonVariant.ghost ? palette.border : _background),
              ),
            ),
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.badgeCount,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final Widget button = IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: tooltip,
      color: palette.textPrimary,
      constraints: const BoxConstraints(
        minWidth: AppSizes.minTapTarget,
        minHeight: AppSizes.minTapTarget,
      ),
    );

    if (badgeCount == null || badgeCount == 0) return button;

    return Stack(
      alignment: Alignment.topRight,
      children: <Widget>[
        button,
        Positioned(
          right: 6,
          top: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.danger,
              borderRadius: BorderRadius.circular(AppSizes.radiusPill),
            ),
            child: Text(
              badgeCount! > 99 ? '99+' : '$badgeCount',
              style: AppText.label.copyWith(color: Colors.white, fontSize: 9),
            ),
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------- tiles

class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 42,
    this.radius = AppSizes.radiusSm,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Container(
      height: size,
      width: size,
      decoration: AppDecorations.tile(palette.tint(color), radius: radius),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// The 2×2 dashboard quick action ("Report Emergency", "Nearby Incidents"…).
class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
    this.badge,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          child: Ink(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSizes.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          color: AppColors.whiteSoft,
                          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                        ),
                        child: Icon(icon, color: Colors.white, size: 22),
                      ),
                      const Spacer(),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.whiteSoft,
                            borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                          ),
                          child: Text(
                            badge!,
                            style: AppText.label.copyWith(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.md),
                  Text(
                    label,
                    style: AppText.bodyStrong.copyWith(color: Colors.white),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.deltaLabel,
    this.deltaUp = true,
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? deltaLabel;
  final bool deltaUp;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.all(compact ? AppSizes.md : AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconTile(icon: icon, color: color, size: compact ? 34 : 40),
              const Spacer(),
              if (deltaLabel != null)
                Row(
                  children: <Widget>[
                    Icon(
                      deltaUp ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 13,
                      color: deltaUp ? AppColors.success : AppColors.danger,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      deltaLabel!,
                      style: AppText.caption.copyWith(
                        color: deltaUp ? AppColors.success : AppColors.danger,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          SizedBox(height: compact ? AppSizes.sm : AppSizes.md),
          Text(value, style: AppText.stat),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppText.caption.copyWith(color: AppPalette.of(context).textSecondary),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

/// Generic "leading icon · title · subtitle · trailing" list row.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final Widget content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: dense ? AppSizes.sm : AppSizes.md,
      ),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[leading!, const SizedBox(width: AppSizes.md)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: AppText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[const SizedBox(width: AppSizes.sm), trailing!],
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      label: subtitle == null ? title : '$title, $subtitle',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          child: content,
        ),
      ),
    );
  }
}

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 44,
    this.statusColor,
    this.icon,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final Color? statusColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final String initials = _initials(name);
    final Widget avatar = Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        shape: BoxShape.circle,
        border: Border.all(color: AppPalette.of(context).border),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, color: Colors.white, size: size * 0.5)
          : Text(
              initials,
              style: AppText.bodyStrong.copyWith(
                color: Colors.white,
                fontSize: size * 0.36,
              ),
            ),
    );

    if (statusColor == null) return avatar;

    return Stack(
      children: <Widget>[
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            height: size * 0.28,
            width: size * 0.28,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              border: Border.all(color: AppPalette.of(context).surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  static String _initials(String name) {
    final List<String> parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

/// Segmented pill tabs (Login screen: Email | Phone | Google).
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Semantics(
      label: 'Select option',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        ),
        child: Row(
          children: List<Widget>.generate(labels.length, (int index) {
            final bool selected = index == selectedIndex;
            return Expanded(
              child: InkWell(
                onTap: () => onChanged(index),
                borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minHeight: 36),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? palette.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                    boxShadow: selected
                        ? const <BoxShadow>[
                            BoxShadow(color: AppColors.shadow, blurRadius: 6),
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[index],
                    style: AppText.caption.copyWith(
                      color: selected ? palette.textPrimary : palette.textSecondary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

/// Selectable chip used for urgency and availability pickers.
class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.color,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final Color base = color ?? AppColors.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget - 8),
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.sm),
          decoration: BoxDecoration(
            color: selected ? base : palette.surface,
            borderRadius: BorderRadius.circular(AppSizes.radiusPill),
            border: Border.all(color: selected ? base : palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 15, color: selected ? Colors.white : base),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AppText.bodyStrong.copyWith(
                  color: selected ? Colors.white : palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------- status

class CapacityBar extends StatelessWidget {
  const CapacityBar({
    super.key,
    required this.label,
    required this.used,
    required this.total,
    required this.color,
  });

  final String label;
  final int used;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final double ratio = total == 0 ? 0 : (used / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: AppText.caption.copyWith(color: palette.textSecondary),
              ),
            ),
            Text(
              '$used / $total',
              style: AppText.caption.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 7,
            backgroundColor: palette.surfaceAlt,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: AppText.body.copyWith(color: palette.textSecondary),
            ),
          ),
          Text(
            value,
            style: AppText.bodyStrong.copyWith(
              color: valueColor ?? palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------- states

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppIconTile(icon: icon, color: palette.textSecondary, size: 56),
            const SizedBox(height: AppSizes.lg),
            Text(title, style: AppText.title, textAlign: TextAlign.center),
            if (message != null) ...<Widget>[
              const SizedBox(height: AppSizes.sm),
              Text(
                message!,
                style: AppText.body.copyWith(color: palette.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AppSizes.lg),
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
                compact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          if (label != null) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Text(
              label!,
              style: AppText.caption.copyWith(
                color: AppPalette.of(context).textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Something went wrong',
      message: message,
      actionLabel: onRetry == null ? null : context.tr('common.retry'),
      onAction: onRetry,
    );
  }
}

/// App-wide connectivity / sync banner (offline support).
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SyncState sync = ref.watch(syncControllerProvider);
    final AppPalette palette = AppPalette.of(context);

    final bool offline = !sync.isOnline;
    if (!offline && sync.pending == 0 && !sync.isSyncing) {
      return const SizedBox.shrink();
    }

    final (IconData icon, Color color, String message) = switch (true) {
      _ when offline && sync.pending > 0 => (
          Icons.cloud_off_outlined,
          AppColors.warning,
          '${context.tr('common.offline')} (${sync.pending})',
        ),
      _ when offline => (
          Icons.cloud_off_outlined,
          AppColors.warning,
          context.tr('common.offline'),
        ),
      _ when sync.isSyncing => (
          Icons.sync,
          AppColors.primary,
          context.tr('common.online'),
        ),
      _ => (
          Icons.cloud_upload_outlined,
          AppColors.primary,
          '${sync.pending} queued — syncing…',
        ),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: palette.tint(color),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.lg,
          vertical: AppSizes.sm,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(
                message,
                style: AppText.caption.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small legend dot used by map legends.
class LegendChip extends StatelessWidget {
  const LegendChip({
    super.key,
    required this.label,
    required this.color,
    this.selected = true,
    this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppSizes.radiusPill),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                height: 9,
                width: 9,
                decoration: BoxDecoration(
                  color: selected ? color : palette.border,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppText.caption.copyWith(
                  color: selected ? palette.textPrimary : palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Requested-by-design pin used on the map and legend.
class PinDot extends StatelessWidget {
  const PinDot({super.key, required this.type, this.size = 14});

  final MapPinType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(color: type.color, shape: BoxShape.circle),
    );
  }
}
