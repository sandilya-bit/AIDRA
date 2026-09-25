import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';

/// Chat support (design system §11.14).
///
/// An offline-capable assistant thread: it answers safety/welfare questions
/// from a local knowledge base and hands off to a human coordinator. The same
/// thread shape is used by incident threads and NGO org channels server-side
/// (`conversations` / `messages` in the database design).
class SupportChatScreen extends ConsumerStatefulWidget {
  const SupportChatScreen({super.key});

  @override
  ConsumerState<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends ConsumerState<SupportChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_ChatMessage> _messages = <_ChatMessage>[
    _ChatMessage(
      id: 'm1',
      body: 'Hi, I am AIDRA Assist. I can help with shelters, safe routes and '
          'first-aid steps. What do you need right now?',
      isAgent: true,
      createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
    ),
  ];

  static const List<String> _quickReplies = <String>[
    'Nearest shelter',
    'Is the road to the camp open?',
    'First aid for a fracture',
    'Talk to a human',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: AppTopBar(
          title: context.tr('dash.chatSupport'),
          subtitle: 'Available offline · replies in your language',
          actions: <Widget>[
            AppIconButton(
              icon: Icons.support_agent_outlined,
              tooltip: 'Escalate to a coordinator',
              onPressed: _escalate,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: AppResponsiveBody(
          maxWidth: 640,
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: AppSizes.lg),
                  itemCount: _messages.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _MessageBubble(message: _messages[index]),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _quickReplies
                      .map(
                        (String reply) => Padding(
                          padding: const EdgeInsets.only(right: AppSizes.sm),
                          child: AppChoiceChip(
                            label: reply,
                            selected: false,
                            color: AppColors.primary,
                            onSelected: () => _send(reply),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: 'Type your message…',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.mic_none),
                          tooltip: 'Voice message',
                          onPressed: () => _send('Voice message (transcribed)'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  IconButton.filled(
                    onPressed: () => _send(_input.text),
                    icon: const Icon(Icons.send),
                    tooltip: 'Send',
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                'Messages are queued offline and delivered when you reconnect.',
                style: AppText.caption.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: AppSizes.md),
            ],
          ),
        ),
      ),
    );
  }

  void _send(String text) {
    final String message = text.trim();
    if (message.isEmpty) return;

    setState(() {
      _messages.add(
        _ChatMessage(
          id: const Uuid().v4(),
          body: message,
          isAgent: false,
          createdAt: DateTime.now(),
        ),
      );
      _messages.add(
        _ChatMessage(
          id: const Uuid().v4(),
          body: _reply(message),
          isAgent: true,
          createdAt: DateTime.now(),
        ),
      );
    });
    _input.clear();
    _scrollToBottom();
  }

  void _escalate() {
    setState(() {
      _messages.add(
        _ChatMessage(
          id: const Uuid().v4(),
          body: 'Connecting you to the district coordinator. Median wait during an '
              'active event is 4 minutes — your chat history is attached.',
          isAgent: true,
          createdAt: DateTime.now(),
          isEscalation: true,
        ),
      );
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Local knowledge base standing in for the assistant backend.
  String _reply(String message) {
    final String value = message.toLowerCase();
    if (value.contains('shelter')) {
      return 'The nearest open shelter is Community Hall Shelter — 180/250 places '
          'used, water and medical support on site. It is 1.2 km away and the '
          'approach road is open.';
    }
    if (value.contains('road') || value.contains('open')) {
      return 'The inner ring road is open. The riverbank underpass is flooded and '
          'closed, so use the ring road corridor — AIDRA routing already avoids it.';
    }
    if (value.contains('fracture') || value.contains('first aid')) {
      return 'For a suspected fracture: do not attempt to straighten the limb. '
          'Immobilise with a splint, apply a cold pack over cloth, keep the person '
          'still and warm, and mark the injury clearly for the medic. A responder '
          'is being matched to you now.';
    }
    if (value.contains('human') || value.contains('coordinator')) {
      _escalate();
      return 'Escalating you to a human coordinator now.';
    }
    if (value.contains('water') || value.contains('food')) {
      return 'Relief food and drinking water are dispatched to the Community Hall '
          'Shelter. Bring containers — water is distributed as 5 L per person per day.';
    }
    return 'Noted. I have logged this and matched it to the closest active incident. '
        'If anyone is in immediate danger, file an emergency report so AI triage can '
        'escalate it to a responder right away.';
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.id,
    required this.body,
    required this.isAgent,
    required this.createdAt,
    this.isEscalation = false,
  });

  final String id;
  final String body;
  final bool isAgent;
  final DateTime createdAt;
  final bool isEscalation;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final Color background = message.isAgent
        ? palette.surface
        : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: Row(
        mainAxisAlignment:
            message.isAgent ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (message.isAgent) ...<Widget>[
            const AppIconTile(
              icon: Icons.support_agent_outlined,
              color: AppColors.purple,
              size: 34,
            ),
            const SizedBox(width: AppSizes.sm),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                border: Border.all(
                  color: message.isAgent
                      ? (message.isEscalation ? AppColors.warning : palette.border)
                      : AppColors.primary,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (message.isEscalation)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'ESCALATED',
                        style: AppText.label.copyWith(color: AppColors.warning),
                      ),
                    ),
                  Text(
                    message.body,
                    style: AppText.body.copyWith(
                      color: message.isAgent ? palette.textPrimary : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
