import 'package:flutter/material.dart';

/// Ignores the keyboard inset while no text field has focus.
///
/// Android can hand the app a keyboard inset that outlives the keyboard: open
/// the keyboard, leave the app, come back, and the window still reports it.
/// Every Scaffold then makes room for a keyboard that is not there, and the
/// screen shows as a half-height page over a blank band.
///
/// A real keyboard always belongs to a focused text field, so when none has
/// focus the inset is wrong by definition and is dropped. With a field focused
/// (including one in a sheet or dialog) the inset passes through untouched.
class KeyboardInsetGuard extends StatefulWidget {
  final Widget child;

  const KeyboardInsetGuard({super.key, required this.child});

  @override
  State<KeyboardInsetGuard> createState() => _KeyboardInsetGuardState();
}

class _KeyboardInsetGuardState extends State<KeyboardInsetGuard> {
  bool _fieldFocused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
    _fieldFocused = _hasFieldFocus();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  bool _hasFieldFocus() {
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.findAncestorStateOfType<EditableTextState>() != null;
  }

  void _onFocusChanged() {
    final focused = _hasFieldFocus();
    if (focused != _fieldFocused && mounted) {
      setState(() => _fieldFocused = focused);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (_fieldFocused || media.viewInsets.bottom == 0) return widget.child;
    return MediaQuery(
      data: media.copyWith(
        viewInsets: media.viewInsets.copyWith(bottom: 0),
      ),
      child: widget.child,
    );
  }
}
