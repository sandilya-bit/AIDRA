import { Router, Request, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';

import { query, queryOne, withTransaction } from '../db';
import { getFirestore } from '../firebase';
import { authMiddleware, requireRole } from '../middleware/auth';
import { validateBody } from '../middleware/validate';
import { analyzeReport } from '../services/triage';
import {
  CreateReportSchema,
  UpdateReportStatusSchema,
  EmergencyReportRow,
} from '../types';

const router = Router();

// All report routes require authentication.
router.use(authMiddleware);

// ── Helpers ───────────────────────────────────────────────────────────────

function generateReportCode(): string {
  const year = new Date().getFullYear();
  const seq = Math.floor(100000 + Math.random() * 900000);
  return `AID-${year}-${seq}`;
}

/** Formats a DB row as the JSON payload the Flutter app expects. */
function formatReport(row: EmergencyReportRow, attachments: unknown[] = []): object {
  return {
    id: row.id,
    report_code: row.report_code,
    reporter_id: row.reporter_id,
    reporter_name: row.reporter_name,
    input_type: row.input_type,
    description: row.description,
    description_lang: row.description_lang,
    transcript: row.transcript,
    latitude: parseFloat(String(row.latitude)),
    longitude: parseFloat(String(row.longitude)),
    location_accuracy_m: row.location_accuracy_m,
    address_text: row.address_text,
    hazard_type: row.hazard_type,
    people_at_risk: row.people_at_risk,
    urgency_user: row.urgency_user,
    urgency_ai: row.urgency_ai,
    priority: row.urgency_ai,
    victims: row.people_at_risk,
    type: row.hazard_type,
    summary: typeof row.ai_entities?.summary === 'string' ? row.ai_entities.summary : row.description,
    recommended_action: typeof row.ai_entities?.recommended_action === 'string' ? row.ai_entities.recommended_action : 'coordinator_review',
    ai_severity_score: row.ai_severity_score,
    ai_confidence: row.ai_confidence,
    ai_model_version: row.ai_model_version,
    ai_entities: row.ai_entities,
    ai_needs: row.ai_needs,
    status: row.status,
    incident_id: row.incident_id,
    is_offline_created: row.is_offline_created,
    created_at: row.created_at,
    synced_at: row.synced_at,
    error_message: row.error_message,
    attachments,
  };
}

/** Writes/updates the Firestore mirror of the report (best-effort). */
async function syncToFirestore(
  reportId: string,
  data: Record<string, unknown>
): Promise<void> {
  try {
    const db = getFirestore();
    await db
      .collection('emergency_reports')
      .doc(reportId)
      .set(data, { merge: true });
  } catch {
    // Fire-and-forget — Firestore errors must never fail the HTTP response.
  }
}

// ── POST /reports ─────────────────────────────────────────────────────────

router.post(
  '/',
  validateBody(CreateReportSchema),
  async (req: Request, res: Response): Promise<void> => {
    const body = req.body as typeof CreateReportSchema._type;
    const user = (req as Request & { user?: { uid: string; name?: string } }).user;
    if (user && body.reporter_id !== user.uid && !['authority', 'superAdmin'].includes((user as { role?: string }).role || '')) {
      res.status(403).json({ error: 'Reports may only be submitted for the authenticated user.' });
      return;
    }

    // Idempotency: check if report with this id already exists.
    if (body.id) {
      const existing = await queryOne<EmergencyReportRow>(
        'SELECT * FROM emergency_reports WHERE id = $1',
        [body.id]
      );
      if (existing) {
        res.status(200).json({ report: formatReport(existing) });
        return;
      }
    }

    const reportId = body.id || uuidv4();
    const reportCode = body.report_code || generateReportCode();

    // Run triage.
    const triage = await analyzeReport({
      description: body.description,
      urgencyUser: body.urgency_user,
      peopleAtRisk: body.people_at_risk,
      inputType: body.input_type,
    });

    // Persist to PostgreSQL inside a transaction.
    const insertedReport = await withTransaction(async (client) => {
      const reportRow = await client.query<EmergencyReportRow>(
        `INSERT INTO emergency_reports (
          id, report_code, reporter_id, reporter_name,
          input_type, description, description_lang, transcript,
          latitude, longitude, location_accuracy_m, address_text,
          hazard_type, people_at_risk,
          urgency_user, urgency_ai, ai_severity_score, ai_confidence,
          ai_model_version, ai_entities, ai_needs,
          status, is_offline_created, synced_at
        ) VALUES (
          $1, $2, $3, $4,
          $5, $6, $7, $8,
          $9, $10, $11, $12,
          $13, $14,
          $15, $16, $17, $18,
          $19, $20, $21,
          'submitted', $22, NOW()
        )
        RETURNING *`,
        [
          reportId,
          reportCode,
          body.reporter_id,
          body.reporter_name || user?.name || null,
          body.input_type,
          body.description,
          body.description_lang || 'en',
          body.transcript || null,
          body.latitude,
          body.longitude,
          body.location_accuracy_m || null,
          body.address_text || null,
          body.hazard_type || (typeof triage.aiEntities.type === 'string' ? triage.aiEntities.type : null),
          (typeof triage.aiEntities.victims === 'number' ? triage.aiEntities.victims : body.people_at_risk) ?? null,
          body.urgency_user,
          triage.urgencyAi,
          triage.aiSeverityScore,
          triage.aiConfidence,
          triage.aiModelVersion,
          JSON.stringify({ ...triage.aiEntities, summary: triage.summary, recommended_action: triage.recommendedAction }),
          JSON.stringify(triage.aiNeeds),
          body.is_offline_created,
        ]
      );

      const savedReport = reportRow.rows[0];

      // Insert attachments.
      if (body.attachments && body.attachments.length > 0) {
        for (const att of body.attachments) {
          await client.query(
            `INSERT INTO report_attachments
              (id, report_id, kind, mime_type, storage_key, local_path, size_bytes, duration_sec, uploaded)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
             ON CONFLICT (id) DO NOTHING`,
            [
              att.id || uuidv4(),
              reportId,
              att.kind,
              att.mime_type,
              att.storage_key || null,
              att.local_path || null,
              att.size_bytes || 0,
              att.duration_sec || null,
              att.uploaded || false,
            ]
          );
        }
      }

      return savedReport;
    });

    // Dual-write to Firestore (best-effort, does not fail the request).
    const firestoreData: Record<string, unknown> = {
      id: insertedReport.id,
      report_code: insertedReport.report_code,
      reporter_id: insertedReport.reporter_id,
      input_type: insertedReport.input_type,
      description: insertedReport.description,
      latitude: insertedReport.latitude,
      longitude: insertedReport.longitude,
      people_at_risk: insertedReport.people_at_risk,
      urgency_user: insertedReport.urgency_user,
      urgency_ai: insertedReport.urgency_ai,
      ai_entities: insertedReport.ai_entities,
      ai_needs: insertedReport.ai_needs,
      ai_severity_score: insertedReport.ai_severity_score,
      status: insertedReport.status,
      created_at: insertedReport.created_at,
    };
    syncToFirestore(reportId, firestoreData);
    // Topic subscribers (authority command centers) receive new incident alerts.
    try {
      const admin = await import('firebase-admin');
      if (admin.apps.length) await admin.messaging().send({
        topic: 'aidra_authorities',
        notification: { title: `New ${triage.urgencyAi} emergency`, body: String(triage.summary || body.description).slice(0, 180) },
        data: { report_id: reportId, type: 'emergency_created', priority: triage.urgencyAi },
      });
    } catch (error) { console.warn('[FCM] New report notification was not delivered:', (error as Error).message); }

    const formatted = formatReport(insertedReport, body.attachments || []);
    res.status(201).json({ report: formatted });
  }
);

// ── GET /reports ──────────────────────────────────────────────────────────

router.get('/', async (req: Request, res: Response): Promise<void> => {
  const user = (req as Request & { user?: { uid: string; role?: string } }).user;
  const isAdmin = ['authority', 'ngo', 'superAdmin'].includes(user?.role || '');
  const scope = req.query['scope'];
  const limit = Math.min(parseInt(String(req.query['limit'] || '100'), 10), 500);

  let reports: EmergencyReportRow[];

  if (isAdmin && scope === 'all') {
    reports = await query<EmergencyReportRow>(
      `SELECT er.*, 
              COALESCE(
                json_agg(ra.*) FILTER (WHERE ra.id IS NOT NULL),
                '[]'
              ) AS attachments
       FROM emergency_reports er
       LEFT JOIN report_attachments ra ON ra.report_id = er.id
       GROUP BY er.id
       ORDER BY er.created_at DESC
       LIMIT $1`,
      [limit]
    );
  } else {
    reports = await query<EmergencyReportRow>(
      `SELECT er.*,
              COALESCE(
                json_agg(ra.*) FILTER (WHERE ra.id IS NOT NULL),
                '[]'
              ) AS attachments
       FROM emergency_reports er
       LEFT JOIN report_attachments ra ON ra.report_id = er.id
       WHERE er.reporter_id = $1
       GROUP BY er.id
       ORDER BY er.created_at DESC
       LIMIT $2`,
      [user?.uid, limit]
    );
  }

  res.json({ items: reports.map((r) => formatReport(r)) });
});

// ── GET /reports/:id ──────────────────────────────────────────────────────

router.get('/:id', async (req: Request, res: Response): Promise<void> => {
  const user = (req as Request & { user?: { uid: string; role?: string } }).user;
  const { id } = req.params;

  const report = await queryOne<EmergencyReportRow>(
    'SELECT * FROM emergency_reports WHERE id = $1',
    [id]
  );

  if (!report) {
    res.status(404).json({ error: 'Report not found.' });
    return;
  }

  const isAdmin = ['authority', 'ngo', 'superAdmin'].includes(user?.role || '');
  if (!isAdmin && report.reporter_id !== user?.uid) {
    res.status(403).json({ error: 'Access denied.' });
    return;
  }

  const attachments = await query(
    'SELECT * FROM report_attachments WHERE report_id = $1 ORDER BY created_at',
    [id]
  );

  res.json({ report: formatReport(report, attachments) });
});

// ── PATCH /reports/:id/status ─────────────────────────────────────────────

router.patch(
  '/:id/status',
  requireRole('authority', 'ngo', 'superAdmin', 'volunteer'),
  validateBody(UpdateReportStatusSchema),
  async (req: Request, res: Response): Promise<void> => {
    const { id } = req.params;
    const { status, assigned_incident_id } = req.body as {
      status: string;
      assigned_incident_id?: string;
    };

    const updated = await queryOne<EmergencyReportRow>(
      `UPDATE emergency_reports
       SET status = $1, incident_id = COALESCE($2::uuid, incident_id)
       WHERE id = $3
       RETURNING *`,
      [status, assigned_incident_id || null, id]
    );

    if (!updated) {
      res.status(404).json({ error: 'Report not found.' });
      return;
    }

    // Mirror status change to Firestore.
    syncToFirestore(id, { status, updated_at: new Date() });

    res.json({ report: formatReport(updated) });
  }
);

export default router;
