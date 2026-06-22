import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/sync/models/feedback_thread_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/sync/services/device_metadata_service.dart';

/// Screen for creating a new feedback thread with initial message
class CreateFeedbackScreen extends ConsumerStatefulWidget {
  const CreateFeedbackScreen({super.key});

  @override
  ConsumerState<CreateFeedbackScreen> createState() =>
      _CreateFeedbackScreenState();
}

class _CreateFeedbackScreenState extends ConsumerState<CreateFeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  FeedbackCategory _selectedCategory = FeedbackCategory.bug;
  bool _submitting = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Feedback'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Category selector
            Text(
              'Category',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: FeedbackCategory.values.map((category) {
                final isSelected = category == _selectedCategory;
                return ChoiceChip(
                  label: Text(
                    category.displayName,
                    style: TextStyle(
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() => _selectedCategory = category);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Subject field
            TextFormField(
              controller: _subjectController,
              decoration: InputDecoration(
                labelText: 'Subject',
                hintText: 'Brief summary of your feedback',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLength: 100,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a subject';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Message field
            TextFormField(
              controller: _messageController,
              decoration: InputDecoration(
                labelText: 'Message',
                hintText: 'Describe your feedback in detail...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                alignLabelWithHint: true,
              ),
              maxLines: 6,
              minLines: 4,
              textInputAction: TextInputAction.newline,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a message';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _submitting ? null : _handleSubmit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit Feedback'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
      final threadRepo = ref.read(feedbackThreadRepositoryProvider);
      final messageRepo = ref.read(feedbackMessageRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);

      // Capture device metadata
      final deviceModel = await DeviceMetadataService.getDeviceModel();
      final osVersion = await DeviceMetadataService.getOsVersion();
      final appVersion = await DeviceMetadataService.getAppVersion();

      // 1. Create the thread with device metadata
      final thread = await threadRepo.createThread(
        userId: userId,
        category: _selectedCategory.toDbValue(),
        subject: _subjectController.text.trim(),
        deviceModel: deviceModel,
        osVersion: osVersion,
        appVersion: appVersion,
      );

      // 2. Create the initial message
      await messageRepo.addMessage(
        threadId: thread.id,
        userId: userId,
        message: _messageController.text.trim(),
        senderType: 'user',
      );

      if (!mounted) return;

      // Navigate to the thread
      final path = Routes.feedbackThread.replaceFirst(':threadId', thread.id);
      context.go(Routes.feedback);
      context.push(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit feedback: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
