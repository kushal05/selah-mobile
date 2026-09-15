import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/enums/prayer_enums.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/models/prayer_collaborator_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';

/// Screen for managing collaborators on a shared prayer
class PrayerCollaboratorsScreen extends ConsumerStatefulWidget {
  final String prayerId;

  const PrayerCollaboratorsScreen({
    super.key,
    required this.prayerId,
  });

  @override
  ConsumerState<PrayerCollaboratorsScreen> createState() =>
      _PrayerCollaboratorsScreenState();
}

class _PrayerCollaboratorsScreenState
    extends ConsumerState<PrayerCollaboratorsScreen> {
  final _usernameController = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collaboratorsAsync =
        ref.watch(prayerCollaboratorsProvider(widget.prayerId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n(context).collaborators),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Add collaborator section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                bottom: BorderSide(color: context.hairline),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      hintText: l10n(context).enterUsernameToAdd,
                      prefixIcon: const Icon(Icons.person_add_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isAdding ? null : _addCollaborator,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.brandBlue,
                    foregroundColor: AppTheme.onAccent(AppTheme.brandBlue),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isAdding
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l10n(context).add),
                ),
              ],
            ),
          ),

          // Collaborators list
          Expanded(
            child: collaboratorsAsync.when(
              loading: () =>
                  const ListTileSkeletonList(count: 4),
              error: (error, stack) =>
                  Center(child: Text(UserFacingError.forLoad(error))),
              data: (collaborators) {
                if (collaborators.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: collaborators.length,
                  itemBuilder: (context, index) {
                    final collab = collaborators[index];
                    return _CollaboratorCard(
                      collaborator: collab,
                      onChangeRole: (role) =>
                          _changeRole(collab.id, role),
                      onRemove: () => _removeCollaborator(collab),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_add_outlined,
                size: 64, color: context.hintText),
            const SizedBox(height: 16),
            Text(
              l10n(context).noCollaboratorsYet,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n(context).addFriendsByUsernameToCollaborateOnThisPraye,
              style: TextStyle(
                fontSize: 16,
                color: context.mutedText,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addCollaborator() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return;

    setState(() => _isAdding = true);

    try {
      final api = ref.read(sharedPrayerApiServiceProvider);
      await api.addCollaborator(
        prayerId: widget.prayerId,
        username: username,
      );

      ref.invalidate(prayerCollaboratorsProvider(widget.prayerId));
      _usernameController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$username added as collaborator'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'add collaborator')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isAdding = false);
    }
  }

  Future<void> _changeRole(String id, CollaboratorRole role) async {
    try {
      final api = ref.read(sharedPrayerApiServiceProvider);
      await api.updateCollaboratorRole(
        prayerId: widget.prayerId,
        collaboratorId: id,
        role: role.name,
      );
      ref.invalidate(prayerCollaboratorsProvider(widget.prayerId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'update role')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _removeCollaborator(
      PrayerCollaboratorModel collaborator) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n(context).removeCollaborator),
        content: Text(
          'Remove ${collaborator.collaboratorUsername} from this prayer?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n(context).actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: context.dangerText),
            child: Text(l10n(context).remove),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final api = ref.read(sharedPrayerApiServiceProvider);
      await api.removeCollaborator(
        prayerId: widget.prayerId,
        collaboratorId: collaborator.id,
      );
      ref.invalidate(prayerCollaboratorsProvider(widget.prayerId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${collaborator.collaboratorUsername} removed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'remove')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _CollaboratorCard extends StatelessWidget {
  final PrayerCollaboratorModel collaborator;
  final Function(CollaboratorRole) onChangeRole;
  final VoidCallback onRemove;

  const _CollaboratorCard({
    required this.collaborator,
    required this.onChangeRole,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final initial = collaborator.collaboratorUsername.isNotEmpty
        ? collaborator.collaboratorUsername[0].toUpperCase()
        : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor:
                AppTheme.brandBlue.withValues(alpha: 0.1),
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.brandBlue,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${collaborator.collaboratorUsername}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                _RoleBadge(role: collaborator.role),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'remove') {
                onRemove();
              } else {
                final role = CollaboratorRole.values.firstWhere(
                  (r) => r.name == value,
                  orElse: () => CollaboratorRole.viewer,
                );
                onChangeRole(role);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'collaborator',
                child: Text(l10n(context).setAsCollaborator),
              ),
              PopupMenuItem(
                value: 'viewer',
                child: Text(l10n(context).setAsViewer),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'remove',
                child: Text(
                  l10n(context).remove,
                  style: TextStyle(color: context.dangerText),
                ),
              ),
            ],
            child: Icon(Icons.more_vert, color: context.hintText),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final CollaboratorRole role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (role) {
      case CollaboratorRole.owner:
        color = AppTheme.brandBlue;
      case CollaboratorRole.collaborator:
        color = AppTheme.teal;
      case CollaboratorRole.viewer:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        role.displayName,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
