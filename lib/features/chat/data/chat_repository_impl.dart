import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../domain/chat_message.dart';
import '../domain/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl({
    required ApiClient apiClient,
    FirebaseFirestore? firestore,
  })  : _apiClient = apiClient,
        _firestore = firestore;

  final ApiClient _apiClient;
  FirebaseFirestore? _firestore;

  // Local fallback storage for offline operation or when Firestore is unconfigured
  final Map<String, List<ChatMessage>> _localMessages = <String, List<ChatMessage>>{};
  final Map<String, StreamController<List<ChatMessage>>> _streamControllers =
      <String, StreamController<List<ChatMessage>>>{};

  FirebaseFirestore? get firestore {
    if (_firestore != null) return _firestore;
    try {
      if (Firebase.apps.isNotEmpty) {
        _firestore = FirebaseFirestore.instance;
      }
    } catch (_) {}
    return _firestore;
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    // If Firebase is available and configured, stream directly from Firestore
    if (AppConfig.useFirebase && firestore != null) {
      try {
        return firestore!
            .collection('conversations')
            .doc(conversationId)
            .collection('messages')
            .orderBy('created_at', descending: false)
            .snapshots()
            .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
          return snapshot.docs.map((doc) {
            final Map<String, dynamic> data = doc.data();
            data['id'] = doc.id;
            return ChatMessage.fromJson(data);
          }).toList();
        });
      } catch (_) {
        // Fall back to local stream controller
      }
    }

    // Local / Offline fallback stream
    if (!_streamControllers.containsKey(conversationId)) {
      _streamControllers[conversationId] =
          StreamController<List<ChatMessage>>.broadcast();
    }

    // Initial broadcast with current in-memory items
    final List<ChatMessage> current =
        _localMessages[conversationId] ?? <ChatMessage>[];
    Timer.run(() {
      if (!(_streamControllers[conversationId]?.isClosed ?? true)) {
        _streamControllers[conversationId]!.add(List<ChatMessage>.from(current));
      }
    });

    // Also fetch historical messages from backend if remote is enabled
    if (AppConfig.useRemoteBackend) {
      _fetchRemoteMessages(conversationId);
    }

    return _streamControllers[conversationId]!.stream;
  }

  Future<void> _fetchRemoteMessages(String conversationId) async {
    try {
      final dynamic response = await _apiClient.get(
        '/chat/conversations/$conversationId/messages',
      );
      if (response is Map<String, dynamic> && response['items'] is List) {
        final List<ChatMessage> fetched = (response['items'] as List<dynamic>)
            .map((dynamic item) =>
                ChatMessage.fromJson(item as Map<String, dynamic>))
            .toList();
        _localMessages[conversationId] = fetched;
        _streamControllers[conversationId]?.add(fetched);
      }
    } catch (_) {}
  }

  @override
  Future<ChatMessage> sendMessage({
    required String conversationId,
    String? text,
    String? attachmentUrl,
  }) async {
    final String messageId = const Uuid().v4();
    final ChatMessage message = ChatMessage(
      id: messageId,
      conversationId: conversationId,
      senderId: 'me',
      senderName: 'You',
      text: text,
      attachmentUrl: attachmentUrl,
      createdAt: DateTime.now(),
      status: MessageDeliveryStatus.sending,
      readBy: const <String>['me'],
    );

    // Add to local state immediately (optimistic UI)
    _localMessages.putIfAbsent(conversationId, () => <ChatMessage>[]);
    _localMessages[conversationId]!.add(message);
    _streamControllers[conversationId]
        ?.add(List<ChatMessage>.from(_localMessages[conversationId]!));

    // Dual-write to Firestore if available
    if (AppConfig.useFirebase && firestore != null) {
      try {
        await firestore!
            .collection('conversations')
            .doc(conversationId)
            .collection('messages')
            .doc(messageId)
            .set(message.toJson());
      } catch (_) {}
    }

    // Dual-write to REST backend
    if (AppConfig.useRemoteBackend) {
      try {
        final dynamic res = await _apiClient.post(
          '/chat/conversations/$conversationId/messages',
          data: <String, dynamic>{
            'id': messageId,
            'text': text,
            'attachment_url': attachmentUrl,
          },
        );
        if (res is Map<String, dynamic> && res['message'] is Map<String, dynamic>) {
          final ChatMessage confirmed =
              ChatMessage.fromJson(res['message'] as Map<String, dynamic>);
          _updateMessageInList(conversationId, confirmed);
          return confirmed;
        }
      } catch (_) {}
    }

    // Mark as sent
    final ChatMessage sent = message.copyWith(status: MessageDeliveryStatus.sent);
    _updateMessageInList(conversationId, sent);
    return sent;
  }

  void _updateMessageInList(String conversationId, ChatMessage updated) {
    final List<ChatMessage>? list = _localMessages[conversationId];
    if (list == null) return;
    final int idx = list.indexWhere((m) => m.id == updated.id);
    if (idx != -1) {
      list[idx] = updated;
      _streamControllers[conversationId]?.add(List<ChatMessage>.from(list));
    }
  }

  @override
  Future<void> markMessagesAsRead(
    String conversationId,
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return;

    // Update local state
    final List<ChatMessage>? list = _localMessages[conversationId];
    if (list != null) {
      for (int i = 0; i < list.length; i++) {
        if (messageIds.contains(list[i].id)) {
          list[i] = list[i].copyWith(status: MessageDeliveryStatus.read);
        }
      }
      _streamControllers[conversationId]?.add(List<ChatMessage>.from(list));
    }

    // Update remote
    if (AppConfig.useRemoteBackend) {
      try {
        await _apiClient.post(
          '/chat/conversations/$conversationId/receipts',
          data: <String, dynamic>{'message_ids': messageIds},
        );
      } catch (_) {}
    }
  }

  @override
  Future<String> uploadChatImage(
    List<int> bytes,
    String fileName,
    String mimeType,
  ) async {
    final String base64Data = base64Encode(bytes);
    try {
      final dynamic response = await _apiClient.post(
        '/chat/upload',
        data: <String, dynamic>{
          'data_base64': base64Data,
          'mime_type': mimeType,
          'filename': fileName,
        },
      );
      if (response is Map<String, dynamic> && response['url'] is String) {
        return response['url'] as String;
      }
    } catch (_) {}

    // Fallback data URI
    return 'data:$mimeType;base64,$base64Data';
  }
}
