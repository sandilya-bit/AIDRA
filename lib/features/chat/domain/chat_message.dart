import 'package:flutter/foundation.dart';

enum MessageDeliveryStatus {
  sending,
  sent,
  delivered,
  read,
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    this.text,
    this.attachmentUrl,
    required this.createdAt,
    this.status = MessageDeliveryStatus.sent,
    this.readBy = const <String>[],
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String? text;
  final String? attachmentUrl;
  final DateTime createdAt;
  final MessageDeliveryStatus status;
  final List<String> readBy;

  bool get hasAttachment => attachmentUrl != null && attachmentUrl!.isNotEmpty;

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? senderName,
    String? text,
    String? attachmentUrl,
    DateTime? createdAt,
    MessageDeliveryStatus? status,
    List<String>? readBy,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      text: text ?? this.text,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      readBy: readBy ?? this.readBy,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    MessageDeliveryStatus status = MessageDeliveryStatus.sent;
    final String? rawStatus = json['status'] as String?;
    if (rawStatus == 'sending') status = MessageDeliveryStatus.sending;
    if (rawStatus == 'delivered') status = MessageDeliveryStatus.delivered;
    if (rawStatus == 'read') status = MessageDeliveryStatus.read;

    return ChatMessage(
      id: json['id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      senderName: json['sender_name'] as String? ?? 'Responder',
      text: json['text'] as String?,
      attachmentUrl: json['attachment_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      status: status,
      readBy: (json['read_by'] as List<dynamic>?)
              ?.map((dynamic e) => e.toString())
              .toList() ??
          const <String>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'sender_name': senderName,
      'text': text,
      'attachment_url': attachmentUrl,
      'created_at': createdAt.toIso8601String(),
      'status': status.name,
      'read_by': readBy,
    };
  }
}
