// Código común a las 3 páginas (app, personal y admin)

const configured = !SUPABASE_URL.includes('TU-PROYECTO') && !SUPABASE_ANON_KEY.includes('PEGA-AQUI');
const sb = configured ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY) : null;

// ── Fechas en hora de Bélgica ──
const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
function pad(n) { return String(n).padStart(2, '0'); }

function brussels(date) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Brussels',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hour12: false
  }).formatToParts(date);
  const get = t => parseInt(parts.find(p => p.type === t).value);
  return { day: get('day'), month: get('month'), year: get('year'), hour: get('hour') % 24, min: get('minute') };
}

// "Thursday 08/10/2026 at 14:36"
function formatCheckinTime(iso) {
  const b = brussels(new Date(iso));
  const dayName = DAYS[new Date(b.year, b.month - 1, b.day).getDay()];
  return `${dayName} ${pad(b.day)}/${pad(b.month)}/${b.year} at ${pad(b.hour)}:${pad(b.min)}`;
}

function isToday(iso) {
  const a = brussels(new Date(iso)), b = brussels(new Date());
  return a.day === b.day && a.month === b.month && a.year === b.year;
}

// ── Utilidades ──
function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// Avatar con iniciales (sin servicios externos)
function initialsAvatar(name) {
  const initials = (name || '?').trim().split(/\s+/).slice(0, 2).map(w => w[0]).join('').toUpperCase() || '?';
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400"><rect width="400" height="400" fill="#d1d5db"/><text x="200" y="200" dy=".35em" text-anchor="middle" font-family="Inter,Arial,sans-serif" font-size="160" fill="#9ca3af">${esc(initials)}</text></svg>`;
  return 'data:image/svg+xml,' + encodeURIComponent(svg);
}

async function photoUrl(path, name) {
  if (!path) return initialsAvatar(name);
  const { data } = await sb.storage.from('photos').createSignedUrl(path, 60 * 60);
  return data?.signedUrl || initialsAvatar(name);
}

async function getMyProfile() {
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return null;
  const { data, error } = await sb.from('profiles').select('*').eq('id', user.id).single();
  if (error) throw error;
  return data;
}

// ── Formulario de login común ──
// Espera un <form> con inputs name="email" y name="password" y un elemento .login-error
function setupLogin(form, onSuccess) {
  const errorEl = form.querySelector('.login-error');
  const button  = form.querySelector('button[type="submit"]');
  if (!configured) {
    errorEl.textContent = 'Falta configurar Supabase en config.js';
    button.disabled = true;
    return;
  }
  form.addEventListener('submit', async e => {
    e.preventDefault();
    errorEl.textContent = '';
    button.disabled = true;
    const { error } = await sb.auth.signInWithPassword({
      email: form.email.value.trim(),
      password: form.password.value
    });
    button.disabled = false;
    if (error) {
      errorEl.textContent = error.message === 'Invalid login credentials'
        ? 'Email o contraseña incorrectos'
        : error.message;
      return;
    }
    form.password.value = '';
    onSuccess();
  });
}

async function hasSession() {
  if (!configured) return false;
  const { data: { session } } = await sb.auth.getSession();
  return !!session;
}

async function logout() {
  await sb.auth.signOut();
  location.reload();
}
