import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/sync/models/entity_access_model.dart';
import '../../../core/sync/models/friendship_model.dart';
import '../../../core/sync/providers/sync_providers.dart';
import '../../../core/sync/services/public_share_api_service.dart';

/// Universal share dialog for any content entity.
///
/// Supported modes:
///   - Private:         owner-only
///   - Specific People: per-user grants (AccessType.user) with View/Edit role
///   - Friends:         broadcast to all friends (AccessType.friend)
///   - Group:           grant to a selected group (AccessType.group)
///   - Public:          broadcast visibility (AccessType.public)
///
/// In addition, a Public Link section (always visible, independent of
/// mode) manages tokenised share URLs via `/v1/shares/.../public-tokens`.
///
/// Usage:
/// ```dart
/// ShareSheet.show(context, ref,
///   entityType: 'note',
///   entityId: noteId,
///   userId: currentUserId,
/// );
/// ```
class ShareSheet extends ConsumerStatefulWidget {
  final String entityType;
  final String entityId;
  final String userId;

  const ShareSheet({
    super.key,
    required this.entityType,
    required this.entityId,
    required this.userId,
  });

  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required String entityType,
    required String entityId,
    required String userId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ShareSheet(
        entityType: entityType,
        entityId: entityId,
        userId: userId,
      ),
    );
  }

  @override
  ConsumerState<ShareSheet> createState() => _ShareSheetState();
}

enum _ShareMode { private, specificPeople, friends, group, public }

class _ShareSheetState extends ConsumerState<ShareSheet> {
  static const _uuid = Uuid();

  _ShareMode _selectedMode = _ShareMode.private;
  String? _selectedGroupId;
  final Set<String> _selectedFriendUserIds = <String>{};
  AccessRole _selectedRole = AccessRole.viewer;

  bool _saving = false;
  bool _loading = true;
  bool _userHasInteracted = false;

  // Public link state — loaded independently of the mode picker.
  List<PublicShareToken> _publicTokens = const [];
  bool _loadingPublicTokens = true;
  bool _creatingPublicLink = false;
  String? _justCreatedToken;

  @override
  void initState() {
    super.initState();
    _loadCurrentAccess();
    if (widget.entityType == 'note') {
      _loadPublicTokens();
    } else {
      _loadingPublicTokens = false;
    }
  }

  // --------------------------------------------------------------------
  // Load current access state
  // --------------------------------------------------------------------

  Future<void> _loadCurrentAccess() async {
    final repo = ref.read(entityAccessRepositoryProvider);
    final records = await repo.getAccessForEntity(
      widget.entityType,
      widget.entityId,
    );

    if (!mounted || _userHasInteracted) return;

    // Tier-2 user shares take precedence when any exist — they're the
    // most specific grant, so default the picker into that mode.
    final userShares =
        records.where((r) => r.accessType == AccessType.user).toList();
    if (userShares.isNotEmpty) {
      setState(() {
        _selectedMode = _ShareMode.specificPeople;
        _selectedFriendUserIds
          ..clear()
          ..addAll(userShares.map((r) => r.targetId).whereType<String>());
        _selectedRole = userShares.first.role.canEdit
            ? AccessRole.editor
            : AccessRole.viewer;
        _loading = false;
      });
      return;
    }

    for (final record in records) {
      if (record.accessType == AccessType.public_) {
        setState(() {
          _selectedMode = _ShareMode.public;
          _loading = false;
        });
        return;
      }
      if (record.accessType == AccessType.group) {
        setState(() {
          _selectedMode = _ShareMode.group;
          _selectedGroupId = record.targetId;
          _selectedRole = record.role;
          _loading = false;
        });
        return;
      }
      if (record.accessType == AccessType.friend) {
        setState(() {
          _selectedMode = _ShareMode.friends;
          _selectedRole = record.role;
          _loading = false;
        });
        return;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPublicTokens() async {
    try {
      final api = ref.read(publicShareApiServiceProvider);
      final tokens = await api.listNoteTokens(widget.entityId);
      if (!mounted) return;
      setState(() {
        _publicTokens = tokens;
        _loadingPublicTokens = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPublicTokens = false);
    }
  }

  // --------------------------------------------------------------------
  // Save — applies mode picker choices via entity_access repo
  // --------------------------------------------------------------------

  Future<void> _save() async {
    if (_selectedMode == _ShareMode.group && _selectedGroupId == null) {
      _snack('Please select a group');
      return;
    }
    if (_selectedMode == _ShareMode.specificPeople &&
        _selectedFriendUserIds.isEmpty) {
      _snack('Pick at least one person');
      return;
    }

    setState(() => _saving = true);

    try {
      final repo = ref.read(entityAccessRepositoryProvider);

      // Blow away all prior non-owner access, then re-create per the
      // current selection. Keeps the sheet's single-mode mental model
      // and avoids surgical diffs.
      await repo.deleteAllNonOwnerAccess(
        widget.entityType,
        widget.entityId,
      );

      switch (_selectedMode) {
        case _ShareMode.private:
          break;
        case _ShareMode.specificPeople:
          for (final friendUserId in _selectedFriendUserIds) {
            await repo.createAccess(EntityAccessModel.create(
              id: _uuid.v4(),
              entityType: widget.entityType,
              entityId: widget.entityId,
              accessType: AccessType.user,
              targetId: friendUserId,
              role: _selectedRole,
              userId: widget.userId,
            ));
          }
          break;
        case _ShareMode.friends:
          await repo.createAccess(EntityAccessModel.create(
            id: _uuid.v4(),
            entityType: widget.entityType,
            entityId: widget.entityId,
            accessType: AccessType.friend,
            role: _selectedRole,
            userId: widget.userId,
          ));
          break;
        case _ShareMode.group:
          await repo.createAccess(EntityAccessModel.create(
            id: _uuid.v4(),
            entityType: widget.entityType,
            entityId: widget.entityId,
            accessType: AccessType.group,
            targetId: _selectedGroupId,
            role: _selectedRole,
            userId: widget.userId,
          ));
          break;
        case _ShareMode.public:
          await repo.createAccess(EntityAccessModel.create(
            id: _uuid.v4(),
            entityType: widget.entityType,
            entityId: widget.entityId,
            accessType: AccessType.public_,
            role: AccessRole.viewer,
            userId: widget.userId,
          ));
          break;
      }

      ref.invalidate(entityAccessStreamProvider(
        (entityType: widget.entityType, entityId: widget.entityId),
      ));

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack('Failed to update sharing: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // --------------------------------------------------------------------
  // Public link actions
  // --------------------------------------------------------------------

  Future<void> _createPublicLink() async {
    setState(() => _creatingPublicLink = true);
    try {
      final api = ref.read(publicShareApiServiceProvider);
      final created = await api.createNoteToken(widget.entityId);
      if (!mounted) return;
      setState(() {
        _justCreatedToken = created.token;
        _publicTokens = [created, ..._publicTokens];
      });
      if (created.token != null) {
        await Clipboard.setData(ClipboardData(text: _linkFor(created.token!)));
        _snack('Public link copied to clipboard');
      }
    } catch (e) {
      _snack('Failed to create link: $e');
    } finally {
      if (mounted) setState(() => _creatingPublicLink = false);
    }
  }

  Future<void> _revokePublicToken(String tokenId) async {
    try {
      final api = ref.read(publicShareApiServiceProvider);
      await api.revokeToken(tokenId);
      if (!mounted) return;
      setState(() {
        _publicTokens = _publicTokens.where((t) => t.id != tokenId).toList();
        _justCreatedToken = null;
      });
      _snack('Link revoked');
    } catch (e) {
      _snack('Failed to revoke: $e');
    }
  }

  String _linkFor(String token) {
    final cfg = ref.read(syncConfigProvider);
    return '${cfg.apiBaseUrl}/v1/public/notes/$token';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Share', style: theme.textTheme.titleLarge),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _buildModePicker(theme),
              const SizedBox(height: 12),
              if (_modeSupportsRole(_selectedMode)) _buildRoleToggle(theme),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
            if (widget.entityType == 'note') ...[
              const SizedBox(height: 24),
              Divider(color: theme.dividerColor),
              const SizedBox(height: 12),
              _buildPublicLinkSection(theme),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------
  // Mode picker + dependent pickers
  // --------------------------------------------------------------------

  Widget _buildModePicker(ThemeData theme) {
    final friendsAsync = ref.watch(friendsListProvider);
    final groupsAsync = ref.watch(groupsListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PrivacyOption(
          icon: Icons.lock_outline,
          title: 'Private',
          subtitle: 'Only you can see this',
          selected: _selectedMode == _ShareMode.private,
          onTap: () => _pickMode(_ShareMode.private),
        ),
        _PrivacyOption(
          icon: Icons.person_add_alt_1_outlined,
          title: 'Specific people',
          subtitle: 'Share with chosen friends',
          selected: _selectedMode == _ShareMode.specificPeople,
          onTap: () => _pickMode(_ShareMode.specificPeople),
        ),
        if (_selectedMode == _ShareMode.specificPeople)
          Padding(
            padding: const EdgeInsets.only(left: 56, top: 4, bottom: 4),
            child: friendsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
              error: (_, _) => const Text('Failed to load friends'),
              data: _buildFriendChips,
            ),
          ),
        _PrivacyOption(
          icon: Icons.people_outline,
          title: 'All friends',
          subtitle: 'Visible to all your friends',
          selected: _selectedMode == _ShareMode.friends,
          onTap: () => _pickMode(_ShareMode.friends),
        ),
        _PrivacyOption(
          icon: Icons.group_outlined,
          title: 'Group',
          subtitle: 'Share with a group',
          selected: _selectedMode == _ShareMode.group,
          onTap: () => _pickMode(_ShareMode.group),
        ),
        if (_selectedMode == _ShareMode.group)
          Padding(
            padding: const EdgeInsets.only(left: 56, top: 8, bottom: 8),
            child: groupsAsync.when(
              loading: () => const CircularProgressIndicator(),
              error: (_, _) => const Text('Failed to load groups'),
              data: (groups) {
                if (groups.isEmpty) {
                  return const Text('No groups available. Create one first.');
                }
                return DropdownButtonFormField<String>(
                  initialValue: _selectedGroupId,
                  decoration: const InputDecoration(
                    labelText: 'Select group',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: groups
                      .map((g) => DropdownMenuItem(
                            value: g.id,
                            child: Text(g.name),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedGroupId = value),
                );
              },
            ),
          ),
        _PrivacyOption(
          icon: Icons.public_outlined,
          title: 'Public',
          subtitle: 'Anyone in the app can see this',
          selected: _selectedMode == _ShareMode.public,
          onTap: () => _pickMode(_ShareMode.public),
        ),
      ],
    );
  }

  Widget _buildFriendChips(List<FriendshipModel> friends) {
    if (friends.isEmpty) {
      return const Text('No friends yet. Add some to share with them.');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: friends.map((f) {
        final selected = _selectedFriendUserIds.contains(f.friendUserId);
        final label = f.friendDisplayName.isNotEmpty
            ? f.friendDisplayName
            : f.friendUsername;
        return FilterChip(
          label: Text(label),
          selected: selected,
          onSelected: (v) => setState(() {
            _userHasInteracted = true;
            if (v) {
              _selectedFriendUserIds.add(f.friendUserId);
            } else {
              _selectedFriendUserIds.remove(f.friendUserId);
            }
          }),
        );
      }).toList(),
    );
  }

  Widget _buildRoleToggle(ThemeData theme) {
    return Row(
      children: [
        Text('Permission', style: theme.textTheme.labelLarge),
        const Spacer(),
        SegmentedButton<AccessRole>(
          segments: const [
            ButtonSegment(
              value: AccessRole.viewer,
              label: Text('View'),
              icon: Icon(Icons.visibility_outlined),
            ),
            ButtonSegment(
              value: AccessRole.editor,
              label: Text('Edit'),
              icon: Icon(Icons.edit_outlined),
            ),
          ],
          selected: {_selectedRole},
          onSelectionChanged: (s) => setState(() {
            _userHasInteracted = true;
            _selectedRole = s.first;
          }),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------
  // Public link section
  // --------------------------------------------------------------------

  Widget _buildPublicLinkSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.link),
            const SizedBox(width: 8),
            Text('Public link', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Anyone with the link can view — read-only, no account needed.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (_loadingPublicTokens)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          )
        else ...[
          if (_justCreatedToken != null) _buildJustCreatedBanner(theme),
          ..._publicTokens
              .map((t) => _buildTokenRow(t, theme))
              ,
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add_link),
              label: Text(
                _publicTokens.isEmpty
                    ? 'Create public link'
                    : 'Create another link',
              ),
              onPressed: _creatingPublicLink ? null : _createPublicLink,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildJustCreatedBanner(ThemeData theme) {
    final token = _justCreatedToken!;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Link ready — save it now, we won\'t show it again',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            _linkFor(token),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenRow(PublicShareToken t, ThemeData theme) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.link),
      title: Text('Link created ${_relativeTime(t.createdAt)}'),
      subtitle: const Text('View-only • cannot be re-copied'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Revoke',
        onPressed: () => _revokePublicToken(t.id),
      ),
    );
  }

  // --------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------

  void _pickMode(_ShareMode mode) {
    setState(() {
      _userHasInteracted = true;
      _selectedMode = mode;
      if (mode != _ShareMode.specificPeople) {
        _selectedFriendUserIds.clear();
      }
    });
  }

  bool _modeSupportsRole(_ShareMode mode) {
    switch (mode) {
      case _ShareMode.specificPeople:
      case _ShareMode.friends:
      case _ShareMode.group:
        return true;
      case _ShareMode.private:
      case _ShareMode.public:
        return false;
    }
  }

  String _relativeTime(int createdAtMs) {
    final diff = DateTime.now().millisecondsSinceEpoch - createdAtMs;
    if (diff < 60 * 1000) return 'just now';
    if (diff < 60 * 60 * 1000) return '${diff ~/ 60000}m ago';
    if (diff < 24 * 60 * 60 * 1000) return '${diff ~/ 3600000}h ago';
    return '${diff ~/ 86400000}d ago';
  }
}

class _PrivacyOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _PrivacyOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: selected ? theme.colorScheme.primary : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : const Icon(Icons.circle_outlined, color: Colors.grey),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
