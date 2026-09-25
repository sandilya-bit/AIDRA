import express, { Application, Request, Response, NextFunction } from 'express';
import helmet from 'helmet';
import cors from 'cors';
import morgan from 'morgan';
import * as dotenv from 'dotenv';

import { checkConnection } from './db';
import { initFirebase } from './firebase';
import reportsRouter from './routes/reports';
import operationsRouter from './routes/operations';
import { createRateLimiter } from './middleware/rate_limit';

dotenv.config();

const app: Application = express();
const PORT = parseInt(process.env.PORT || '3000', 10);

// ── Security + parsing middleware ─────────────────────────────────────────
app.use(helmet());
app.use(
  cors({
    origin: (process.env.CORS_ORIGINS || 'http://localhost:3000,http://localhost:5173').split(',').map((value) => value.trim()),
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: [
      'Content-Type',
      'Authorization',
      'Idempotency-Key',
      'X-Request-Id',
    ],
    credentials: true,
  })
);
app.use(express.json({ limit: '5mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev'));
app.use(createRateLimiter());

// ── Health check ──────────────────────────────────────────────────────────
app.get('/health', (_req: Request, res: Response) => {
  res.json({
    status: 'ok',
    service: 'aidra-backend',
    version: process.env.npm_package_version || '1.0.0',
    timestamp: new Date().toISOString(),
  });
});

// ── API routes ────────────────────────────────────────────────────────────
app.use('/v1/reports', reportsRouter);
app.use('/v1', operationsRouter);

// ── 404 handler ───────────────────────────────────────────────────────────
app.use((_req: Request, res: Response) => {
  res.status(404).json({ error: 'Route not found.' });
});

// ── Global error handler ──────────────────────────────────────────────────
// eslint-disable-next-line @typescript-eslint/no-unused-vars
app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
  console.error('[Unhandled Error]', err);
  res.status(500).json({
    error: 'An unexpected error occurred.',
    ...(process.env.NODE_ENV !== 'production' && { detail: err.message }),
  });
});

// ── Bootstrap ─────────────────────────────────────────────────────────────
async function bootstrap(): Promise<void> {
  // Initialise Firebase Admin (non-fatal if credentials are missing in dev).
  initFirebase();

  // Verify database connection.
  try {
    await checkConnection();
    console.info('[DB] PostgreSQL connection established.');
  } catch (err) {
    console.warn(
      '[DB] Could not connect to PostgreSQL. Starting without DB:',
      (err as Error).message
    );
  }

  app.listen(PORT, () => {
    console.info(
      `[AIDRA Backend] Listening on http://localhost:${PORT} (${process.env.NODE_ENV || 'development'})`
    );
  });
}

bootstrap().catch((err) => {
  console.error('[Fatal] Bootstrap failed:', err);
  process.exit(1);
});

export default app;
