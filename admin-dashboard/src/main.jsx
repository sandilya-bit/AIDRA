import React, { useState, useEffect, useCallback } from 'react';
import { createRoot } from 'react-dom/client';
import {
  Shield,
  Activity,
  AlertTriangle,
  Users,
  HeartPulse,
  Package,
  MapPin,
  Building2,
  FileText,
  BarChart3,
  Settings,
  Search,
  Bell,
  Moon,
  Sun,
  RefreshCw,
  Radio,
  Clock,
  CheckCircle2,
  Navigation,
  Sparkles,
  ArrowRight,
  ExternalLink,
  ChevronRight,
  Play,
  Share2,
} from 'lucide-react';
import './style.css';

const DEFAULT_INCIDENTS = [
  {
    id: 'inc-1',
    report_code: 'AID-26-008421',
    description: 'Building Collapse — 2 people trapped',
    place: '2.4 km · Rajendra Nagar Sector 4',
    urgency_ai: 'high',
    people_at_risk: 2,
    created_at: '10:32 AM',
    latitude: 17.3850,
    longitude: 78.4867,
    status: 'assigned',
    x: 48,
    y: 44,
  },
  {
    id: 'inc-2',
    report_code: 'AID-26-008420',
    description: 'Flood Rescue — 5 people trapped near river',
    place: '4.8 km · Musi River Bank Corridor',
    urgency_ai: 'critical',
    people_at_risk: 5,
    created_at: '09:47 AM',
    latitude: 17.3910,
    longitude: 78.4720,
    status: 'submitted',
    x: 42,
    y: 50,
  },
  {
    id: 'inc-3',
    report_code: 'AID-26-008416',
    description: 'Road Blocked — Heavy waterlogging & debris',
    place: '6.2 km · Outer Ring Road Junction',
    urgency_ai: 'medium',
    people_at_risk: 0,
    created_at: '08:15 AM',
    latitude: 17.3620,
    longitude: 78.5110,
    status: 'in_progress',
    x: 62,
    y: 35,
  },
  {
    id: 'inc-4',
    report_code: 'AID-26-008412',
    description: 'Medical Emergency — Oxygen cylinder needed',
    place: '7.1 km · Kukatpally Relief Camp',
    urgency_ai: 'high',
    people_at_risk: 6,
    created_at: '07:20 AM',
    latitude: 17.4120,
    longitude: 78.4550,
    status: 'assigned',
    x: 32,
    y: 65,
  },
];

function App() {
  const [currentView, setCurrentView] = useState('command_center'); // 'command_center' | 'landing_page'
  const [activeNav, setActiveNav] = useState('dashboard');
  const [darkMode, setDarkMode] = useState(true);
  const [autoRefreshInterval, setAutoRefreshInterval] = useState(10); // seconds: 5, 10, 30, 0 (paused)
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [lastRefreshedAt, setLastRefreshedAt] = useState(new Date());
  const [searchQuery, setSearchQuery] = useState('');
  const [overviewData, setOverviewData] = useState(null);
  const [selectedIncident, setSelectedIncident] = useState(null);
  const [visibleLayers, setVisibleLayers] = useState({
    incidents: true,
    volunteers: true,
    hospitals: true,
    resources: true,
  });

  const apiUrl = import.meta.env.VITE_API_URL || 'http://localhost:3000/v1';

  const fetchOverview = useCallback(async () => {
    setIsRefreshing(true);
    try {
      const res = await fetch(`${apiUrl}/admin/overview`, {
        headers: {
          Authorization: `Bearer ${localStorage.getItem('aidra_token') || 'demo_token'}`,
        },
      });
      if (res.ok) {
        const json = await res.json();
        setOverviewData(json);
      }
    } catch {
      // Offline or mock fallback
    } finally {
      setIsRefreshing(false);
      setLastRefreshedAt(new Date());
    }
  }, [apiUrl]);

  // Initial load
  useEffect(() => {
    fetchOverview();
  }, [fetchOverview]);

  // Live auto-refresh polling
  useEffect(() => {
    if (autoRefreshInterval <= 0) return;
    const timer = setInterval(() => {
      fetchOverview();
    }, autoRefreshInterval * 1000);
    return () => clearInterval(timer);
  }, [autoRefreshInterval, fetchOverview]);

  const incidents = (overviewData?.incidents?.length
    ? overviewData.incidents.map((inc, i) => ({
        id: inc.id,
        report_code: inc.report_code,
        description: inc.description || 'Emergency Incident',
        place: `${inc.latitude ? inc.latitude.toFixed(4) : '17.3850'}, ${inc.longitude ? inc.longitude.toFixed(4) : '78.4867'}`,
        urgency_ai: inc.urgency_ai || 'high',
        people_at_risk: inc.people_at_risk || 1,
        created_at: new Date(inc.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
        status: inc.status || 'submitted',
        x: 28 + ((i * 17) % 55),
        y: 25 + ((i * 21) % 55),
      }))
    : DEFAULT_INCIDENTS
  ).filter((item) =>
    searchQuery === ''
      ? true
      : item.description.toLowerCase().includes(searchQuery.toLowerCase()) ||
        item.report_code.toLowerCase().includes(searchQuery.toLowerCase()) ||
        item.place.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const kpis = {
    active: overviewData?.active ?? 12,
    activeDelta: overviewData?.deltas?.active ?? '+3 new',
    peopleInNeed: overviewData?.people_in_need ?? 248,
    peopleDelta: overviewData?.deltas?.people_in_need ?? '+12%',
    volunteersActive: overviewData?.volunteers_active ?? 156,
    volunteersDelta: overviewData?.deltas?.volunteers_active ?? '+8%',
    resourcesAvailable: overviewData?.resources_available ?? 8,
    resourcesDelta: overviewData?.deltas?.resources_available ?? '+2 new',
  };

  const teams = overviewData?.teams_in_field ?? [
    { id: '1', name: 'Rescue · Team Alpha', area: 'Rajendra Nagar · 4 members', status: 'EN ROUTE', eta: 'ETA 6 min' },
    { id: '2', name: 'Medical · Unit 03', area: 'Kukatpally · 2 members', status: 'ON SCENE', eta: 'Updated now' },
    { id: '3', name: 'Evacuation · Team Bravo', area: 'Amberpet · 6 members', status: 'DISPATCHED', eta: 'ETA 12 min' },
  ];

  const resources = overviewData?.resource_readiness ?? [
    { name: 'Emergency kits', percent: 82, color: 'blue' },
    { name: 'Rescue boats', percent: 56, color: 'orange' },
    { name: 'Medical beds', percent: 68, color: 'green' },
    { name: 'Food & water rations', percent: 91, color: 'blue' },
  ];

  const handleAssignVolunteer = async (incidentId) => {
    try {
      await fetch(`${apiUrl}/admin/assign-volunteer`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${localStorage.getItem('aidra_token') || 'demo_token'}`,
        },
        body: JSON.stringify({
          incident_id: incidentId,
          volunteer_id: 'vol-arjun-patel',
        }),
      });
      fetchOverview();
    } catch {}
  };

  // If in Landing Page view
  if (currentView === 'landing_page') {
    return <LandingPageView onOpenCommandCenter={() => setCurrentView('command_center')} />;
  }

  return (
    <div className={`app-container ${darkMode ? 'dark' : 'light'}`}>
      {/* Left Sidebar */}
      <aside className="sidebar">
        <div className="sidebar-header">
          <div className="logo-shield">
            <Shield size={22} fill="white" />
          </div>
          <div className="logo-text">
            <span className="logo-title">AIDRA</span>
            <span className="logo-tagline">Disaster Response</span>
          </div>
        </div>

        <nav className="sidebar-nav">
          <button
            className={`nav-item ${activeNav === 'dashboard' ? 'active' : ''}`}
            onClick={() => setActiveNav('dashboard')}
          >
            <Activity size={18} />
            <span>Dashboard</span>
          </button>
          <button
            className={`nav-item ${activeNav === 'map' ? 'active' : ''}`}
            onClick={() => setActiveNav('map')}
          >
            <MapPin size={18} />
            <span>Live Map</span>
          </button>
          <button
            className={`nav-item ${activeNav === 'incidents' ? 'active' : ''}`}
            onClick={() => setActiveNav('incidents')}
          >
            <AlertTriangle size={18} />
            <span>Incidents</span>
          </button>
          <button
            className={`nav-item ${activeNav === 'volunteers' ? 'active' : ''}`}
            onClick={() => setActiveNav('volunteers')}
          >
            <Users size={18} />
            <span>Volunteers</span>
          </button>
          <button
            className={`nav-item ${activeNav === 'hospitals' ? 'active' : ''}`}
            onClick={() => setActiveNav('hospitals')}
          >
            <HeartPulse size={18} />
            <span>Hospitals</span>
          </button>
          <button
            className={`nav-item ${activeNav === 'resources' ? 'active' : ''}`}
            onClick={() => setActiveNav('resources')}
          >
            <Package size={18} />
            <span>Resources</span>
          </button>
          <button
            className={`nav-item ${activeNav === 'ngos' ? 'active' : ''}`}
            onClick={() => setActiveNav('ngos')}
          >
            <Building2 size={18} />
            <span>NGOs</span>
          </button>
          <button
            className={`nav-item ${activeNav === 'reports' ? 'active' : ''}`}
            onClick={() => setActiveNav('reports')}
          >
            <FileText size={18} />
            <span>Reports</span>
          </button>
          <button
            className={`nav-item ${activeNav === 'analytics' ? 'active' : ''}`}
            onClick={() => setActiveNav('analytics')}
          >
            <BarChart3 size={18} />
            <span>Analytics</span>
          </button>
          <button
            className={`nav-item ${activeNav === 'settings' ? 'active' : ''}`}
            onClick={() => setActiveNav('settings')}
          >
            <Settings size={18} />
            <span>Settings</span>
          </button>
        </nav>

        <div className="sidebar-footer">
          <button className="mode-toggle-btn" onClick={() => setCurrentView('landing_page')}>
            <span>Web Landing Page</span>
            <ExternalLink size={14} />
          </button>
          <button className="mode-toggle-btn" onClick={() => setDarkMode(!darkMode)}>
            <span>{darkMode ? 'Dark Mode' : 'Light Mode'}</span>
            {darkMode ? <Sun size={14} /> : <Moon size={14} />}
          </button>
        </div>
      </aside>

      {/* Main Area */}
      <div className="main-wrapper">
        {/* Topbar */}
        <header className="topbar">
          <div className="topbar-left">
            <h1 className="page-title">Disaster Command Center</h1>
            <div className="search-bar">
              <Search size={16} color="var(--text-dark-secondary)" />
              <input
                type="text"
                placeholder="Search locations, incidents, or people..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
            </div>
          </div>

          <div className="topbar-right">
            <div className="live-badge">
              <span className="live-dot" />
              LIVE FEED
            </div>

            <div className="refresh-control">
              <button
                className={`btn-icon ${isRefreshing ? 'spinning' : ''}`}
                title="Refresh live data now"
                onClick={fetchOverview}
              >
                <RefreshCw size={16} />
              </button>
              <select
                style={{
                  background: 'var(--bg-dark-surface)',
                  color: 'var(--text-dark-secondary)',
                  border: '1px solid var(--border-dark)',
                  borderRadius: 6,
                  padding: '6px 8px',
                  fontSize: 12,
                }}
                value={autoRefreshInterval}
                onChange={(e) => setAutoRefreshInterval(Number(e.target.value))}
              >
                <option value={5}>Auto: 5s</option>
                <option value={10}>Auto: 10s</option>
                <option value={30}>Auto: 30s</option>
                <option value={0}>Auto: Off</option>
              </select>
            </div>

            <button className="btn-icon" title="Notifications">
              <Bell size={16} />
            </button>

            <div className="user-profile">
              <div className="user-avatar">AA</div>
              <div className="user-info">
                <span className="user-name">Admin Authority</span>
                <span className="user-role">State Coordinator</span>
              </div>
            </div>
          </div>
        </header>

        {/* Dashboard Content */}
        <main className="dashboard-content">
          {/* 4 KPI Cards Matching Design */}
          <section className="kpi-grid">
            <div className="kpi-card">
              <div className="kpi-top">
                <div className="kpi-icon-wrap red">
                  <AlertTriangle size={20} />
                </div>
                <span className="kpi-delta red">↑ {kpis.activeDelta}</span>
              </div>
              <span className="kpi-title">Active Incidents</span>
              <strong className="kpi-value" style={{ color: 'var(--emergency-red)' }}>
                {kpis.active}
              </strong>
            </div>

            <div className="kpi-card">
              <div className="kpi-top">
                <div className="kpi-icon-wrap blue">
                  <Users size={20} />
                </div>
                <span className="kpi-delta blue">↑ {kpis.peopleDelta}</span>
              </div>
              <span className="kpi-title">People in Need</span>
              <strong className="kpi-value" style={{ color: '#38BDF8' }}>
                {kpis.peopleInNeed}
              </strong>
            </div>

            <div className="kpi-card">
              <div className="kpi-top">
                <div className="kpi-icon-wrap green">
                  <Users size={20} />
                </div>
                <span className="kpi-delta green">↑ {kpis.volunteersDelta}</span>
              </div>
              <span className="kpi-title">Volunteers Active</span>
              <strong className="kpi-value" style={{ color: 'var(--success-green)' }}>
                {kpis.volunteersActive}
              </strong>
            </div>

            <div className="kpi-card">
              <div className="kpi-top">
                <div className="kpi-icon-wrap green">
                  <Package size={20} />
                </div>
                <span className="kpi-delta green">↑ {kpis.resourcesDelta}</span>
              </div>
              <span className="kpi-title">Resources Available</span>
              <strong className="kpi-value" style={{ color: 'var(--success-green)' }}>
                {kpis.resourcesAvailable}
              </strong>
            </div>
          </section>

          {/* Main Grid: Interactive Map + Recent Incidents */}
          <section className="main-grid">
            {/* Tactical Live Map */}
            <div className="card">
              <div className="card-header">
                <div className="card-title">
                  <MapPin size={18} color="var(--primary-blue-light)" />
                  <span>Tactical Response Map</span>
                  <span className="card-badge">Hyderabad Zone</span>
                </div>
                <span style={{ fontSize: 12, color: 'var(--text-dark-secondary)' }}>
                  Refreshed: {lastRefreshedAt.toLocaleTimeString()}
                </span>
              </div>

              <div className="map-canvas-container">
                {/* Stylized vector map backdrop */}
                <svg className="map-svg-backdrop" xmlns="http://www.w3.org/2000/svg">
                  <defs>
                    <pattern id="grid" width="36" height="36" patternUnits="userSpaceOnUse">
                      <path d="M 36 0 L 0 0 0 36" fill="none" stroke="rgba(255,255,255,0.04)" strokeWidth="1" />
                    </pattern>
                  </defs>
                  <rect width="100%" height="100%" fill="url(#grid)" />

                  {/* River */}
                  <path
                    d="M -20 280 Q 220 220 380 260 T 800 240"
                    fill="none"
                    stroke="#1E3A5F"
                    strokeWidth="28"
                    strokeLinecap="round"
                  />
                  {/* Primary Roads */}
                  <path
                    d="M 50 -10 Q 180 180 420 210 T 850 320"
                    fill="none"
                    stroke="rgba(255,255,255,0.18)"
                    strokeWidth="4"
                  />
                  <path
                    d="M 680 -10 Q 480 180 200 360 T -10 400"
                    fill="none"
                    stroke="rgba(255,255,255,0.14)"
                    strokeWidth="3.5"
                  />
                  {/* Safe Route Polyline */}
                  <path
                    d="M 280 110 L 340 180 L 410 210 L 460 270"
                    fill="none"
                    stroke="#3B82F6"
                    strokeWidth="4.5"
                    strokeDasharray="6 4"
                  />
                </svg>

                {/* Central Flood Hazard Pulsing Radius */}
                <div className="map-hazard-zone">
                  <span className="hazard-label">Flood Area</span>
                </div>

                {/* Render Incident Pins */}
                {visibleLayers.incidents &&
                  incidents.map((inc) => (
                    <div
                      key={inc.id}
                      className="map-marker"
                      style={{ left: `${inc.x}%`, top: `${inc.y}%` }}
                      onClick={() => setSelectedIncident(inc)}
                      title={`${inc.description} (${inc.urgency_ai.toUpperCase()})`}
                    >
                      <div className={`marker-pin ${inc.urgency_ai}`}>
                        <AlertTriangle size={15} />
                      </div>
                    </div>
                  ))}

                {/* Responders & Hospitals Pins */}
                {visibleLayers.volunteers && (
                  <>
                    <div className="map-marker" style={{ left: '55%', top: '38%' }} title="Arjun Patel (Medical Volunteer)">
                      <div className="marker-pin volunteer">
                        <Users size={14} />
                      </div>
                    </div>
                    <div className="map-marker" style={{ left: '38%', top: '62%' }} title="Sneha Reddy (Rescue Volunteer)">
                      <div className="marker-pin volunteer">
                        <Users size={14} />
                      </div>
                    </div>
                  </>
                )}

                {visibleLayers.hospitals && (
                  <div className="map-marker" style={{ left: '72%', top: '28%' }} title="Apollo Emergency Hub (14 ICU ready)">
                    <div className="marker-pin hospital">
                      <HeartPulse size={14} />
                    </div>
                  </div>
                )}

                {/* Map Controls */}
                <div className="map-controls">
                  <button className="map-ctrl-btn" title="Zoom in">+</button>
                  <button className="map-ctrl-btn" title="Zoom out">−</button>
                </div>
              </div>

              {/* Map Layer Legend */}
              <div className="map-legend">
                <div
                  className={`legend-item ${visibleLayers.incidents ? 'active' : ''}`}
                  onClick={() => setVisibleLayers((p) => ({ ...p, incidents: !p.incidents }))}
                >
                  <span className="legend-dot" style={{ backgroundColor: 'var(--emergency-red)' }} />
                  <span>Incidents ({incidents.length})</span>
                </div>
                <div
                  className={`legend-item ${visibleLayers.volunteers ? 'active' : ''}`}
                  onClick={() => setVisibleLayers((p) => ({ ...p, volunteers: !p.volunteers }))}
                >
                  <span className="legend-dot" style={{ backgroundColor: 'var(--accent-cyan)' }} />
                  <span>Volunteers ({kpis.volunteersActive})</span>
                </div>
                <div
                  className={`legend-item ${visibleLayers.hospitals ? 'active' : ''}`}
                  onClick={() => setVisibleLayers((p) => ({ ...p, hospitals: !p.hospitals }))}
                >
                  <span className="legend-dot" style={{ backgroundColor: 'var(--success-green)' }} />
                  <span>Hospitals (9)</span>
                </div>
                <div
                  className={`legend-item ${visibleLayers.resources ? 'active' : ''}`}
                  onClick={() => setVisibleLayers((p) => ({ ...p, resources: !p.resources }))}
                >
                  <span className="legend-dot" style={{ backgroundColor: 'var(--warning-orange)' }} />
                  <span>Resources ({kpis.resourcesAvailable})</span>
                </div>
              </div>
            </div>

            {/* Recent Incidents Panel */}
            <div className="card">
              <div className="card-header">
                <div className="card-title">
                  <AlertTriangle size={18} color="var(--emergency-red)" />
                  <span>Recent Incidents</span>
                  <span className="card-badge">{incidents.length}</span>
                </div>
                <button
                  style={{
                    background: 'none',
                    border: 'none',
                    color: 'var(--primary-blue-light)',
                    fontSize: 12,
                    fontWeight: 600,
                    cursor: 'pointer',
                  }}
                  onClick={() => setSelectedIncident(incidents[0])}
                >
                  View All
                </button>
              </div>

              <div className="incident-list">
                {incidents.map((item) => (
                  <div
                    key={item.id}
                    className="incident-row"
                    onClick={() => setSelectedIncident(item)}
                  >
                    <div className={`incident-icon-box ${item.urgency_ai}`}>
                      <AlertTriangle size={17} />
                    </div>

                    <div className="incident-details">
                      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                        <span className="incident-title">{item.description}</span>
                        <span className={`incident-urgency-badge ${item.urgency_ai}`}>
                          {item.urgency_ai}
                        </span>
                      </div>

                      <div className="incident-meta">
                        <span>👥 {item.people_at_risk} trapped</span>
                        <span>·</span>
                        <span>📍 {item.place}</span>
                        <span>·</span>
                        <span style={{ color: 'var(--text-dark-muted)' }}>🕒 {item.created_at}</span>
                      </div>

                      <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
                        <button
                          style={{
                            background: 'var(--primary-blue)',
                            color: 'white',
                            border: 'none',
                            padding: '4px 10px',
                            borderRadius: 6,
                            fontSize: 11,
                            fontWeight: 600,
                            cursor: 'pointer',
                          }}
                          onClick={(e) => {
                            e.stopPropagation();
                            handleAssignVolunteer(item.id);
                          }}
                        >
                          Assign Volunteer
                        </button>
                        <button
                          style={{
                            background: 'rgba(255,255,255,0.06)',
                            color: 'var(--text-dark-secondary)',
                            border: '1px solid var(--border-dark)',
                            padding: '4px 10px',
                            borderRadius: 6,
                            fontSize: 11,
                            cursor: 'pointer',
                          }}
                          onClick={(e) => {
                            e.stopPropagation();
                            setSelectedIncident(item);
                          }}
                        >
                          View Safe Route
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </section>

          {/* Secondary Grid: Field Teams & Resource Readiness */}
          <section className="secondary-grid">
            <div className="card">
              <div className="card-header">
                <div className="card-title">
                  <Radio size={18} color="var(--primary-blue-light)" />
                  <span>Response Teams in Field</span>
                </div>
                <span className="card-badge">3 Dispatched</span>
              </div>
              <div>
                {teams.map((t) => (
                  <div key={t.id} className="team-item">
                    <div className="team-left">
                      <div className="team-avatar">
                        <Users size={16} />
                      </div>
                      <div>
                        <div style={{ fontSize: 13, fontWeight: 600 }}>{t.name}</div>
                        <div style={{ fontSize: 11, color: 'var(--text-dark-secondary)' }}>{t.area}</div>
                      </div>
                    </div>
                    <div style={{ textAlign: 'right' }}>
                      <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--primary-blue-light)' }}>
                        {t.status}
                      </div>
                      <div style={{ fontSize: 10, color: 'var(--text-dark-secondary)' }}>{t.eta}</div>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            <div className="card">
              <div className="card-header">
                <div className="card-title">
                  <Package size={18} color="var(--success-green)" />
                  <span>Resource Readiness</span>
                </div>
                <span className="card-badge">Regional Hub</span>
              </div>
              <div>
                {resources.map((r) => (
                  <div key={r.name} className="resource-bar-row">
                    <div className="resource-bar-label">
                      <span>{r.name}</span>
                      <strong>{r.percent}%</strong>
                    </div>
                    <div className="resource-progress-track">
                      <div
                        className={`resource-progress-fill ${r.color}`}
                        style={{ width: `${r.percent}%` }}
                      />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </section>
        </main>
      </div>

      {/* Incident Detail / Dispatch Modal */}
      {selectedIncident && (
        <div
          style={{
            position: 'fixed',
            inset: 0,
            backgroundColor: 'rgba(0,0,0,0.7)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 100,
            backdropFilter: 'blur(4px)',
          }}
          onClick={() => setSelectedIncident(null)}
        >
          <div
            style={{
              backgroundColor: 'var(--bg-dark-secondary)',
              border: '1px solid var(--border-dark)',
              borderRadius: 14,
              padding: 24,
              maxWidth: 500,
              width: '90%',
              color: 'var(--text-dark-primary)',
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <span className={`incident-urgency-badge ${selectedIncident.urgency_ai}`}>
                  {selectedIncident.urgency_ai}
                </span>
                <strong style={{ fontSize: 16 }}>{selectedIncident.report_code}</strong>
              </div>
              <button
                style={{ background: 'none', border: 'none', color: 'white', cursor: 'pointer', fontSize: 18 }}
                onClick={() => setSelectedIncident(null)}
              >
                ✕
              </button>
            </div>

            <p style={{ fontSize: 14, marginBottom: 14, lineHeight: 1.5 }}>
              {selectedIncident.description}
            </p>

            <div style={{ background: 'var(--bg-dark-surface)', padding: 12, borderRadius: 8, fontSize: 12, marginBottom: 16 }}>
              <div>📍 <strong>Location:</strong> {selectedIncident.place}</div>
              <div style={{ marginTop: 4 }}>👥 <strong>Victims Trapped:</strong> {selectedIncident.people_at_risk} people</div>
              <div style={{ marginTop: 4 }}>🕒 <strong>Reported Time:</strong> {selectedIncident.created_at}</div>
              <div style={{ marginTop: 4 }}>🚦 <strong>Status:</strong> {selectedIncident.status}</div>
            </div>

            <div style={{ display: 'flex', gap: 10 }}>
              <button
                className="btn-primary"
                style={{ flex: 1 }}
                onClick={() => {
                  handleAssignVolunteer(selectedIncident.id);
                  setSelectedIncident(null);
                }}
              >
                Dispatch Volunteer Team
              </button>
              <button
                className="btn-secondary"
                style={{ flex: 1 }}
                onClick={() => setSelectedIncident(null)}
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ── Landing Page View Matching Image ─────────────────────────────────────────

function LandingPageView({ onOpenCommandCenter }) {
  return (
    <div className="landing-page">
      {/* Top Navbar */}
      <nav className="landing-navbar">
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div className="logo-shield">
            <Shield size={22} fill="white" />
          </div>
          <span style={{ fontFamily: 'var(--font-display)', fontSize: 24, fontWeight: 800, letterSpacing: 0.5 }}>
            AIDRA
          </span>
        </div>

        <div className="landing-nav-links">
          <span className="landing-nav-link active">Home</span>
          <span className="landing-nav-link">Features</span>
          <span className="landing-nav-link">About</span>
          <span className="landing-nav-link">Contact</span>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <button className="btn-primary" onClick={onOpenCommandCenter}>
            Open Command Center
          </button>
        </div>
      </nav>

      {/* Hero Section */}
      <section className="landing-hero">
        <div className="hero-content">
          <h1 className="hero-title">
            AI-Powered<br />
            <span>Disaster Response</span><br />
            for a Safer Tomorrow
          </h1>

          <p className="hero-subtitle">
            Connecting victims, volunteers, NGOs, hospitals, and authorities in real time. Faster coordination. Smarter decisions. Stronger communities.
          </p>

          {/* 4 Feature Pills */}
          <div className="feature-chips">
            <div className="feature-chip">
              <Bell size={15} color="var(--success-green)" />
              <span>Real-Time Alerts</span>
            </div>
            <div className="feature-chip">
              <Sparkles size={15} color="#38BDF8" />
              <span>AI-Powered Coordination</span>
            </div>
            <div className="feature-chip">
              <Navigation size={15} color="#FBBF24" />
              <span>Safe Route Navigation</span>
            </div>
            <div className="feature-chip">
              <Package size={15} color="var(--success-green)" />
              <span>Resource Management</span>
            </div>
          </div>

          <div className="hero-actions">
            <button className="btn-primary" style={{ padding: '14px 28px', fontSize: 16 }} onClick={onOpenCommandCenter}>
              Get Started
            </button>
            <button className="btn-secondary" style={{ padding: '14px 24px', fontSize: 15 }}>
              <Play size={16} fill="white" />
              Watch Video
            </button>
          </div>
        </div>

        {/* Hero Visual Card */}
        <div className="hero-visual">
          <div className="hero-image-card">
            {/* Visual representation of responder overlooking rescue zone */}
            <div
              style={{
                height: 420,
                width: '100%',
                background: 'linear-gradient(135deg, #1E293B 0%, #0F172A 50%, #162438 100%)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                position: 'relative',
              }}
            >
              <div style={{ textAlign: 'center', padding: 24, zIndex: 10 }}>
                <div
                  style={{
                    width: 72,
                    height: 72,
                    borderRadius: '50%',
                    background: 'rgba(239, 68, 68, 0.2)',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    margin: '0 auto 16px',
                    border: '2px solid rgba(239, 68, 68, 0.4)',
                  }}
                >
                  <Shield size={36} color="#F87171" />
                </div>
                <h3 style={{ fontSize: 22, fontWeight: 700, marginBottom: 8 }}>
                  Mission Critical Response
                </h3>
                <p style={{ color: '#94A3B8', fontSize: 13, maxWidth: 300, margin: '0 auto' }}>
                  24/7 AI Triage, GPS victim clustering, and volunteer dispatch network.
                </p>
              </div>

              <div className="hero-bg-overlay" />

              <div className="hero-badge-tagline">
                <CheckCircle2 size={16} />
                <span>Together We Save Lives</span>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}

createRoot(document.getElementById('root')).render(<App />);
