import * as admin from 'firebase-admin';
import * as fs from 'fs';
import * as dotenv from 'dotenv';

dotenv.config();

let _initialized = false;

export function initFirebase(): void {
  if (_initialized || admin.apps.length > 0) {
    _initialized = true;
    return;
  }

  let credential: admin.credential.Credential;

  // Prefer inline JSON (CI/Docker) over file path.
  const inlineJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (inlineJson) {
    const serviceAccount = JSON.parse(inlineJson) as admin.ServiceAccount;
    credential = admin.credential.cert(serviceAccount);
  } else {
    const keyPath =
      process.env.FIREBASE_SERVICE_ACCOUNT_PATH ||
      './firebase-service-account.json';
    if (!fs.existsSync(keyPath)) {
      console.warn(
        `[Firebase] Service account key not found at "${keyPath}". ` +
          'Firebase features are disabled.'
      );
      return;
    }
    const serviceAccount = JSON.parse(
      fs.readFileSync(keyPath, 'utf8')
    ) as admin.ServiceAccount;
    credential = admin.credential.cert(serviceAccount);
  }

  admin.initializeApp({
    credential,
    projectId: process.env.FIREBASE_PROJECT_ID,
    storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
  });

  _initialized = true;
  console.info('[Firebase] Admin SDK initialised.');
}

export function getFirestore(): admin.firestore.Firestore {
  return admin.firestore();
}

export function getStorage(): admin.storage.Storage {
  return admin.storage();
}

/**
 * Verifies a Firebase ID token and returns the decoded token.
 * Returns null if Firebase is not initialised or the token is invalid.
 */
export async function verifyIdToken(
  token: string
): Promise<admin.auth.DecodedIdToken | null> {
  if (admin.apps.length === 0) return null;
  try {
    return await admin.auth().verifyIdToken(token);
  } catch {
    return null;
  }
}
