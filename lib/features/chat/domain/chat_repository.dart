import 'chat_message.dart';

abstract class ChatRepository {
  /// Watches messages in a conversation in real time.
  Stream<List<ChatMessage>> watchMessages(String conversationId);

  /// Sends a new message in the conversation.
  Future<ChatMessage> sendMessage({
    required String conversationId,
    String? text,
    String? attachmentUrl,
  });

  /// Marks a list of messages as read by the current user.
  Future<void> markMessagesAsRead(String conversationId, List<String> messageIds);

  /// Uploads an image attachment and returns its accessible URL.
  Future<String> uploadChatImage(List<int> bytes, String fileName, String mimeType);
}
