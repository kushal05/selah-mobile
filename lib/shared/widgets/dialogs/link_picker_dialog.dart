import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// A generic search + multi-select dialog for picking items to link.
///
/// Used for linking Promises ↔ Prayers bidirectionally.
/// [T] is the item type, [items] are the available choices,
/// [alreadyLinkedIds] are IDs to exclude, [getId] and [getLabel]
/// extract the id/display text from each item.
class LinkPickerDialog<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final Set<String> alreadyLinkedIds;
  final String Function(T) getId;
  final String Function(T) getLabel;
  final String? Function(T)? getSubtitle;

  const LinkPickerDialog({
    super.key,
    required this.title,
    required this.items,
    required this.alreadyLinkedIds,
    required this.getId,
    required this.getLabel,
    this.getSubtitle,
  });

  @override
  State<LinkPickerDialog<T>> createState() => _LinkPickerDialogState<T>();
}

class _LinkPickerDialogState<T> extends State<LinkPickerDialog<T>> {
  final _searchController = TextEditingController();
  final _selectedIds = <String>{};
  String _query = '';

  List<T> get _filteredItems {
    final available = widget.items
        .where((item) => !widget.alreadyLinkedIds.contains(widget.getId(item)))
        .toList();

    if (_query.isEmpty) return available;

    final lower = _query.toLowerCase();
    return available.where((item) {
      final label = widget.getLabel(item).toLowerCase();
      final subtitle = widget.getSubtitle?.call(item)?.toLowerCase() ?? '';
      return label.contains(lower) || subtitle.contains(lower);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search, size: AppTheme.iconBase),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: AppTheme.borderRadiusMD,
                ),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: AppTheme.spacing12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        _query.isEmpty
                            ? 'No items available'
                            : 'No results for "$_query"',
                        style: TextStyle(color: AppTheme.unselectedColor),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final id = widget.getId(item);
                        final isSelected = _selectedIds.contains(id);
                        final subtitle = widget.getSubtitle?.call(item);

                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedIds.add(id);
                              } else {
                                _selectedIds.remove(id);
                              }
                            });
                          },
                          title: Text(
                            widget.getLabel(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: subtitle != null && subtitle.isNotEmpty
                              ? Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.caption.copyWith(
                                    color: AppTheme.gray600,
                                  ),
                                )
                              : null,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () => Navigator.pop(context, _selectedIds.toList()),
          child: Text('Link (${_selectedIds.length})'),
        ),
      ],
    );
  }
}
