import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';

/// Vant 风格单行单元格 (Cell)
class VantCell extends StatelessWidget {
  final String title;
  final String? label;
  final String? value;
  final Widget? customValue;
  final IconData? icon;
  final bool isLink;
  final VoidCallback? onTap;
  final Widget? leading;
  final bool showDivider;

  const VantCell({
    super.key,
    required this.title,
    this.label,
    this.value,
    this.customValue,
    this.icon,
    this.isLink = false,
    this.onTap,
    this.leading,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: SnapColors.of(context).border, width: 0.6))
              : null,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: SnapColors.of(context).primary),
              const SizedBox(width: 12),
            ] else if (leading != null) ...[
              leading!,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: SnapColors.of(context).textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (label != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      label!,
                      style: TextStyle(
                        color: SnapColors.of(context).textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (customValue != null)
              customValue!
            else if (value != null)
              Text(
                value!,
                style: TextStyle(
                  color: SnapColors.of(context).textSecondary,
                  fontSize: 13,
                ),
              ),
            if (isLink) ...[
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_ios, size: 12, color: SnapColors.of(context).textTertiary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Vant 风格单元格卡片容器 (CellGroup)
class VantCellGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const VantCellGroup({
    super.key,
    this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
            child: Text(
              title!,
              style: TextStyle(
                color: SnapColors.of(context).textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: SnapColors.of(context).card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SnapColors.of(context).border, width: 0.8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}

/// Vant 风格按钮 (Button)
enum VantButtonType { primary, success, danger, warning, normal }

class VantButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VantButtonType type;
  final bool isRound;
  final bool isBlock;
  final bool isLoading;
  final VoidCallback? onTap;

  const VantButton({
    super.key,
    required this.text,
    this.icon,
    this.type = VantButtonType.primary,
    this.isRound = false,
    this.isBlock = false,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (type) {
      case VantButtonType.primary:
        bg = SnapColors.of(context).primary;
        fg = SnapColors.of(context).textInverse;
        break;
      case VantButtonType.success:
        bg = SnapColors.of(context).success;
        fg = Colors.white;
        break;
      case VantButtonType.danger:
        bg = SnapColors.of(context).danger;
        fg = Colors.white;
        break;
      case VantButtonType.warning:
        bg = SnapColors.of(context).warning;
        fg = Colors.white;
        break;
      case VantButtonType.normal:
        bg = SnapColors.of(context).cardElevated;
        fg = SnapColors.of(context).textPrimary;
        break;
    }

    Widget content = Row(
      mainAxisSize: isBlock ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(fg)),
          ),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
        ],
        Text(
          text,
          style: TextStyle(
            color: fg,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(isRound ? 24 : 8),
      child: Container(
        width: isBlock ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(isRound ? 24 : 8),
        ),
        child: content,
      ),
    );
  }
}

/// Vant 风格状态标签 (Tag)
class VantTag extends StatelessWidget {
  final String text;
  final Color? color;
  final bool isPlain;

  const VantTag({
    super.key,
    required this.text,
    this.color,
    this.isPlain = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = color ?? SnapColors.of(context).primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPlain ? Colors.transparent : themeColor.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: themeColor, width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: themeColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
