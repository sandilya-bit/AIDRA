import 'package:flutter/material.dart';

import '../constants/app_enums.dart';
import 'parse.dart';

/// A single notification as delivered (DB `notifications`, PRD Volume II §7).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.eventType,
    required this.priority,
    required this.createdAt,
    this.channel = NotificationChannel.push,
    this.incidentId,
    this.broadcastId,
    this.actorName,
    this.isRead = false,
    this.deepLink,
    this.payload = const <String, dynamic>{},
  });

  final String id;
  final String title;
  final String body;

  /// e.g. `report.created`, `assignment.offered`, `escalation.l3`, `broadcast.new`.
  final String eventType;
  final NotificationPriority priority;
  final NotificationChannel channel;
  final String? incidentId;
  final String? broadcastId;
  final String? actorName;
  final bool isRead;
  final DateTime createdAt;

  /// In-app route to open when the notification is tapped.
  final String? deepLink;
  final Map<String, dynamic> payload;

  bool get isEmergency => priority == NotificationPriority.p0;

  IconData get icon => switch (eventType.split('.').first) {
        'report' => Icons.assignment_outlined,
        'incident' => Icons.warning_amber_rounded,
        'assignment' => Icons.volunteer_activism_outlined,
        'escalation' => Icons.campaign_outlined,
        'broadcast' => Icons.campaign_outlined,
        'hospital' => Icons.local_hospital_outlined,
        'resource' => Icons.inventory_2_outlined,
        'route' => Icons.alt_route_outlined,
        _ => Icons.notifications_none,
      };

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        title: title,
        body: body,
        eventType: eventType,
        priority: priority,
        channel: channel,
        incidentId: incidentId,
        broadcastId: broadcastId,
        actorName: actorName,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        deepLink: deepLink,
        payload: payload,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'event_type': eventType,
        'priority': priority.key,
        'channel': channel.key,
        'incident_id': incidentId,
        'broadcast_id': broadcastId,
        'actor_name': actorName,
        'is_read': isRead,
        'created_at': createdAt.toIso8601String(),
        'deep_link': deepLink,
        'payload': payload,
      };

  static AppNotification fromJson(Map<String, dynamic> json) => AppNotification(
        id: parseString(json['id'], 'n-${json.hashCode}'),
        title: parseString(json['title'], 'AIDRA'),
        body: parseString(json['body']),
        eventType: parseString(json['event_type'], 'system'),
        priority: enumFromKey(
          NotificationPriority.values,
          json['priority']?.toString(),
          NotificationPriority.p2,
        ),
        channel: enumFromKey(
          NotificationChannel.values,
          json['channel']?.toString(),
          NotificationChannel.push,
        ),
        incidentId: json['incident_id']?.toString(),
        broadcastId: json['broadcast_id']?.toString(),
        actorName: json['actor_name']?.toString(),
        isRead: parseBool(json['is_read']),
        createdAt: parseDate(json['created_at']),
        deepLink: json['deep_link']?.toString(),
        payload: parseMap(json['payload']),
      );
}

/// Authority broadcast to an area polygon (FR-802).
class Broadcast {
  const Broadcast({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.languages,
    required this.sentAt,
    this.recipientCount = 0,
    this.channels = const <NotificationChannel>[NotificationChannel.push],
    this.capPayload,
  });

  final String id;
  final String title;
  final Map<String, String> message;
  final UrgencyLevel severity;
  final List<String> languages;
  final DateTime sentAt;
  final int recipientCount;
  final List<NotificationChannel> channels;

  /// Common Alerting Protocol payload for interoperability (Volume II §11.5).
  final Map<String, dynamic>? capPayload;

  String localizedMessage(String languageCode) =>
      message[languageCode] ?? message['en'] ?? '';

  static Broadcast fromJson(Map<String, dynamic> json) => Broadcast(
        id: parseString(json['id'], 'b-${json.hashCode}'),
        title: parseString(json['title'], 'Alert'),
        message: parseMap(json['message']).map(
          (String key, dynamic value) => MapEntry<String, String>(key, parseString(value)),
        ),
        severity: enumFromKey(
          UrgencyLevel.values,
          json['severity']?.toString(),
          UrgencyLevel.high,
        ),
        languages: parseStringList(json['languages']),
        sentAt: parseDate(json['sent_at'] ?? json['created_at']),
        recipientCount: parseInt(json['recipient_count']),
        capPayload: json['cap_payload'] == null ? null : parseMap(json['cap_payload']),
      );
}
