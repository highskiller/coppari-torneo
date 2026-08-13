const SUPABASE_URL = 'https://lndqbduvyzjehkeetywt.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_VVYN8s9nVaZQR_jiC5s3GA_p8LKZZbk';
const ROOM_ID = 'coppari-main-2026-cloud-tournament';

const managerSecret = process.env.COPPARI_MANAGER_SECRET;
const refereeSecret = process.env.COPPARI_REFEREE_SECRET;
if (!/^[A-Za-z0-9_-]{20,120}$/.test(managerSecret || '') || !/^[A-Za-z0-9_-]{20,120}$/.test(refereeSecret || '')) {
  throw new Error('Imposta COPPARI_MANAGER_SECRET e COPPARI_REFEREE_SECRET con token di almeno 20 caratteri.');
}

const teams = Array.from({ length: 5 }, (_, index) => ({
  id: `t_decisa_${index + 1}`,
  name: `Squadra ${index + 1}`,
  color: ['#315b43', '#934848', '#385d7c', '#9c7837', '#6a4f86'][index],
  captainId: null,
}));

const rosters = [
  ['Greco', 'Valerio', 'Fra Rom', 'Gregorio 2', 'Jacopo S. (GK)'],
  ['Francesco Alfarano', 'Gue', 'Gregorio', 'Jacopo Romano', 'Zango'],
  ['Bako', 'Giorgio T', 'Denny', 'Luca Pisanò', 'Kun'],
  ['Mirko', 'Lorenzo Bove', 'Pippo', 'Pier', 'Marco Toma'],
  ['Ricky', 'Parì', 'Ciliberti', 'Giorgio Romano', 'Tommy'],
];

const players = rosters.flatMap((names, teamIndex) => names.map((name, playerIndex) => ({
  id: `p_decisa_${teamIndex + 1}_${playerIndex + 1}`,
  name,
  role: name === 'Jacopo S. (GK)' ? 'POR' : 'TBD',
  rating: 3,
  teamId: teams[teamIndex].id,
  active: true,
})));

const fixtures = [
  [5, 3], [4, 1], [2, 5], [3, 4], [2, 1],
  [4, 5], [2, 3], [5, 1], [2, 4], [3, 1],
];

const matches = fixtures.map(([home, away], index) => ({
  id: `m_decisa_${index + 1}`,
  stage: 'group',
  leg: 1,
  round: index + 1,
  homeTeamId: `t_decisa_${home}`,
  awayTeamId: `t_decisa_${away}`,
  date: '',
  status: 'scheduled',
  homeScore: null,
  awayScore: null,
  stats: [],
  events: [],
  ratings: [],
  ratingsPublished: false,
  referee: null,
  mvpPlayerId: null,
}));

const now = new Date().toISOString();
const state = {
  settings: {
    name: 'Copparì',
    edition: 'Edizione 2026',
    pointsWin: 3,
    pointsDraw: 1,
    pointsLoss: 0,
    targetPlayers: 25,
    rosterSize: 5,
    teamCount: 5,
    scheduleMode: 'single',
    tournamentFormat: 'groups_ko',
    startTime: '00:00',
    periods: 2,
    matchMinutes: 20,
    halftimeMinutes: 2,
    changeMinutes: 4,
    playoffs: true,
    bronzeFinal: false,
    venue: '',
    organizer: '',
    touchGuard: true,
    hapticFeedback: true,
    soundFeedback: true,
    configured: true,
  },
  players,
  teams,
  matches,
  meta: { appVersion: '3.7.0', createdAt: now, updatedAt: now },
};

const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/coppari_live_create`, {
  method: 'POST',
  headers: {
    apikey: SUPABASE_PUBLISHABLE_KEY,
    Authorization: `Bearer ${SUPABASE_PUBLISHABLE_KEY}`,
    'Content-Type': 'application/json',
    Accept: 'application/json',
  },
  body: JSON.stringify({
    p_room_id: ROOM_ID,
    p_manager_secret: managerSecret,
    p_referee_secret: refereeSecret,
    p_state: state,
  }),
});

const payload = await response.json().catch(() => null);
if (!response.ok) throw new Error(payload?.message || `Supabase HTTP ${response.status}`);
const row = Array.isArray(payload) ? payload[0] : payload;
console.log(JSON.stringify({ roomId: ROOM_ID, revision: row?.revision, active: row?.active }));
