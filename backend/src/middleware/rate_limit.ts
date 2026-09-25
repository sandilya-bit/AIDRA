import { Request, Response, NextFunction } from 'express';
import { createHash } from 'node:crypto';
import { pool } from '../db';

/** Shared PostgreSQL limiter (works across backend instances). Dev-only memory fallback allows startup before migrations. */
export function createRateLimiter(windowMs = 60_000, max = 120) {
  const buckets = new Map<string, { count: number; resetAt: number }>();
  const timer = setInterval(() => {
    const now = Date.now();
    for (const [key, value] of buckets) if (value.resetAt <= now) buckets.delete(key);
  }, windowMs);
  timer.unref();
  const cleanup = setInterval(() => {
    void pool.query("DELETE FROM api_rate_limit_buckets WHERE reset_at < now() - interval '1 day'").catch(() => undefined);
  }, 60 * 60 * 1000);
  cleanup.unref();
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const identity = req.ip || req.socket.remoteAddress || 'unknown';
    const key = createHash('sha256').update(identity).digest('hex');
    const now = Date.now();
    let count: number;
    let resetAt: number;
    try {
      const result = await pool.query<{count:number;reset_at:Date}>(
        `INSERT INTO api_rate_limit_buckets(bucket_key,request_count,reset_at)
         VALUES($1,1,now()+($2::text||' milliseconds')::interval)
         ON CONFLICT(bucket_key) DO UPDATE SET
           request_count=CASE WHEN api_rate_limit_buckets.reset_at<=now() THEN 1 ELSE api_rate_limit_buckets.request_count+1 END,
           reset_at=CASE WHEN api_rate_limit_buckets.reset_at<=now() THEN now()+($2::text||' milliseconds')::interval ELSE api_rate_limit_buckets.reset_at END
         RETURNING request_count AS count,reset_at`, [key,windowMs]);
      count = result.rows[0].count;
      resetAt = new Date(result.rows[0].reset_at).getTime();
    } catch (error) {
      if (process.env.NODE_ENV === 'production') {
        res.status(503).json({error:'Request protection is temporarily unavailable.'});
        return;
      }
      const bucket = buckets.get(key);
      const current = !bucket || bucket.resetAt <= now ? { count: 0, resetAt: now + windowMs } : bucket;
      current.count += 1;
      buckets.set(key, current);
      count = current.count;
      resetAt = current.resetAt;
    }
    res.setHeader('RateLimit-Limit', String(max));
    res.setHeader('RateLimit-Remaining', String(Math.max(0, max - count)));
    if (count > max) {
      res.setHeader('Retry-After', String(Math.ceil((resetAt - now) / 1000)));
      res.status(429).json({ error: 'Too many requests. Please retry shortly.' });
      return;
    }
    next();
  };
}
