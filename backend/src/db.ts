import { Pool, PoolClient } from 'pg';
import * as dotenv from 'dotenv';

dotenv.config();

const connectionString = process.env.DATABASE_URL;

export const pool = new Pool(
  connectionString
    ? {
        connectionString,
        ssl:
          process.env.PG_SSL === 'true'
            ? { rejectUnauthorized: false }
            : false,
      }
    : {
        host: process.env.PG_HOST || 'localhost',
        port: parseInt(process.env.PG_PORT || '5432', 10),
        database: process.env.PG_DATABASE || 'aidra',
        user: process.env.PG_USER || 'postgres',
        password: process.env.PG_PASSWORD || '',
        ssl:
          process.env.PG_SSL === 'true'
            ? { rejectUnauthorized: false }
            : false,
      }
);

/** Run a query and return all rows. */
export async function query<T extends object = Record<string, unknown>>(
  text: string,
  values?: unknown[]
): Promise<T[]> {
  const result = await pool.query<T>(text, values);
  return result.rows;
}

/** Run a query and return the first row (or undefined). */
export async function queryOne<T extends object = Record<string, unknown>>(
  text: string,
  values?: unknown[]
): Promise<T | undefined> {
  const result = await pool.query<T>(text, values);
  return result.rows[0];
}

/** Execute within a transaction. */
export async function withTransaction<T>(
  fn: (client: PoolClient) => Promise<T>
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/** Verify the connection on startup. */
export async function checkConnection(): Promise<void> {
  const client = await pool.connect();
  await client.query('SELECT 1');
  client.release();
}
