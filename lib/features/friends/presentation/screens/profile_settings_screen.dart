import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';

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
        title: Text(l10n(context).profilePrivacy),
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
                : Text(
                    l10n(context).actionSave,
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
                              : context.mutedText,
                        ),
                      ),
                      trailing: Icon(
                        Icons.edit_outlined,
                        color: context.mutedText,
                        size: 20,
                      ),
                      onTap: () => _showUsernameEditDialog(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n(context).yourUniqueUsernameForFriendsToFindYou,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Display name field
                  _buildSectionHeader('DISPLAY NAME'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _displayNameController,
                    decoration: InputDecoration(
                      hintText: l10n(context).displayName,
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
                      hintText: l10n(context).tellOthersAboutYourself,
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
                      title: Text(l10n(context).allowFriendRequests),
                      subtitle: Text(
                        l10n(context).whenOffNoOneCanSendYouFriendRequests,
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
                      leading: Icon(Icons.block, color: context.dangerText),
                      title: Text(l10n(context).blockedUsers),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: context.hintText,
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
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        title: Text(l10n(context).editUsername),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              prefixText: '@',
              hintText: l10n(context).username,
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
            child: Text(l10n(context).actionCancel),
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
            child: Text(l10n(context).actionSave),
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
          SnackBar(
            content: Text(l10n(context).profileSaved),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'save profile')),
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
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        // Keeps the sheet's last control clear of the gesture bar.
        top: false,
        child: DraggableScrollableSheet(
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
                  Text(
                    l10n(context).blockedUsers,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: l10n(context).close,
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
                    Center(child: Text(UserFacingError.forLoad(error))),
                data: (blocked) {
                  if (blocked.isEmpty) {
                    return Center(
                      child: Text(
                        l10n(context).noBlockedUsers,
                        style: TextStyle(color: context.mutedText),
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
                          child: Text(l10n(context).unblock),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      )),
    );
  }
}
