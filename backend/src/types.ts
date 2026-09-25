import { z } from 'zod';

// ── Enums (mirror Flutter app_enums.dart) ─────────────────────────────────

export const ReportInputTypeEnum = z.enum(['text', 'voice', 'image', 'video']);
export type ReportInputType = z.infer<typeof ReportInputTypeEnum>;

export const UrgencyLevelEnum = z.enum(['low', 'medium', 'high', 'critical']);
export type UrgencyLevel = z.infer<typeof UrgencyLevelEnum>;

export const ReportStatusEnum = z.enum([
  'queued',
  'submitting',
  'submitted',
  'triaged',
  'verified',
  'assigned',
  'resolved',
  'failed',
]);
export type ReportStatus = z.infer<typeof ReportStatusEnum>;

// ── Zod validation schemas ─────────────────────────────────────────────────

export const MediaAttachmentSchema = z.object({
  id: z.string().uuid(),
  kind: ReportInputTypeEnum,
  mime_type: z.string(),
  storage_key: z.string().optional(),
  local_path: z.string().optional(),
  size_bytes: z.number().int().nonnegative().default(0),
  duration_sec: z.number().int().nonnegative().optional(),
  uploaded: z.boolean().default(false),
});

export const CreateReportSchema = z.object({
  id: z.string().uuid(),
  report_code: z.string().optional(),
  reporter_id: z.string().min(1),
  reporter_name: z.string().optional(),
  input_type: ReportInputTypeEnum,
  description: z.string().min(3).max(2000),
  description_lang: z.string().default('en'),
  transcript: z.string().optional(),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  location_accuracy_m: z.number().nonnegative().optional(),
  address_text: z.string().optional(),
  hazard_type: z.string().optional(),
  people_at_risk: z.number().int().min(0).optional(),
  urgency_user: UrgencyLevelEnum,
  attachments: z.array(MediaAttachmentSchema).default([]),
  is_offline_created: z.boolean().default(false),
  client_created_at: z.string().datetime().optional(),
});

export const UpdateReportStatusSchema = z.object({
  status: ReportStatusEnum,
  assigned_incident_id: z.string().optional(),
});

// ── TypeScript interfaces ──────────────────────────────────────────────────

export interface EmergencyReportRow {
  id: string;
  report_code: string;
  reporter_id: string;
  reporter_name: string | null;
  input_type: ReportInputType;
  description: string;
  description_lang: string;
  transcript: string | null;
  latitude: number;
  longitude: number;
  location_accuracy_m: number | null;
  address_text: string | null;
  hazard_type: string | null;
  people_at_risk: number | null;
  urgency_user: UrgencyLevel;
  urgency_ai: UrgencyLevel | null;
  ai_severity_score: number | null;
  ai_confidence: number | null;
  ai_model_version: string | null;
  ai_entities: Record<string, unknown>;
  ai_needs: Record<string, boolean>;
  status: ReportStatus;
  incident_id: string | null;
  is_offline_created: boolean;
  created_at: Date;
  synced_at: Date | null;
  error_message: string | null;
}

export interface RequestWithUser extends Express.Request {
  user?: {
    uid: string;
    email?: string;
    role?: string;
    name?: string;
  };
}
