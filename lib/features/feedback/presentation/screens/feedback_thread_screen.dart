import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/models/feedback_attachment_model.dart';
import '../../../../core/sync/models/feedback_message_model.dart';
import '../../../../core/sync/models/feedback_thread_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';

/// Chat-style screen for a feedback thread
class FeedbackThreadScreen extends ConsumerStatefulWidget {
  final String threadId;

  const FeedbackThreadScreen({super.key, required this.threadId});

  @override
  ConsumerState<FeedbackThreadScreen> createState() =>
      _FeedbackThreadScreenState();
}

class _FeedbackThreadScreenState extends ConsumerState<FeedbackThreadScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final threadAsync = ref.watch(feedbackThreadByIdProvider(widget.threadId));
    final messagesAsync =
        ref.watch(feedbackMessagesStreamProvider(widget.threadId));

    return Scaffold(
      appBar: AppBar(
        title: threadAsync.when(
          loading: () => const Text('Feedback'),
          error: (_, _) => const Text('Feedback'),
          data: (thread) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                thread?.subject ?? 'Feedback',
                style: const TextStyle(fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (thread != null)
                Text(
                  '${thread.categoryEnum.displayName} · ${thread.statusEnum.displayName}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
            ],
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: messagesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Error loading messages',
                        style: TextStyle(color: Colors.grey.shade600)),
                    TextButton(
                      onPressed: () => ref.invalidate(
                          feedbackMessagesStreamProvider(widget.threadId)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });
                return ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final showDateHeader = index == 0 ||
                        !_isSameDay(
                            messages[index - 1].createdAt, msg.createdAt);
                    return Column(
                      children: [
                        if (showDateHeader) _DateHeader(timestamp: msg.createdAt),
                        if (msg.isSystemMessage)
                          _SystemMessage(message: msg)
                        else
                          _ChatBubble(message: msg),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Input bar
          _buildInputBar(threadAsync),
        ],
      ),
    );
  }

  Widget _buildInputBar(AsyncValue<FeedbackThreadModel?> threadAsync) {
    final isClosed = threadAsync.valueOrNull?.isClosed ?? false;

    if (isClosed) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Text(
          'This thread is closed and no longer accepts replies.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _handleSend,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSend() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);

    try {
      final messageRepo = ref.read(feedbackMessageRepositoryProvider);
      final threadRepo = ref.read(feedbackThreadRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);

      // Add message
      await messageRepo.addMessage(
        threadId: widget.threadId,
        userId: userId,
        message: text,
        senderType: 'user',
      );

      // Update thread lastMessageAt
      await threadRepo.updateThread(
        id: widget.threadId,
        lastMessageAt: DateTime.now().millisecondsSinceEpoch,
      );

      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  bool _isSameDay(int ts1, int ts2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(ts1);
    final d2 = DateTime.fromMillisecondsSinceEpoch(ts2);
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }
}

/// System message displayed as a centered, muted banner
class _SystemMessage extends StatelessWidget {
  final FeedbackMessageModel message;

  const _SystemMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends ConsumerWidget {
  final FeedbackMessageModel message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = !message.isFromAdmin;
    final time = DateTime.fromMillisecondsSinceEpoch(message.createdAt);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade200,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser
                ? const Radius.circular(16)
                : const Radius.circular(4),
            bottomRight: isUser
                ? const Radius.circular(4)
                : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.isFromAdmin)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Support',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            Text(
              message.message,
              style: TextStyle(
                color: isUser ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
            ),
            // Attachment previews
            if (message.hasFiles)
              _AttachmentList(messageId: message.id),
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 11,
                color: isUser
                    ? Colors.white.withValues(alpha: 0.7)
                    : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays attachments for a message
class _AttachmentList extends ConsumerWidget {
  final String messageId;

  const _AttachmentList({required this.messageId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentsAsync =
        ref.watch(feedbackAttachmentsStreamProvider(messageId));

    return attachmentsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 8),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (attachments) {
        if (attachments.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: attachments.map((a) => _AttachmentTile(attachment: a)).toList(),
          ),
        );
      },
    );
  }
}

/// Single attachment tile showing icon + filename
class _AttachmentTile extends StatelessWidget {
  final FeedbackAttachmentModel attachment;

  const _AttachmentTile({required this.attachment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _iconForType(attachment.typeEnum),
            size: 16,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              attachment.fileName ?? 'Attachment',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                decoration: TextDecoration.underline,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForType(FeedbackAttachmentType type) {
    switch (type) {
      case FeedbackAttachmentType.image:
        return Icons.image_outlined;
      case FeedbackAttachmentType.video:
        return Icons.videocam_outlined;
      case FeedbackAttachmentType.file:
        return Icons.attach_file;
    }
  }
}

class _DateHeader extends StatelessWidget {
  final int timestamp;

  const _DateHeader({required this.timestamp});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(date);

    String label;
    if (diff.inDays == 0) {
      label = 'Today';
    } else if (diff.inDays == 1) {
      label = 'Yesterday';
    } else {
      label = '${date.month}/${date.day}/${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
      ),
    );
  }
}
