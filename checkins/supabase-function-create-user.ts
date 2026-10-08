// ══════════════════════════════════════════════════════════════
//  Edge Function "create-user": crea cuentas desde admin.html
//  Se instala en Supabase → Edge Functions → Deploy a new function → Via Editor
//  (nombre: create-user). Usa la clave secreta que Supabase ya tiene dentro
//  del servidor: NO hay que pegar ninguna clave aquí.
// ══════════════════════════════════════════════════════════════
import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    // Clave secreta: proyectos antiguos (service_role) o nuevos (sb_secret_...)
    let secretKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!secretKey) {
      try {
        const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}');
        secretKey = keys.default ?? Object.values(keys)[0];
      } catch (_) { /* sin clave */ }
    }
    if (!secretKey) return json({ error: 'La función no encuentra la clave secreta del proyecto' }, 500);

    const admin = createClient(Deno.env.get('SUPABASE_URL')!, secretKey, {
      auth: { persistSession: false },
    });

    // ¿Quién llama? Tiene que ser un admin con sesión iniciada
    const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(token);
    if (!user) return json({ error: 'No has iniciado sesión' }, 401);

    const { data: me } = await admin.from('profiles').select('role').eq('id', user.id).single();
    if (me?.role !== 'admin') return json({ error: 'Solo los administradores pueden crear perfiles' }, 403);

    // Datos del nuevo perfil
    const { email, password, full_name, institution, role } = await req.json();
    if (!email || !/^\S+@\S+\.\S+$/.test(email)) return json({ error: 'Email no válido' }, 400);
    if (!password || String(password).length < 8) return json({ error: 'La contraseña debe tener al menos 8 caracteres' }, 400);
    if (!full_name || !String(full_name).trim()) return json({ error: 'Falta el nombre' }, 400);
    if (!['student', 'staff', 'admin'].includes(role)) return json({ error: 'Rol no válido' }, 400);

    const { data, error } = await admin.auth.admin.createUser({
      email: String(email).trim(),
      password: String(password),
      email_confirm: true,
    });
    if (error) {
      const msg = /already|registered|exists/i.test(error.message)
        ? 'Ya existe una cuenta con ese email'
        : error.message;
      return json({ error: msg }, 400);
    }

    // El perfil lo crea el trigger de la base de datos; aquí lo completamos
    const { error: upErr } = await admin.from('profiles').update({
      full_name: String(full_name).trim(),
      institution: String(institution ?? '').trim(),
      role,
    }).eq('id', data.user.id);
    if (upErr) return json({ error: upErr.message }, 500);

    return json({ id: data.user.id });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
