import * as admin from 'firebase-admin';
import { query } from '../db';

export interface PushNotificationPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

/**
 * Registers or updates an FCM device token for a user.
 */
export async function registerDeviceToken(
  userId: string,
  fcmToken: string,
  platform: 'android' | 'ios' | 'web'
): Promise<void> {
  await query(
    `INSERT INTO user_devices (user_id, fcm_token, platform, updated_at)
     VALUES ($1, $2, $3, NOW())
     ON CONFLICT (fcm_token)
     DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, updated_at = NOW()`,
    [userId, fcmToken, platform]
  );
}

/**
 * Sends a multicast push notification to a list of tokens.
 */
export async function sendMulticast(
  tokens: string[],
  payload: PushNotificationPayload
): Promise<{ successCount: number; failureCount: number }> {
  if (!tokens || tokens.length === 0) {
    return { successCount: 0, failureCount: 0 };
  }

  // Filter out duplicates and empty strings
  const uniqueTokens = Array.from(new Set(tokens.filter((t) => typeof t === 'string' && t.length >= 10)));
  if (uniqueTokens.length === 0) {
    return { successCount: 0, failureCount: 0 };
  }

  if (admin.apps.length === 0) {
    console.info(`[FCM Sim] Push to ${uniqueTokens.length} device(s): "${payload.title}" - ${payload.body}`);
    return { successCount: uniqueTokens.length, failureCount: 0 };
  }

  try {
    const messaging = admin.messaging();
    const result = await messaging.sendEachForMulticast({
      tokens: uniqueTokens,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: payload.data || {},
    });
    return { successCount: result.successCount, failureCount: result.failureCount };
  } catch (err) {
    console.warn('[FCM] Error sending multicast notification:', (err as Error).message);
    return { successCount: 0, failureCount: uniqueTokens.length };
  }
}

/**
 * Sends a push notification to all devices registered to a specific user.
 */
export async function sendToUser(
  userId: string,
  payload: PushNotificationPayload
): Promise<{ successCount: number; failureCount: number }> {
  try {
    const rows = await query<{ fcm_token: string }>(
      'SELECT fcm_token FROM user_devices WHERE user_id = $1',
      [userId]
    );
    const tokens = rows.map((r) => r.fcm_token);
    return await sendMulticast(tokens, payload);
  } catch (err) {
    console.warn(`[FCM] Failed to look up devices for user ${userId}:`, (err as Error).message);
    return { successCount: 0, failureCount: 0 };
  }
}

/**
 * Event-triggered notification: Dispatched when a new emergency report is filed.
 * Notifies the 'aidra_authorities' topic and nearby available volunteers.
 */
export async function notifyEmergencyReported(report: {
  id: string;
  reportCode: string;
  title: string;
  urgency: string;
  victims: number;
  latitude: number;
  longitude: number;
}): Promise<void> {
  const title = `🚨 New ${report.urgency.toUpperCase()} Emergency: ${report.reportCode}`;
  const body = `${report.title.slice(0, 120)}${report.victims > 0 ? ` (${report.victims} people at risk)` : ''}`;
  const data = {
    event_type: 'emergency_reported',
    report_id: report.id,
    report_code: report.reportCode,
    urgency: report.urgency,
    lat: String(report.latitude),
    lng: String(report.longitude),
  };

  // 1. Topic broadcast to command centers & authorities
  if (admin.apps.length > 0) {
    try {
      await admin.messaging().send({
        topic: 'aidra_authorities',
        notification: { title, body },
        data,
      });
    } catch (err) {
      console.warn('[FCM] Topic notification failed:', (err as Error).message);
    }
  } else {
    console.info(`[FCM Sim] Topic 'aidra_authorities' received: "${title}" - ${body}`);
  }

  // 2. Multicast to nearby available volunteers (within 10 km)
  try {
    const nearbyVolunteers = await query<{ user_id: string }>(
      `SELECT user_id FROM volunteer_profiles
       WHERE availability = 'available'
         AND latitude IS NOT NULL
         AND longitude IS NOT NULL
         AND (
           6371 * acos(
             cos(radians($1)) * cos(radians(latitude)) *
             cos(radians(longitude) - radians($2)) +
             sin(radians($1)) * sin(radians(latitude))
           )
         ) <= 10.0
       LIMIT 50`,
      [report.latitude, report.longitude]
    );

    if (nearbyVolunteers.length > 0) {
      const userIds = nearbyVolunteers.map((v) => v.user_id);
      const devices = await query<{ fcm_token: string }>(
        `SELECT fcm_token FROM user_devices WHERE user_id = ANY($1::text[])`,
        [userIds]
      );
      const tokens = devices.map((d) => d.fcm_token);
      await sendMulticast(tokens, {
        title: `Nearby Alert: ${report.title}`,
        body: `Emergency reported within 10 km. Tap to view details and response route.`,
        data,
      });
    }
  } catch (err) {
    console.warn('[FCM] Nearby volunteer notification query failed:', (err as Error).message);
  }
}

/**
 * Event-triggered notification: Dispatched when a volunteer is assigned to an incident.
 */
export async function notifyVolunteerAssigned(
  volunteerUserId: string,
  incident: { id: string; title: string; locationText?: string; urgency: string }
): Promise<void> {
  await sendToUser(volunteerUserId, {
    title: 'Dispatched to Emergency',
    body: `You have been assigned to: ${incident.title}. Priority: ${incident.urgency.toUpperCase()}.`,
    data: {
      event_type: 'volunteer_assigned',
      incident_id: incident.id,
      urgency: incident.urgency,
    },
  });
}

/**
 * Event-triggered notification: Dispatched when a new chat message arrives.
 * Notifies all other members in the conversation.
 */
export async function notifyNewChatMessage(
  conversationId: string,
  senderId: string,
  senderName: string,
  text: string
): Promise<void> {
  try {
    // Find all other members
    const members = await query<{ user_id: string }>(
      `SELECT user_id FROM conversation_members WHERE conversation_id = $1 AND user_id != $2`,
      [conversationId, senderId]
    );
    if (!members.length) return;

    const userIds = members.map((m) => m.user_id);
    const devices = await query<{ fcm_token: string }>(
      `SELECT fcm_token FROM user_devices WHERE user_id = ANY($1::text[])`,
      [userIds]
    );
    const tokens = devices.map((d) => d.fcm_token);

    await sendMulticast(tokens, {
      title: `${senderName || 'Incident Chat'}`,
      body: text.length > 100 ? `${text.slice(0, 97)}...` : text,
      data: {
        event_type: 'chat_message',
        conversation_id: conversationId,
        sender_id: senderId,
      },
    });
  } catch (err) {
    console.warn('[FCM] Chat notification failed:', (err as Error).message);
  }
}
