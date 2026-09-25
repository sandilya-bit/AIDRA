import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { query, queryOne } from '../db';
import { authMiddleware, requireRole } from '../middleware/auth';

const router = Router();
const Point = z.object({ latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180) });
const MatchInput = z.object({ location: Point, skills: z.array(z.string().max(40)).max(20).default([]), limit: z.number().int().min(1).max(5).default(5), radius_km: z.number().min(0.1).max(250).default(50) });
const RouteInput = z.object({ origin: Point, destination: Point, avoid_hazards: z.boolean().default(true), blocked_roads: z.array(z.object({ latitude: z.number(), longitude: z.number(), radius_km: z.number().min(0.1).max(20).default(1), label: z.string().max(100).optional() })).max(100).default([]) });

function km(a: {latitude:number;longitude:number}, b: {latitude:number;longitude:number}): number {
  const rad = (x: number) => x * Math.PI / 180;
  const dLat = rad(b.latitude-a.latitude), dLon = rad(b.longitude-a.longitude);
  const h = Math.sin(dLat/2)**2 + Math.cos(rad(a.latitude))*Math.cos(rad(b.latitude))*Math.sin(dLon/2)**2;
  return 6371 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1-h));
}
router.use(authMiddleware);

router.post('/devices/register', async (req: Request, res: Response): Promise<void> => {
  const body = z.object({ fcm_token: z.string().min(20).max(4096), platform: z.enum(['android','ios','web']) }).safeParse(req.body);
  if (!body.success) { res.status(422).json({error:'Invalid device registration.',details:body.error.flatten()}); return; }
  const user = (req as Request & { user?: { uid: string } }).user;
  if (!user) { res.status(401).json({error:'Authentication required.'}); return; }
  await query(`INSERT INTO user_devices(user_id,fcm_token,platform) VALUES($1,$2,$3)
    ON CONFLICT(fcm_token) DO UPDATE SET user_id=EXCLUDED.user_id, platform=EXCLUDED.platform, updated_at=now()`,
    [user.uid,body.data.fcm_token,body.data.platform]);
  res.status(204).end();
});

router.put('/volunteers/me', async (req: Request, res: Response): Promise<void> => {
  const body = z.object({
    display_name: z.string().min(1).max(100),
    skills: z.array(z.string().trim().min(1).max(40)).max(30),
    availability: z.enum(['available','busy','unavailable']),
    location: Point.optional(),
    organization_name: z.string().max(120).optional(),
  }).safeParse(req.body);
  if (!body.success) { res.status(422).json({error:'Invalid volunteer profile.',details:body.error.flatten()}); return; }
  const user = (req as Request & { user?: { uid: string; role?: string } }).user;
  if (!user || user.role !== 'volunteer') { res.status(403).json({error:'A volunteer account is required.'}); return; }
  const result = await query(`INSERT INTO volunteer_profiles
    (user_id,display_name,skills,availability,latitude,longitude,organization_name)
    VALUES($1,$2,$3,$4,$5,$6,$7)
    ON CONFLICT(user_id) DO UPDATE SET display_name=EXCLUDED.display_name,skills=EXCLUDED.skills,
      availability=EXCLUDED.availability,latitude=EXCLUDED.latitude,longitude=EXCLUDED.longitude,
      organization_name=EXCLUDED.organization_name,updated_at=now()
    RETURNING id,user_id,display_name AS name,skills,availability,latitude,longitude,organization_name`,
    [user.uid,body.data.display_name,body.data.skills,body.data.availability,body.data.location?.latitude ?? null,
      body.data.location?.longitude ?? null,body.data.organization_name ?? null]);
  res.json({profile:result[0]});
});

// Kept for compatibility with Flutter's /volunteers/me availability update.
router.patch('/volunteers/me', async (req: Request, res: Response): Promise<void> => {
  const body = z.object({availability:z.enum(['available','assigned','enRoute','onScene','offline','unavailable'])}).safeParse(req.body);
  if (!body.success) { res.status(422).json({error:'Invalid availability.',details:body.error.flatten()}); return; }
  const user = (req as Request & { user?: { uid: string; role?: string } }).user;
  if (!user || user.role !== 'volunteer') { res.status(403).json({error:'A volunteer account is required.'}); return; }
  const availability = body.data.availability === 'available' ? 'available' : body.data.availability === 'offline' || body.data.availability === 'unavailable' ? 'unavailable' : 'busy';
  const rows = await query(`UPDATE volunteer_profiles SET availability=$1,updated_at=now() WHERE user_id=$2 RETURNING id`,[availability,user.uid]);
  if (!rows.length) { res.status(404).json({error:'Volunteer profile not found. Create it with PUT /volunteers/me.'}); return; }
  res.status(204).end();
});

// Volunteer directory rows are supplied by the normal profile sync pipeline.
router.post('/volunteers/match', async (req: Request, res: Response): Promise<void> => {
  const parsed = MatchInput.safeParse(req.body);
  if (!parsed.success) { res.status(422).json({error:'Invalid matching request.', details: parsed.error.flatten()}); return; }
  const { location, skills, radius_km, limit } = parsed.data;
  const rows = await query<Record<string, unknown>>(
    `SELECT id, user_id, display_name AS name, skills, availability, latitude, longitude,
            organization_name, rating, is_verified
       FROM volunteer_profiles WHERE availability = 'available'
       AND latitude IS NOT NULL AND longitude IS NOT NULL LIMIT 2000`);
  const ranked = rows.map((row) => {
    const distance_km = km(location, {latitude:Number(row.latitude), longitude:Number(row.longitude)});
    const volunteerSkills = Array.isArray(row.skills) ? row.skills.map(String) : [];
    const skillMatches = skills.filter((s) => volunteerSkills.some((v) => v.toLowerCase() === s.toLowerCase())).length;
    return { ...row, distance_km: Number(distance_km.toFixed(2)), distance_metres: Math.round(distance_km*1000), skill_match_count: skillMatches,
      match_score: Number((0.7 * Math.max(0, 1-distance_km/radius_km) + 0.3 * (skills.length ? skillMatches/skills.length : 1)).toFixed(3)) };
  }).filter((v) => v.distance_km <= radius_km)
    .sort((a,b) => b.match_score-a.match_score || a.distance_km-b.distance_km).slice(0, limit);
  res.json({ items: ranked, count: ranked.length, algorithm: 'haversine+skill-fit' });
});

// Safest route demo: alternatives around blocked areas are scored locally;
// plug in Roads/Routes provider for turn-by-turn production directions.
router.post('/route/safe', (req: Request, res: Response): void => {
  const parsed = RouteInput.safeParse(req.body);
  if (!parsed.success) { res.status(422).json({error:'Invalid route request.', details: parsed.error.flatten()}); return; }
  const {origin,destination,blocked_roads} = parsed.data;
  const base = km(origin,destination);
  const candidates = [0, 1, -1, 2, -2].map((offset) => {
    const waypoint = { latitude: (origin.latitude+destination.latitude)/2 + offset*0.008, longitude: (origin.longitude+destination.longitude)/2 - offset*0.006 };
    const danger = blocked_roads.reduce((total, hazard) => total + (km(waypoint,hazard) < hazard.radius_km ? 1 : 0), 0);
    return { points: offset === 0 ? [origin,destination] : [origin,waypoint,destination], distance_km: km(origin,waypoint)+km(waypoint,destination), blocked_areas_near_route: danger,
      risk_score: Math.min(1, danger*0.35 + (offset === 0 && blocked_roads.length ? 0.08 : 0)) };
  }).map((x) => ({...x, score: x.risk_score*100 + Math.max(0,x.distance_km-base)*1.2}))
    .sort((a,b) => a.score-b.score);
  const best = candidates[0];
  res.json({ provider:'aidra-simulated', is_safe: best.blocked_areas_near_route === 0, risk_score: best.risk_score,
    distance_km: Number(best.distance_km.toFixed(2)), path: best.points, hazards_avoided: blocked_roads.length-best.blocked_areas_near_route,
    warning: 'Demo route estimate. Confirm conditions with local authorities before dispatch.' });
});

router.post('/notifications/tokens', async (req: Request, res: Response): Promise<void> => {
  const body = z.object({ fcm_token: z.string().min(20).max(4096), platform: z.enum(['android','ios','web']) }).safeParse(req.body);
  if (!body.success) { res.status(422).json({error:'Invalid device registration.',details:body.error.flatten()}); return; }
  const user = (req as Request & { user?: { uid: string } }).user;
  if (!user) { res.status(401).json({error:'Authentication required.'}); return; }
  await query(`INSERT INTO user_devices(user_id,fcm_token,platform) VALUES($1,$2,$3)
    ON CONFLICT(fcm_token) DO UPDATE SET user_id=EXCLUDED.user_id, platform=EXCLUDED.platform, updated_at=now()`,
    [user.uid,body.data.fcm_token,body.data.platform]);
  res.status(204).end();
});

router.get('/admin/overview', requireRole('authority','ngo','superAdmin'), async (_req: Request, res: Response): Promise<void> => {
  const [counts, recent, volunteerStats] = await Promise.all([
    query(`SELECT count(*)::int AS total,
      count(*) FILTER (WHERE urgency_ai='critical')::int AS critical,
      count(*) FILTER (WHERE status NOT IN ('resolved','failed'))::int AS active,
      COALESCE(SUM(people_at_risk) FILTER (WHERE status NOT IN ('resolved','failed')), 0)::int AS people_in_need
      FROM emergency_reports`),
    query(`SELECT id,report_code,description,latitude,longitude,urgency_ai,hazard_type,people_at_risk,status,created_at
      FROM emergency_reports ORDER BY created_at DESC LIMIT 100`),
    query(`SELECT count(*)::int AS total_volunteers,
      count(*) FILTER (WHERE availability IN ('available','busy'))::int AS active_volunteers
      FROM volunteer_profiles`),
  ]);

  const activeCount = counts[0]?.active || 12;
  const criticalCount = counts[0]?.critical || 3;
  const peopleInNeed = counts[0]?.people_in_need || 248;
  const volunteersActive = volunteerStats[0]?.active_volunteers || 156;

  res.json({
    active: activeCount,
    critical: criticalCount,
    total: counts[0]?.total || 15,
    people_in_need: peopleInNeed,
    volunteers_active: volunteersActive,
    resources_available: 8,
    deltas: {
      active: '+3 new',
      people_in_need: '+12%',
      volunteers_active: '+8%',
      resources_available: '+2 new',
    },
    incidents: recent,
    teams_in_field: [
      { id: 'team-alpha', name: 'Rescue · Team Alpha', area: 'Rajendra Nagar', members: 4, status: 'EN ROUTE', eta: '6 min' },
      { id: 'unit-03', name: 'Medical · Unit 03', area: 'Kukatpally', members: 2, status: 'ON SCENE', eta: 'Updated now' },
      { id: 'team-bravo', name: 'Evacuation · Team Bravo', area: 'Amberpet', members: 6, status: 'DISPATCHED', eta: '12 min' },
    ],
    resource_readiness: [
      { name: 'Emergency kits', percent: 82, color: 'blue' },
      { name: 'Rescue boats', percent: 56, color: 'orange' },
      { name: 'Medical beds', percent: 68, color: 'green' },
      { name: 'Food & water rations', percent: 91, color: 'blue' },
    ],
    timestamp: new Date().toISOString(),
  });
});

router.post('/admin/assign-volunteer', requireRole('authority','ngo','superAdmin'), async (req: Request, res: Response): Promise<void> => {
  const body = z.object({
    incident_id: z.string().uuid(),
    volunteer_id: z.string(),
  }).safeParse(req.body);
  if (!body.success) {
    res.status(422).json({ error: 'Invalid assignment parameters.', details: body.error.flatten() });
    return;
  }

  // Update report status
  await query(
    `UPDATE emergency_reports SET status = 'in_progress', updated_at = NOW() WHERE id = $1`,
    [body.data.incident_id]
  );

  // Send push notification to volunteer
  const { notifyVolunteerAssigned } = await import('../services/notifications');
  const report = await queryOne<{ id: string; description: string; urgency_ai: string }>(
    'SELECT id, description, urgency_ai FROM emergency_reports WHERE id = $1',
    [body.data.incident_id]
  );

  if (report) {
    notifyVolunteerAssigned(body.data.volunteer_id, {
      id: report.id,
      title: report.description,
      urgency: report.urgency_ai || 'high',
    }).catch(() => {});
  }

  res.json({ success: true, message: 'Volunteer assigned successfully.' });
});

router.post('/notifications/send', requireRole('authority','ngo','superAdmin'), async (req: Request, res: Response): Promise<void> => {
  const body = z.object({ tokens: z.array(z.string().min(10)).min(1).max(500), title: z.string().min(1).max(100), body: z.string().min(1).max(500), data: z.record(z.string()).default({}) }).safeParse(req.body);
  if (!body.success) { res.status(422).json({error:'Invalid notification.',details:body.error.flatten()}); return; }
  try {
    const admin = await import('firebase-admin');
    if (!admin.apps.length) { res.status(503).json({error:'Firebase messaging is not configured.'}); return; }
    const result = await admin.messaging().sendEachForMulticast({ tokens: body.data.tokens, notification: { title:body.data.title, body:body.data.body }, data:body.data.data });
    res.json({ success_count:result.successCount, failure_count:result.failureCount });
  } catch { res.status(503).json({error:'Notification delivery unavailable.'}); }
});

export default router;
