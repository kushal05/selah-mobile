import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// Profile settings screen for managing username, display name, bio, and privacy
class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() =>
      _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState
    extends ConsumerState<ProfileSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _friendRequestsEnabled = true;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _hasLoaded = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Load profile data on first build
    if (!_hasLoaded) {
      _loadProfile();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Privacy'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: AppTheme.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const FormSkeleton()
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Profile avatar
                  Center(
                    child: CircleAvatar(
                      radius: 48,
                      backgroundColor:
                          AppTheme.teal.withValues(alpha: 0.1),
                      child: Text(
                        _getInitials(),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.teal,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Username field (read-only, edit via dialog)
                  _buildSectionHeader('USERNAME'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      title: Text(
                        _usernameController.text.isNotEmpty
                            ? '@${_usernameController.text}'
                            : '@username',
                        style: TextStyle(
                          color: _usernameController.text.isNotEmpty
                              ? null
                              : Colors.grey.shade500,
                        ),
                      ),
                      trailing: Icon(
                        Icons.edit_outlined,
                        color: Colors.grey.shade500,
                        size: 20,
                      ),
                      onTap: () => _showUsernameEditDialog(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your unique username for friends to find you',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Display name field
                  _buildSectionHeader('DISPLAY NAME'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _displayNameController,
                    decoration: InputDecoration(
                      hintText: 'Display Name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).cardColor,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Bio field
                  _buildSectionHeader('BIO'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _bioController,
                    maxLines: 3,
                    maxLength: 150,
                    decoration: InputDecoration(
                      hintText: 'Tell others about yourself...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).cardColor,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Privacy section
                  _buildSectionHeader('PRIVACY'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SwitchListTile(
                      title: const Text('Allow Friend Requests'),
                      subtitle: const Text(
                        'When off, no one can send you friend requests',
                      ),
                      value: _friendRequestsEnabled,
                      onChanged: (value) {
                        setState(() {
                          _friendRequestsEnabled = value;
                        });
                      },
                      activeTrackColor: AppTheme.teal.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Blocked users
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: Icon(Icons.block, color: Colors.red.shade400),
                      title: const Text('Blocked Users'),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: Colors.grey.shade400,
                      ),
                      onTap: () => _showBlockedUsers(context),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  String _getInitials() {
    final display = _displayNameController.text.trim();
    final username = _usernameController.text.trim();
    final name = display.isNotEmpty ? display : username;
    if (name.isEmpty) return '?';

    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade600,
        letterSpacing: 0.5,
      ),
    );
  }

  void _showUsernameEditDialog(BuildContext context) {
    final controller = TextEditingController(text: _usernameController.text);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Username'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              prefixText: '@',
              hintText: 'username',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Username is required';
              }
              if (value.trim().length < 3) {
                return 'Username must be at least 3 characters';
              }
              if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value.trim())) {
                return 'Only letters, numbers, and underscores';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                setState(() {
                  _usernameController.text = controller.text.trim();
                });
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  Future<void> _loadProfile() async {
    _hasLoaded = true;
    setState(() => _isLoading = true);

    try {
      final api = ref.read(friendsApiServiceProvider);
      final profile = await api.getCurrentProfile();

      if (profile != null) {
        _usernameController.text = profile.username;
        _displayNameController.text = profile.displayName;
        _bioController.text = profile.bio;
        _friendRequestsEnabled = profile.friendRequestsEnabled;
      }
    } catch (e) {
      // Profile may not exist yet
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final api = ref.read(friendsApiServiceProvider);
      await api.updateProfile(
        username: _usernameController.text.trim().toLowerCase(),
        displayName: _displayNameController.text.trim(),
        bio: _bioController.text.trim(),
        friendRequestsEnabled: _friendRequestsEnabled,
      );

      ref.invalidate(currentUserProfileProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile saved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  void _showBlockedUsers(BuildContext context) {
    final blockedAsync = ref.watch(blockedUsersProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    'Blocked Users',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: blockedAsync.when(
                loading: () =>
                    const ListTileSkeletonList(count: 3),
                error: (error, stack) =>
                    Center(child: Text('Error: $error')),
                data: (blocked) {
                  if (blocked.isEmpty) {
                    return Center(
                      child: Text(
                        'No blocked users',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    itemCount: blocked.length,
                    itemBuilder: (context, index) {
                      final user = blocked[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.grey.shade200,
                          child: Text(
                            user.blockedUsername.isNotEmpty
                                ? user.blockedUsername[0].toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text('@${user.blockedUsername}'),
                        trailing: TextButton(
                          onPressed: () async {
                            final api =
                                ref.read(friendsApiServiceProvider);
                            await api.unblockUser(user.blockedUserId);
                            ref.invalidate(blockedUsersProvider);
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '${user.blockedUsername} unblocked'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          child: const Text('Unblock'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
