import * as fs from 'fs';
import * as path from 'path';
import { v4 as uuidv4 } from 'uuid';
import { getStorage } from '../firebase';

export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024; // 10 MB limit

export const ALLOWED_MIME_TYPES = new Set([
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/webp',
  'image/gif',
  'audio/mpeg',
  'audio/mp4',
  'audio/wav',
  'audio/x-m4a',
  'audio/m4a',
  'audio/aac',
  'application/pdf',
]);

const UPLOADS_DIR = path.resolve(process.cwd(), 'uploads');

function ensureUploadsDir(): void {
  if (!fs.existsSync(UPLOADS_DIR)) {
    fs.mkdirSync(UPLOADS_DIR, { recursive: true });
  }
}

/**
 * Validates file buffer, size, and mime type.
 */
export function validateUpload(
  buffer: Buffer,
  mimeType: string
): { valid: boolean; error?: string } {
  if (!buffer || buffer.length === 0) {
    return { valid: false, error: 'Empty file payload.' };
  }
  if (buffer.length > MAX_UPLOAD_BYTES) {
    return {
      valid: false,
      error: `File size ${buffer.length} exceeds maximum limit of ${MAX_UPLOAD_BYTES} bytes (10MB).`,
    };
  }
  const normalizedMime = mimeType.toLowerCase().trim();
  if (!ALLOWED_MIME_TYPES.has(normalizedMime)) {
    return {
      valid: false,
      error: `Unsupported MIME type: "${mimeType}". Allowed: ${Array.from(ALLOWED_MIME_TYPES).join(', ')}`,
    };
  }
  return { valid: true };
}

/**
 * Generates a signed download URL for a given Firebase Storage path.
 * Returns null when Firebase is not configured (development without credentials).
 */
export async function getSignedUrl(storagePath: string): Promise<string | null> {
  try {
    const bucket = getStorage().bucket();
    const file = bucket.file(storagePath);
    const [url] = await file.getSignedUrl({
      action: 'read',
      expires: Date.now() + 60 * 60 * 1000, // 1 hour
    });
    return url;
  } catch {
    return null;
  }
}

export interface UploadResult {
  url: string;
  storageKey: string;
  mimeType: string;
  sizeBytes: number;
  isLocal: boolean;
}

/**
 * Saves an uploaded file buffer.
 * If Firebase Storage is available, uploads to the cloud bucket.
 * Otherwise, falls back to the local uploads directory for development/offline mode.
 */
export async function saveFile(
  buffer: Buffer,
  mimeType: string,
  originalName?: string
): Promise<UploadResult> {
  const validation = validateUpload(buffer, mimeType);
  if (!validation.valid) {
    throw new Error(validation.error);
  }

  const ext = getExtensionFromMime(mimeType) || path.extname(originalName || '').toLowerCase() || '.bin';
  const fileId = uuidv4();
  const safeFilename = `${fileId}${ext}`;
  const storageKey = `chat_attachments/${safeFilename}`;

  // Attempt Firebase Cloud Storage upload first
  try {
    const storage = getStorage();
    if (storage && process.env.FIREBASE_STORAGE_BUCKET) {
      const bucket = storage.bucket();
      const file = bucket.file(storageKey);
      await file.save(buffer, {
        metadata: {
          contentType: mimeType,
          metadata: {
            originalName: originalName || safeFilename,
            uploadedAt: new Date().toISOString(),
          },
        },
      });

      const signedUrl = await getSignedUrl(storageKey);
      return {
        url: signedUrl || `https://storage.googleapis.com/${bucket.name}/${storageKey}`,
        storageKey,
        mimeType,
        sizeBytes: buffer.length,
        isLocal: false,
      };
    }
  } catch (err) {
    console.warn('[Storage] Firebase upload bypassed or failed, using local storage fallback:', (err as Error).message);
  }

  // Fallback to local uploads directory
  ensureUploadsDir();
  const localFilePath = path.join(UPLOADS_DIR, safeFilename);
  fs.writeFileSync(localFilePath, buffer);

  const localUrl = `/uploads/${safeFilename}`;
  return {
    url: localUrl,
    storageKey: safeFilename,
    mimeType,
    sizeBytes: buffer.length,
    isLocal: true,
  };
}

function getExtensionFromMime(mime: string): string {
  switch (mime.toLowerCase().trim()) {
    case 'image/jpeg':
    case 'image/jpg':
      return '.jpg';
    case 'image/png':
      return '.png';
    case 'image/webp':
      return '.webp';
    case 'image/gif':
      return '.gif';
    case 'audio/mpeg':
      return '.mp3';
    case 'audio/mp4':
    case 'audio/x-m4a':
    case 'audio/m4a':
      return '.m4a';
    case 'audio/wav':
      return '.wav';
    case 'audio/aac':
      return '.aac';
    case 'application/pdf':
      return '.pdf';
    default:
      return '';
  }
}
