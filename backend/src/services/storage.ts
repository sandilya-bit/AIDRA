import { getStorage } from '../firebase';

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
