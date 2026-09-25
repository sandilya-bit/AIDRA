const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');
require('dotenv').config();

async function main() {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  try {
    await pool.query('CREATE TABLE IF NOT EXISTS aidra_migrations(name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())');
    const dir = path.join(__dirname, '..', 'migrations');
    for (const name of fs.readdirSync(dir).filter((file) => /^\d+_.+\.sql$/.test(file)).sort()) {
      const exists = await pool.query('SELECT 1 FROM aidra_migrations WHERE name=$1', [name]);
      if (exists.rowCount) continue;
      const sql = fs.readFileSync(path.join(dir, name), 'utf8');
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        await client.query(sql);
        await client.query('INSERT INTO aidra_migrations(name) VALUES($1)', [name]);
        await client.query('COMMIT');
        console.info(`[migration] applied ${name}`);
      } catch (error) { await client.query('ROLLBACK'); throw error; }
      finally { client.release(); }
    }
  } finally { await pool.end(); }
}
main().catch((error) => { console.error('[migration] failed:', error.message); process.exitCode = 1; });
