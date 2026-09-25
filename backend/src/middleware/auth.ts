import { Request, Response, NextFunction } from 'express';
import { verifyIdToken } from '../firebase';

/**
 * Express middleware that verifies the Firebase ID token in the
 * `Authorization: Bearer <token>` header.
 *
 * - On success: attaches `req.user` and calls `next()`.
 * - On failure: responds 401.
 * - Demo identity is permitted only with explicit opt-in outside production.
 */
export async function authMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const authHeader = req.headers['authorization'];
  if (!authHeader?.startsWith('Bearer ')) {
    // In development without Firebase, allow anonymous access with a mock user.
    if (process.env.NODE_ENV !== 'production' && process.env.ALLOW_DEMO_AUTH === 'true') {
      (req as Request & { user: unknown }).user = {
        uid: 'dev-user',
        email: 'dev@aidra.app',
        role: 'victim',
        name: 'Dev User',
      };
      next();
      return;
    }
    res.status(401).json({ error: 'Missing or malformed Authorization header.' });
    return;
  }

  const token = authHeader.slice(7);
  let decoded;
  try { decoded = await verifyIdToken(token); } catch { decoded = null; }

  if (!decoded) {
    res.status(401).json({ error: 'Invalid or expired token.' });
    return;
  }

  (req as Request & { user: unknown }).user = {
    uid: decoded.uid,
    email: decoded.email,
    role: (decoded['role'] as string) || 'victim',
    name: decoded.name,
  };

  next();
}

/** Middleware factory: only allow the listed roles through. */
export function requireRole(...roles: string[]) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const user = (req as Request & { user?: { role?: string } }).user;
    if (!user || !roles.includes(user.role || '')) {
      res.status(403).json({
        error: `Access denied. Required role(s): ${roles.join(', ')}.`,
      });
      return;
    }
    next();
  };
}
