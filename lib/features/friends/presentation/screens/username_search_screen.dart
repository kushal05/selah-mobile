import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/models/user_profile_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// Screen that lists all discoverable users with an Add button to send
/// friend requests. A search bar at the top filters the list in real time.
class UsernameSearchScreen extends ConsumerStatefulWidget {
  const UsernameSearchScreen({super.key});

  @override
  ConsumerState<UsernameSearchScreen> createState() =>
      _UsernameSearchScreenState();
}

class _UsernameSearchScreenState extends ConsumerState<UsernameSearchScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  List<UserProfileModel> _users = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _error;
  Timer? _debounce;

  /// The current search query (empty = list all).
  String _currentQuery = '';

  /// Set of userIds for which a request was sent during this session,
  /// so we can immediately swap the button to "Sent".
  final _sentRequests = <String>{};

  /// Set of userIds currently being sent, to disable the button while sending.
  final _sendingRequests = <String>{};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadUsers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isLoadingMore || !_hasMore) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // Trigger when within 200px of the bottom
    if (currentScroll >= maxScroll - 200) {
      _loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Friends'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by username...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _currentQuery = '';
                          _loadUsers();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
              ),
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
            ),
          ),

          // Results
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const ListTileSkeletonList(count: 6);
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade600),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _loadUsers,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                _searchController.text.isNotEmpty
                    ? 'No users found'
                    : 'No new people to add',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        // +1 for the loading indicator at the bottom
        itemCount: _users.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _users.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final profile = _users[index];
          final alreadySent = _sentRequests.contains(profile.userId);
          final isSending = _sendingRequests.contains(profile.userId);
          return _UserCard(
            profile: profile,
            alreadySent: alreadySent,
            isSending: isSending,
            onAdd: (alreadySent || isSending) ? null : () => _sendFriendRequest(profile),
          );
        },
      ),
    );
  }

  /// Debounced search — waits 400ms after the user stops typing, then
  /// queries the server. Clears debounce and loads all users when empty.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();

    if (query.isEmpty) {
      _currentQuery = '';
      _loadUsers();
      return;
    }

    if (query.length < 2) return;

    _debounce = Timer(const Duration(milliseconds: 400), () {
      _currentQuery = query;
      _searchOnServer(query);
    });
  }

  /// Load the first page (resets list).
  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final searchService = ref.read(userSearchServiceProvider);
      final result = _currentQuery.isEmpty
          ? await searchService.listUsers()
          : await searchService.searchUsers(_currentQuery);
      if (mounted) {
        setState(() {
          _users = result.users;
          _hasMore = result.hasMore;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load users: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Search first page (resets list).
  Future<void> _searchOnServer(String query) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final searchService = ref.read(userSearchServiceProvider);
      final result = await searchService.searchUsers(query);
      if (mounted) {
        setState(() {
          _users = result.users;
          _hasMore = result.hasMore;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Search failed: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Load the next page and append results.
  Future<void> _loadMore() async {
    if (_isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final searchService = ref.read(userSearchServiceProvider);
      final result = _currentQuery.isEmpty
          ? await searchService.listUsers(offset: _users.length)
          : await searchService.searchUsers(_currentQuery, offset: _users.length);
      if (mounted) {
        setState(() {
          _users = [..._users, ...result.users];
          _hasMore = result.hasMore;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load more: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _sendFriendRequest(UserProfileModel profile) async {
    setState(() => _sendingRequests.add(profile.userId));
    try {
      final api = ref.read(friendsApiServiceProvider);
      await api.sendFriendRequest(toUserId: profile.userId);

      if (mounted) {
        setState(() {
          _sendingRequests.remove(profile.userId);
          _sentRequests.add(profile.userId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Friend request sent to ${profile.username}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingRequests.remove(profile.userId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send request: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _UserCard extends StatelessWidget {
  final UserProfileModel profile;
  final bool alreadySent;
  final bool isSending;
  final VoidCallback? onAdd;

  const _UserCard({
    required this.profile,
    required this.alreadySent,
    required this.isSending,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = profile.displayName.isNotEmpty
        ? profile.displayName
        : profile.username;

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
                AppTheme.teal.withValues(alpha: 0.1),
            child: Text(
              profile.initials,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.teal,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '@${profile.username}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (profile.bio.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.bio,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (alreadySent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Sent',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else if (isSending)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            ElevatedButton(
              onPressed: onAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.teal,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Add', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
