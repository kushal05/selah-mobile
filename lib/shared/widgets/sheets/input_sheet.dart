import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'selah_sheet.dart';

/// Asks for one piece of text: a name, a title, a short note.
///
/// Returns the text, trimmed, or null if the sheet was dismissed.
///
/// Replaces AlertDialogs with an undecorated TextField. The field takes focus
/// as the sheet opens and the sheet rides up over the keyboard, so typing
/// starts at once. The main action stays disabled until the text is valid —
/// non-empty unless [allowEmpty], and passing [validator] — rather than
/// accepting a blank name and failing later. A validation message is held back
/// only while the field is empty and untouched — not a reproach before anything
/// is typed — but shown at once for a starting value that fails, so Save is
/// never greyed out without a reason.
Future<String?> showInputSheet(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? subtitle,
  IconData? icon,
  IconData? confirmIcon,
  Color accent = AppTheme.brandBlue,
  String initialValue = '',
  String? hint,
  int? maxLength,
  int minLines = 1,
  int maxLines = 1,
  bool allowEmpty = false,
  TextCapitalization textCapitalization = TextCapitalization.sentences,
  TextInputType? keyboardType,
  String? Function(String value)? validator,
}) {
  return showSelahSheet<String>(
    context,
    builder: (_) => _InputSheet(
      title: title,
      subtitle: subtitle,
      icon: icon,
      accent: accent,
      confirmLabel: confirmLabel,
      confirmIcon: confirmIcon,
      initialValue: initialValue,
      hint: hint,
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
      allowEmpty: allowEmpty,
      textCapitalization: textCapitalization,
      keyboardType: keyboardType,
      validator: validator,
    ),
  );
}

class _InputSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color accent;
  final String confirmLabel;
  final IconData? confirmIcon;
  final String initialValue;
  final String? hint;
  final int? maxLength;
  final int minLines;
  final int maxLines;
  final bool allowEmpty;
  final TextCapitalization textCapitalization;
  final TextInputType? keyboardType;
  final String? Function(String value)? validator;

  const _InputSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.confirmLabel,
    required this.confirmIcon,
    required this.initialValue,
    required this.hint,
    required this.maxLength,
    required this.minLines,
    required this.maxLines,
    required this.allowEmpty,
    required this.textCapitalization,
    required this.keyboardType,
    required this.validator,
  });

  @override
  State<_InputSheet> createState() => _InputSheetState();
}

class _InputSheetState extends State<_InputSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  )..selection = TextSelection(
      // Selected, so renaming means typing over the old name.
      baseOffset: 0,
      extentOffset: widget.initialValue.length,
    );

  /// Whether the person has typed anything yet; until then a validation
  /// message on an empty field would be scolding one they have not touched.
  bool _edited = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _value => _controller.text.trim();

  /// Why the current text cannot be accepted, or null if it can.
  String? get _problem => widget.validator?.call(_value);

  bool get _valid =>
      (widget.allowEmpty || _value.isNotEmpty) && _problem == null;

  void _submit() {
    if (_valid) Navigator.of(context).pop(_value);
  }

  @override
  Widget build(BuildContext context) {
    final singleLine = widget.maxLines == 1;
    return SelahSheet(
      title: widget.title,
      subtitle: widget.subtitle,
      icon: widget.icon,
      accent: widget.accent,
      body: TextField(
        controller: _controller,
        autofocus: true,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        textCapitalization: widget.textCapitalization,
        keyboardType: widget.keyboardType,
        textInputAction:
            singleLine ? TextInputAction.done : TextInputAction.newline,
        onSubmitted: singleLine ? (_) => _submit() : null,
        onChanged: (_) => setState(() => _edited = true),
        style: const TextStyle(fontSize: 16, height: 1.4),
        decoration: selahFieldDecoration(
          context,
          hint: widget.hint,
          accent: widget.accent,
          errorText: _edited || _value.isNotEmpty ? _problem : null,
        ),
      ),
      primaryLabel: widget.confirmLabel,
      primaryIcon: widget.confirmIcon,
      onPrimary: _valid ? _submit : null,
    );
  }
}
