import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../l10n/l10n.dart';
import '../drag_handle.dart';

/// Opens [builder] as the app's standard bottom sheet.
///
/// The one place the sheet's frame is decided — shape, colour, safe area,
/// keyboard behaviour — so a sheet opened from any screen looks like every
/// other. Pair it with [SelahSheet] for the contents.
///
/// Always dismissible — by a drag, a tap outside or the back gesture — and a
/// dismissal returns null. There is deliberately no switch to turn that off:
/// isDismissible and enableDrag leave Android's back gesture closing the sheet
/// anyway, so a sheet that truly must be answered also needs a PopScope.
Future<T?> showSelahSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    // Lets the sheet grow past half the screen and ride up over the keyboard.
    isScrollControlled: true,
    // Defaults to false, which would draw the top edge under the notch.
    useSafeArea: true,
    backgroundColor: context.cardSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: builder,
  );
}

/// The contents of a standard sheet: handle, a header naming what the sheet is
/// for, an optional body, and the actions.
///
/// Taken from the log-prayer sheet, which replaced the app's first bare
/// AlertDialog and is the design every dialog is moving to: the header names
/// the thing being acted on, the main action is a filled button twice the width
/// of Cancel instead of one of two identical links, and every button is 48pt.
///
/// Leave [primaryLabel] null for a sheet that acts on tap — a list of choices —
/// and has no action row. Give [onPrimary] null to show the action disabled.
class SelahSheet extends StatelessWidget {
  final String title;

  /// One or two short lines under the title: what is being acted on.
  final String? subtitle;

  /// Shown in a tinted circle beside the title.
  final IconData? icon;

  /// The screen's colour. The icon is tinted with it and the main action is
  /// filled with it, darkened where a label would not read on it.
  final Color accent;

  /// Red instead of [accent] — for actions that delete or cannot be undone.
  final bool destructive;

  final Widget? body;

  /// When true the body scrolls inside a sheet capped at 85% of the screen,
  /// with the header and actions held in place — for long lists. Otherwise the
  /// whole sheet scrolls as one, which suits short content.
  final bool expandBody;

  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;

  final String? cancelLabel;

  /// Defaults to closing the sheet with no result.
  final VoidCallback? onCancel;

  const SelahSheet({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.accent = AppTheme.brandBlue,
    this.destructive = false,
    this.body,
    this.expandBody = false,
    this.primaryLabel,
    this.primaryIcon,
    this.onPrimary,
    this.cancelLabel,
    this.onCancel,
  });

  static const _padding = EdgeInsets.fromLTRB(20, 8, 20, 20);

  @override
  Widget build(BuildContext context) {
    final header = _Header(
      title: title,
      subtitle: subtitle,
      icon: icon,
      accent: accent,
      destructive: destructive,
    );
    final actions = primaryLabel == null
        ? null
        : _Actions(
            primaryLabel: primaryLabel!,
            primaryIcon: primaryIcon,
            onPrimary: onPrimary,
            cancelLabel: cancelLabel ?? l10n(context).actionCancel,
            onCancel: onCancel ?? () => Navigator.of(context).pop(),
            fill: AppTheme.filledFor(
                destructive ? AppTheme.errorSurface : accent),
          );

    final Widget content;
    if (expandBody) {
      content = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: _padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DragHandle(),
              const SizedBox(height: 14),
              header,
              if (body != null) ...[
                const SizedBox(height: 12),
                Flexible(child: body!),
              ],
              if (actions != null) ...[const SizedBox(height: 18), actions],
            ],
          ),
        ),
      );
    } else {
      content = SingleChildScrollView(
        padding: _padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),
            const SizedBox(height: 14),
            header,
            if (body != null) ...[const SizedBox(height: 18), body!],
            if (actions != null) ...[const SizedBox(height: 18), actions],
          ],
        ),
      );
    }

    return Padding(
      // Rides up over the keyboard, for the sheets that exist to type into.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(top: false, child: content),
    );
  }
}

class _Header extends StatelessWidget {
  static const _badgePadding = 10.0;
  static const _badge = AppTheme.iconMD + _badgePadding * 2;

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color accent;
  final bool destructive;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.destructive,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final tint = destructive ? AppTheme.error : accent;
    final glyph = destructive
        ? context.dangerText
        : AppTheme.accentOnTintFor(accent, brightness);
    const titleStyle = TextStyle(fontSize: 17, fontWeight: FontWeight.w700);

    // Where the badge sits beside the text, in three cases:
    //  - text shorter than the badge (a one-line title): centred on the badge;
    //  - text taller, first line shorter (a title wrapped at normal size, or a
    //    title and subtitle): tops aligned, the usual list-row arrangement;
    //  - first line itself taller than the badge (large text sizes): the badge
    //    drops to sit centred on that line.
    // Centring on the whole block instead put the badge beside the middle of a
    // title wrapped over three lines; aligning tops alone left a one-line
    // title riding high beside it.
    var iconDrop = 0.0;
    if (icon != null) {
      final painter = TextPainter(
        text: TextSpan(
            text: title,
            style: DefaultTextStyle.of(context).style.merge(titleStyle)),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      if (painter.height > _badge) iconDrop = (painter.height - _badge) / 2;
      painter.dispose();
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            margin: EdgeInsets.only(top: iconDrop),
            padding: const EdgeInsets.all(_badgePadding),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: AppTheme.alphaMedium),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: AppTheme.iconMD, color: glyph),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: ConstrainedBox(
            // Text shorter than the badge sits centred beside it.
            constraints: BoxConstraints(minHeight: icon == null ? 0 : _badge),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: titleStyle),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: context.mutedText),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  final String primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  final String cancelLabel;
  final VoidCallback onCancel;
  final ({Color fill, Color label}) fill;

  const _Actions({
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.cancelLabel,
    required this.onCancel,
    required this.fill,
  });

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      backgroundColor: fill.fill,
      foregroundColor: fill.label,
    );
    final label = Text(
      primaryLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    return _ActionsLayout(
      children: [
        TextButton(
          onPressed: onCancel,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 48),
            foregroundColor: context.mutedText,
          ),
          child: Text(cancelLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        primaryIcon == null
            ? FilledButton(onPressed: onPrimary, style: style, child: label)
            : FilledButton.icon(
                onPressed: onPrimary,
                style: style,
                icon: Icon(primaryIcon, size: 18),
                label: label,
              ),
      ],
    );
  }
}

/// Cancel and the main action side by side, the main action twice as wide —
/// or, when either label would not fit its share, stacked full width with the
/// main action on top.
///
/// At 320pt with text at 200% a side-by-side row cut "Cancel" to "Ca…" and
/// "Log prayer" to "Log pra…". Whether they fit is asked of the buttons
/// themselves (their intrinsic widths), not estimated from font sizes and
/// padding, so it stays right for any label, language or text size.
class _ActionsLayout extends MultiChildRenderObjectWidget {
  /// Cancel, then the main action.
  const _ActionsLayout({required super.children}) : assert(children.length == 2);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderActions();
}

class _ActionsParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderActions extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ActionsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ActionsParentData> {
  static const _rowGap = 12.0;
  static const _stackGap = 4.0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ActionsParentData) {
      child.parentData = _ActionsParentData();
    }
  }

  RenderBox get _cancel => firstChild!;
  RenderBox get _primary => lastChild!;

  double _share(double width) => (width - _rowGap) / 3;

  /// Whether each label fits its share. The slack absorbs rounding: the width
  /// [computeMaxIntrinsicWidth] reports as just enough comes back, after
  /// (3c + 12 − 12) / 3, a hair short of c for about one width in eleven, and
  /// without it the buttons stacked at the very width meant to hold them side
  /// by side.
  bool _fitsSideBySide(double width) {
    const slack = 0.01;
    return _cancel.getMaxIntrinsicWidth(double.infinity) <=
            _share(width) + slack &&
        _primary.getMaxIntrinsicWidth(double.infinity) <=
            _share(width) * 2 + slack;
  }

  /// The one sizing rule, shared by real layout and by measuring:
  /// [layoutChild] either lays a child out or only asks what size it would be.
  Size _size(BoxConstraints constraints, ChildLayouter layoutChild) {
    // Unbounded only when measured with no width in mind: take the width at
    // which the buttons just sit side by side.
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : constraints.constrainWidth(computeMaxIntrinsicWidth(double.infinity));
    if (_fitsSideBySide(width)) {
      final share = _share(width);
      final cancel =
          layoutChild(_cancel, BoxConstraints.tightFor(width: share));
      final primary =
          layoutChild(_primary, BoxConstraints.tightFor(width: share * 2));
      return constraints.constrain(Size(
          width, cancel.height > primary.height ? cancel.height : primary.height));
    }
    final full = BoxConstraints.tightFor(width: width);
    final primary = layoutChild(_primary, full);
    final cancel = layoutChild(_cancel, full);
    return constraints.constrain(
        Size(width, primary.height + _stackGap + cancel.height));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _size(constraints, ChildLayoutHelper.dryLayoutChild);

  @override
  void performLayout() {
    size = _size(constraints, ChildLayoutHelper.layoutChild);
    final cancelData = _cancel.parentData! as _ActionsParentData;
    final primaryData = _primary.parentData! as _ActionsParentData;
    if (_fitsSideBySide(size.width)) {
      cancelData.offset = Offset(0, (size.height - _cancel.size.height) / 2);
      primaryData.offset = Offset(_share(size.width) + _rowGap,
          (size.height - _primary.size.height) / 2);
    } else {
      primaryData.offset = Offset.zero;
      cancelData.offset = Offset(0, _primary.size.height + _stackGap);
    }
  }

  /// Narrowest it can be: stacked, as wide as the wider button.
  @override
  double computeMinIntrinsicWidth(double height) {
    final cancel = _cancel.getMinIntrinsicWidth(height);
    final primary = _primary.getMinIntrinsicWidth(height);
    return cancel > primary ? cancel : primary;
  }

  /// Widest it wants to be: just wide enough to sit side by side.
  @override
  double computeMaxIntrinsicWidth(double height) {
    final forCancel = _cancel.getMaxIntrinsicWidth(height) * 3;
    final forPrimary = _primary.getMaxIntrinsicWidth(height) * 1.5;
    return (forCancel > forPrimary ? forCancel : forPrimary) + _rowGap;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _size(BoxConstraints(maxWidth: width), ChildLayoutHelper.dryLayoutChild)
          .height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// The text field style for sheets: filled and bordered, so it reads as a
/// place to write rather than a line under a label.
InputDecoration selahFieldDecoration(
  BuildContext context, {
  String? hint,
  Color accent = AppTheme.brandBlue,
  String? errorText,
}) {
  final border = OutlineInputBorder(
    borderRadius: AppTheme.borderRadiusLG,
    borderSide: BorderSide(color: context.hairline),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: context.hintText),
    errorText: errorText,
    // The default is one line, which at large text sizes cut the reason a
    // name was refused down to its first few words.
    errorMaxLines: 3,
    filled: true,
    fillColor: context.subtleFill,
    contentPadding: const EdgeInsets.all(14),
    border: border,
    enabledBorder: border,
    // accentInk, not the raw accent: a focus ring is a graphic and needs 3:1
    // against the field, which some raw accents miss.
    focusedBorder: OutlineInputBorder(
      borderRadius: AppTheme.borderRadiusLG,
      borderSide: BorderSide(color: context.accentInk(accent), width: 1.5),
    ),
  );
}
