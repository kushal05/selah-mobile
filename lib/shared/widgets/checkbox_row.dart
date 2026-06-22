import 'package:flutter/material.dart';

/// Displays a checkbox with a label
class CheckboxRow extends StatelessWidget {
  final String label;
  final bool checked;
  final ValueChanged<bool?>? onChanged;

  const CheckboxRow({
    super.key,
    required this.label,
    this.checked = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Checkbox(
            value: checked,
            onChanged: onChanged,
          ),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
