import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { v4 as uuidv4 } from 'uuid';
import { query, queryOne, withTransaction } from '../db';
import { getFirestore } from '../firebase';
import { authMiddleware } from '../middleware/auth';
import { validateBody } from '../middleware/validate';
import { saveFile } from '../services/storage';
import { notifyNewChatMessage } from '../services/notifications';

const router = Router();
router.use(authMiddleware);

// ── Validation Schemas ─────────────────────────────────────────────────────

const CreateConversationSchema = z.object({
  id: z.string().uuid().optional(),
  incident_id: z.string().uuid().optional().nullable(),
  title: z.string().min(1).max(150),
  member_ids: z.array(z.string().min(1)).default([]),
});

const SendMessageSchema = z.object({
  id: z.string().uuid().optional(),
  text: z.string().max(4000).optional().nullable(),
  attachment_url: z.string().url().max(2048).optional().nullable(),
}).refine((data) => (data.text && data.text.trim().length > 0) || (data.attachment_url && data.attachment_url.length > 0), {
  message: 'Either text or attachment_url must be provided.',
});

const MarkReceiptsSchema = z.object({
  message_ids: z.array(z.string().uuid()).min(1).max(100),
});

const UploadChatMediaSchema = z.object({
  data_base64: z.string().min(10),
  mime_type: z.string().min(3).max(100),
  filename: z.string().max(255).optional(),
});

// ── Helpers ────────────────────────────────────────────────────────────────

interface UserSession {
  uid: string;
  name?: string;
  role?: string;
}

function getUser(req: Request): UserSession {
  return (req as Request & { user: UserSession }).user;
}

/** Mirror conversation document to Firestore (best-effort) */
async function syncConversationToFirestore(
  conversationId: string,
  data: Record<string, unknown>
): Promise<void> {
  try {
    const db = getFirestore();
    if (db) {
      await db.collection('conversations').doc(conversationId).set(data, { merge: true });
    }
  } catch {
    // Non-fatal
  }
}

/** Mirror message document to Firestore subcollection (best-effort) */
async function syncMessageToFirestore(
  conversationId: string,
  messageId: string,
  data: Record<string, unknown>
): Promise<void> {
  try {
    const db = getFirestore();
    if (db) {
      await db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .set(data, { merge: true });
    }
  } catch {
    // Non-fatal
  }
}

// ── GET /conversations ─────────────────────────────────────────────────────

router.get('/conversations', async (req: Request, res: Response): Promise<void> => {
  const user = getUser(req);
  const isStaff = ['authority', 'ngo', 'superAdmin'].includes(user.role || '');

  let sql: string;
  let params: unknown[];

  if (isStaff) {
    sql = `
      SELECT c.*,
             COALESCE(json_agg(DISTINCT cm.user_id) FILTER (WHERE cm.user_id IS NOT NULL), '[]') AS member_ids,
             (SELECT count(*)::int FROM chat_messages m WHERE m.conversation_id = c.id) AS message_count,
             (SELECT text FROM chat_messages m WHERE m.conversation_id = c.id ORDER BY m.created_at DESC LIMIT 1) AS last_message
      FROM conversations c
      LEFT JOIN conversation_members cm ON cm.conversation_id = c.id
      GROUP BY c.id
      ORDER BY c.created_at DESC
      LIMIT 100
    `;
    params = [];
  } else {
    sql = `
      SELECT c.*,
             COALESCE(json_agg(DISTINCT cm.user_id) FILTER (WHERE cm.user_id IS NOT NULL), '[]') AS member_ids,
             (SELECT count(*)::int FROM chat_messages m WHERE m.conversation_id = c.id) AS message_count,
             (SELECT text FROM chat_messages m WHERE m.conversation_id = c.id ORDER BY m.created_at DESC LIMIT 1) AS last_message
      FROM conversations c
      INNER JOIN conversation_members current_member ON current_member.conversation_id = c.id AND current_member.user_id = $1
      LEFT JOIN conversation_members cm ON cm.conversation_id = c.id
      GROUP BY c.id
      ORDER BY c.created_at DESC
      LIMIT 100
    `;
    params = [user.uid];
  }

  const rows = await query(sql, params);
  res.json({ items: rows });
});

// ── POST /conversations ────────────────────────────────────────────────────

router.post(
  '/conversations',
  validateBody(CreateConversationSchema),
  async (req: Request, res: Response): Promise<void> => {
    const user = getUser(req);
    const body = req.body as z.infer<typeof CreateConversationSchema>;
    const conversationId = body.id || uuidv4();

    // Check if conversation for this incident already exists
    if (body.incident_id) {
      const existing = await queryOne<{ id: string }>(
        'SELECT id FROM conversations WHERE incident_id = $1 LIMIT 1',
        [body.incident_id]
      );
      if (existing) {
        res.status(200).json({ conversation: existing, existed: true });
        return;
      }
    }

    const members = Array.from(new Set([user.uid, ...body.member_ids]));

    const conversation = await withTransaction(async (client) => {
      const convRes = await client.query(
        `INSERT INTO conversations (id, incident_id, title, created_by, created_at)
         VALUES ($1, $2, $3, $4, NOW())
         RETURNING *`,
        [conversationId, body.incident_id || null, body.title, user.uid]
      );
      const row = convRes.rows[0];

      // Add members
      for (const memberId of members) {
        const role = memberId === user.uid ? (user.role || 'victim') : 'volunteer';
        const safeRole = ['victim', 'volunteer', 'ngo', 'authority'].includes(role) ? role : 'victim';
        await client.query(
          `INSERT INTO conversation_members (conversation_id, user_id, role)
           VALUES ($1, $2, $3)
           ON CONFLICT DO NOTHING`,
          [conversationId, memberId, safeRole]
        );
      }

      return row;
    });

    // Firestore mirror
    await syncConversationToFirestore(conversationId, {
      id: conversationId,
      incident_id: body.incident_id || null,
      title: body.title,
      created_by: user.uid,
      member_ids: members,
      created_at: new Date(),
    });

    res.status(201).json({ conversation: { ...conversation, member_ids: members } });
  }
);

// ── GET /conversations/:id ─────────────────────────────────────────────────

router.get('/conversations/:id', async (req: Request, res: Response): Promise<void> => {
  const user = getUser(req);
  const { id } = req.params;

  const conversation = await queryOne<Record<string, unknown>>(
    'SELECT * FROM conversations WHERE id = $1',
    [id]
  );
  if (!conversation) {
    res.status(404).json({ error: 'Conversation not found.' });
    return;
  }

  const members = await query<{ user_id: string; role: string }>(
    'SELECT user_id, role FROM conversation_members WHERE conversation_id = $1',
    [id]
  );

  const isMember = members.some((m) => m.user_id === user.uid);
  const isStaff = ['authority', 'ngo', 'superAdmin'].includes(user.role || '');
  if (!isMember && !isStaff) {
    res.status(403).json({ error: 'Access denied to this conversation.' });
    return;
  }

  res.json({ conversation: { ...conversation, members } });
});

// ── GET /conversations/:id/messages ────────────────────────────────────────

router.get('/conversations/:id/messages', async (req: Request, res: Response): Promise<void> => {
  const user = getUser(req);
  const { id } = req.params;
  const limit = Math.min(parseInt(String(req.query['limit'] || '100'), 10), 200);

  // Check authorization
  const isStaff = ['authority', 'ngo', 'superAdmin'].includes(user.role || '');
  if (!isStaff) {
    const member = await queryOne(
      'SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2',
      [id, user.uid]
    );
    if (!member) {
      res.status(403).json({ error: 'Access denied.' });
      return;
    }
  }

  const messages = await query<Record<string, unknown>>(
    `SELECT m.*,
            COALESCE(json_agg(DISTINCT cr.user_id) FILTER (WHERE cr.user_id IS NOT NULL), '[]') AS read_by,
            COALESCE(vp.display_name, m.sender_id) AS sender_name
     FROM chat_messages m
     LEFT JOIN chat_receipts cr ON cr.message_id = m.id
     LEFT JOIN volunteer_profiles vp ON vp.user_id = m.sender_id
     WHERE m.conversation_id = $1
     GROUP BY m.id, vp.display_name
     ORDER BY m.created_at ASC
     LIMIT $2`,
    [id, limit]
  );

  res.json({ items: messages });
});

// ── POST /conversations/:id/messages ───────────────────────────────────────

router.post(
  '/conversations/:id/messages',
  validateBody(SendMessageSchema),
  async (req: Request, res: Response): Promise<void> => {
    const user = getUser(req);
    const { id } = req.params;
    const body = req.body as z.infer<typeof SendMessageSchema>;
    const messageId = body.id || uuidv4();

    // Verify conversation existence and membership
    const conversation = await queryOne<{ id: string; title: string }>(
      'SELECT id, title FROM conversations WHERE id = $1',
      [id]
    );
    if (!conversation) {
      res.status(404).json({ error: 'Conversation not found.' });
      return;
    }

    const isStaff = ['authority', 'ngo', 'superAdmin'].includes(user.role || '');
    if (!isStaff) {
      const member = await queryOne(
        'SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2',
        [id, user.uid]
      );
      if (!member) {
        // Automatically enroll the user if they're reporting or involved
        await query(
          `INSERT INTO conversation_members (conversation_id, user_id, role)
           VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
          [id, user.uid, user.role || 'victim']
        );
      }
    }

    const inserted = await withTransaction(async (client) => {
      const msgRes = await client.query(
        `INSERT INTO chat_messages (id, conversation_id, sender_id, text, attachment_url, created_at)
         VALUES ($1, $2, $3, $4, $5, NOW())
         RETURNING *`,
        [messageId, id, user.uid, body.text || null, body.attachment_url || null]
      );
      const msg = msgRes.rows[0];

      // Insert sender's own read receipt
      await client.query(
        `INSERT INTO chat_receipts (message_id, user_id, read_at)
         VALUES ($1, $2, NOW()) ON CONFLICT DO NOTHING`,
        [messageId, user.uid]
      );

      return msg;
    });

    const firestoreMessage = {
      id: messageId,
      conversation_id: id,
      sender_id: user.uid,
      sender_name: user.name || user.uid,
      text: body.text || null,
      attachment_url: body.attachment_url || null,
      created_at: new Date(),
      status: 'sent',
      read_by: [user.uid],
    };

    // Dual-write to Firestore for instant realtime listener sync
    await syncMessageToFirestore(id, messageId, firestoreMessage);

    // Event-triggered push notification to all other conversation members
    if (body.text || body.attachment_url) {
      notifyNewChatMessage(
        id,
        user.uid,
        user.name || 'AIDRA Responder',
        body.text || 'Sent an attachment'
      ).catch((err) => console.warn('[FCM] Push dispatch error:', (err as Error).message));
    }

    res.status(201).json({ message: { ...inserted, read_by: [user.uid] } });
  }
);

// ── POST /conversations/:id/receipts ───────────────────────────────────────

router.post(
  '/conversations/:id/receipts',
  validateBody(MarkReceiptsSchema),
  async (req: Request, res: Response): Promise<void> => {
    const user = getUser(req);
    const { id } = req.params;
    const { message_ids } = req.body as z.infer<typeof MarkReceiptsSchema>;

    for (const msgId of message_ids) {
      await query(
        `INSERT INTO chat_receipts (message_id, user_id, read_at)
         VALUES ($1, $2, NOW())
         ON CONFLICT (message_id, user_id) DO UPDATE SET read_at = NOW()`,
        [msgId, user.uid]
      );

      // Mirror receipt to Firestore
      try {
        const db = getFirestore();
        if (db) {
          const docRef = db
            .collection('conversations')
            .doc(id)
            .collection('messages')
            .doc(msgId);
          await docRef.set(
            {
              read_by: adminFieldUnion(user.uid),
              status: 'read',
            },
            { merge: true }
          );
        }
      } catch {
        // Non-fatal
      }
    }

    res.status(200).json({ success: true, count: message_ids.length });
  }
);

function adminFieldUnion(val: string): unknown {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const admin = require('firebase-admin');
    return admin.firestore.FieldValue.arrayUnion(val);
  } catch {
    return [val];
  }
}

// ── POST /chat/upload ──────────────────────────────────────────────────────

router.post(
  '/upload',
  validateBody(UploadChatMediaSchema),
  async (req: Request, res: Response): Promise<void> => {
    const { data_base64, mime_type, filename } = req.body as z.infer<typeof UploadChatMediaSchema>;

    try {
      const buffer = Buffer.from(data_base64, 'base64');
      const result = await saveFile(buffer, mime_type, filename);
      res.status(201).json(result);
    } catch (err) {
      res.status(400).json({ error: (err as Error).message });
    }
  }
);

export default router;
