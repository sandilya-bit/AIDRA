import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../domain/chat_message.dart';
import 'chat_providers.dart';

/// Realtime Incident Chat Screen with delivery receipts, image uploads,
/// and live Firestore sync.
class IncidentChatScreen extends ConsumerStatefulWidget {
  const IncidentChatScreen({
    super.key,
    required this.conversationId,
    this.title = 'Incident Response Thread',
    this.subtitle = 'Real-time coordination channel',
  });

  final String conversationId;
  final String title;
  final String subtitle;

  @override
  ConsumerState<IncidentChatScreen> createState() => _IncidentChatScreenState();
}

class _IncidentChatScreenState extends ConsumerState<IncidentChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  bool _isUploadingImage = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend() async {
    final String text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    final repo = ref.read(chatRepositoryProvider);
    await repo.sendMessage(
      conversationId: widget.conversationId,
      text: text,
    );
    _scrollToBottom();
  }

  Future<void> _handlePickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _isUploadingImage = true);

      final List<int> bytes = await picked.readAsBytes();
      final String mimeType = picked.mimeType ?? 'image/jpeg';
      final repo = ref.read(chatRepositoryProvider);

      final String attachmentUrl = await repo.uploadChatImage(
        bytes,
        picked.name,
        mimeType,
      );

      await repo.sendMessage(
        conversationId: widget.conversationId,
        text: null,
        attachmentUrl: attachmentUrl,
      );

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final messagesAsync =
        ref.watch(conversationMessagesProvider(widget.conversationId));

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: AppTopBar(
          title: widget.title,
          subtitle: widget.subtitle,
          actions: <Widget>[
            AppIconButton(
              icon: Icons.refresh,
              tooltip: 'Refresh messages',
              onPressed: () =>
                  ref.refresh(conversationMessagesProvider(widget.conversationId)),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: messagesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(
                  child: Text(
                    'Failed to load conversation: $err',
                    style: AppText.caption.copyWith(color: AppColors.danger),
                  ),
                ),
                data: (List<ChatMessage> messages) {
                  if (messages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Icon(Icons.chat_bubble_outline,
                              size: 48, color: AppColors.muted),
                          const SizedBox(height: AppSizes.md),
                          Text(
                            'No messages yet in this incident thread.',
                            style: AppText.body.copyWith(
                                color: palette.textSecondary),
                          ),
                          const SizedBox(height: AppSizes.xs),
                          Text(
                            'Send an update, share safety notes, or post photos.',
                            style: AppText.caption.copyWith(
                                color: palette.textSecondary),
                          ),
                        ],
                      ),
                    );
                  }

                  // Automatically mark incoming unread messages as read
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final unreadIds = messages
                        .where((m) =>
                            m.senderId != 'me' &&
                            m.status != MessageDeliveryStatus.read)
                        .map((m) => m.id)
                        .toList();
                    if (unreadIds.isNotEmpty) {
                      ref
                          .read(chatRepositoryProvider)
                          .markMessagesAsRead(widget.conversationId, unreadIds);
                    }
                  });

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(AppSizes.md),
                    itemCount: messages.length,
                    itemBuilder: (BuildContext context, int index) {
                      final ChatMessage msg = messages[index];
                      final bool isMe = msg.senderId == 'me';
                      return _IncidentMessageTile(message: msg, isMe: isMe);
                    },
                  );
                },
              ),
            ),
            if (_isUploadingImage)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: palette.surface,
                child: Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: AppSizes.md),
                    Text(
                      'Uploading incident photo…',
                      style: AppText.caption.copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            _buildInputBar(palette),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(AppPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.photo_camera_outlined),
            tooltip: 'Attach Photo',
            color: palette.textSecondary,
            onPressed: _handlePickImage,
          ),
          const SizedBox(width: AppSizes.xs),
          Expanded(
            child: TextField(
              controller: _textController,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSend(),
              decoration: InputDecoration(
                hintText: 'Type coordinate or message…',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.md,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: palette.border),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          IconButton.filled(
            icon: const Icon(Icons.send, size: 18),
            tooltip: context.tr('common.submit'),
            onPressed: _handleSend,
          ),
        ],
      ),
    );
  }
}

class _IncidentMessageTile extends StatelessWidget {
  const _IncidentMessageTile({
    required this.message,
    required this.isMe,
  });

  final ChatMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final Color bubbleColor = isMe ? AppColors.primary : palette.surface;
    final Color textColor = isMe ? Colors.white : palette.textPrimary;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (!isMe) ...<Widget>[
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.accent,
              child: Text(
                message.senderName.isNotEmpty
                    ? message.senderName[0].toUpperCase()
                    : 'R',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
            const SizedBox(width: AppSizes.xs),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(AppSizes.sm + 2),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppSizes.radiusMd),
                  topRight: const Radius.circular(AppSizes.radiusMd),
                  bottomLeft: Radius.circular(isMe ? AppSizes.radiusMd : 2),
                  bottomRight: Radius.circular(isMe ? 2 : AppSizes.radiusMd),
                ),
                border: Border.all(
                  color: isMe ? AppColors.primary : palette.border,
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: <Widget>[
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        message.senderName,
                        style: AppText.caption.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (message.hasAttachment) ...<Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                      child: GestureDetector(
                        onTap: () => _viewFullImage(context, message.attachmentUrl!),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 180,
                            maxWidth: 240,
                          ),
                          child: Image.network(
                            message.attachmentUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.black12,
                              padding: const EdgeInsets.all(16),
                              child: const Icon(Icons.broken_image),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (message.text != null && message.text!.isNotEmpty)
                      const SizedBox(height: 6),
                  ],
                  if (message.text != null && message.text!.isNotEmpty)
                    Text(
                      message.text!,
                      style: AppText.body.copyWith(color: textColor),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _formatTime(message.createdAt),
                        style: AppText.caption.copyWith(
                          fontSize: 10,
                          color: isMe
                              ? Colors.white.withAlpha(200)
                              : palette.textSecondary,
                        ),
                      ),
                      if (isMe) ...<Widget>[
                        const SizedBox(width: 4),
                        _buildReceiptIcon(message.status),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptIcon(MessageDeliveryStatus status) {
    switch (status) {
      case MessageDeliveryStatus.sending:
        return const Icon(Icons.access_time, size: 12, color: Colors.white70);
      case MessageDeliveryStatus.sent:
        return const Icon(Icons.check, size: 12, color: Colors.white70);
      case MessageDeliveryStatus.delivered:
        return const Icon(Icons.done_all, size: 12, color: Colors.white70);
      case MessageDeliveryStatus.read:
        return const Icon(Icons.done_all, size: 12, color: Color(0xFF64B5F6));
    }
  }

  String _formatTime(DateTime dt) {
    final String h = dt.hour.toString().padLeft(2, '0');
    final String m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _viewFullImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: <Widget>[
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
