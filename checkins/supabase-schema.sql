-- ══════════════════════════════════════════════════════════════
--  Base de datos del sistema de check-ins
--  Pega TODO este archivo en Supabase → SQL Editor → Run (una sola vez).
-- ══════════════════════════════════════════════════════════════

-- ── Perfiles: uno por cada cuenta. Solo el admin puede modificarlos. ──
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  full_name   text not null default '',
  institution text not null default '',
  photo_path  text,
  role        text not null default 'student' check (role in ('student', 'staff', 'admin')),
  created_at  timestamptz not null default now()
);

-- Crea el perfil automáticamente cuando el admin crea un usuario en Authentication
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Rol del usuario que hace la petición
create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

alter table public.profiles enable row level security;

create policy "Cada uno ve su perfil" on public.profiles
  for select using (id = auth.uid());
create policy "Personal ve todos los perfiles" on public.profiles
  for select using (public.my_role() in ('staff', 'admin'));
create policy "Solo admin modifica perfiles" on public.profiles
  for update using (public.my_role() = 'admin') with check (public.my_role() = 'admin');


-- ── Actividades ──
create table public.activities (
  id         bigint generated always as identity primary key,
  name       text not null,
  location   text not null default '',
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.activities enable row level security;

create policy "Usuarios ven actividades" on public.activities
  for select to authenticated using (true);
create policy "Solo admin gestiona actividades" on public.activities
  for all using (public.my_role() = 'admin') with check (public.my_role() = 'admin');


-- ── Check-ins: la hora y el código los pone el servidor ──
create table public.checkins (
  id          bigint generated always as identity primary key,
  student_id  uuid not null references public.profiles(id) on delete cascade,
  activity_id bigint not null references public.activities(id) on delete cascade,
  code        text not null unique,
  created_at  timestamptz not null default now()
);

alter table public.checkins enable row level security;

create policy "Cada uno ve sus check-ins" on public.checkins
  for select using (student_id = auth.uid());
create policy "Personal ve todos los check-ins" on public.checkins
  for select using (public.my_role() in ('staff', 'admin'));
-- Sin política de insert: los estudiantes solo pueden hacer check-in con do_checkin()

create or replace function public.do_checkin(p_activity_id bigint)
returns public.checkins language plpgsql security definer set search_path = public as $$
declare
  r      public.checkins;
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'No has iniciado sesión';
  end if;
  if not exists (select 1 from profiles where id = auth.uid() and full_name <> '') then
    raise exception 'Tu cuenta aún no tiene perfil. Contacta con el administrador.';
  end if;
  if not exists (select 1 from activities where id = p_activity_id and active) then
    raise exception 'Esta actividad no está disponible';
  end if;

  -- Un check-in por actividad y día (hora de Bélgica): si ya existe, se devuelve el mismo
  select * into r from checkins
   where student_id = auth.uid()
     and activity_id = p_activity_id
     and (created_at at time zone 'Europe/Brussels')::date = (now() at time zone 'Europe/Brussels')::date;
  if found then
    return r;
  end if;

  loop
    v_code := upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from checkins where code = v_code);
  end loop;

  insert into checkins (student_id, activity_id, code)
  values (auth.uid(), p_activity_id, v_code)
  returning * into r;
  return r;
end;
$$;

revoke execute on function public.do_checkin(bigint) from public, anon;
grant execute on function public.do_checkin(bigint) to authenticated;


-- ── Fotos de perfil (privadas): cada estudiante ve la suya, el personal todas, solo el admin sube ──
insert into storage.buckets (id, name, public) values ('photos', 'photos', false);

create policy "Ver fotos" on storage.objects
  for select using (
    bucket_id = 'photos'
    and (name like auth.uid()::text || '%' or public.my_role() in ('staff', 'admin'))
  );
create policy "Admin sube fotos" on storage.objects
  for insert with check (bucket_id = 'photos' and public.my_role() = 'admin');
create policy "Admin cambia fotos" on storage.objects
  for update using (bucket_id = 'photos' and public.my_role() = 'admin');
create policy "Admin borra fotos" on storage.objects
  for delete using (bucket_id = 'photos' and public.my_role() = 'admin');


-- ── Eliminar perfiles (solo admin) ──
-- Borra la cuenta: su perfil y sus check-ins se borran con ella
create or replace function public.delete_user(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if coalesce(public.my_role(), '') <> 'admin' then
    raise exception 'Solo los administradores pueden eliminar perfiles';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'No puedes eliminar tu propia cuenta';
  end if;
  delete from auth.users where id = p_user_id;
end;
$$;

revoke execute on function public.delete_user(uuid) from public, anon;
grant execute on function public.delete_user(uuid) to authenticated;


-- ── Foto y universidad editables por el estudiante ──
-- El estudiante cambia su universidad cuando quiera
create or replace function public.set_my_institution(p_institution text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'No has iniciado sesión';
  end if;
  if length(trim(p_institution)) > 100 then
    raise exception 'El nombre de la universidad es demasiado largo';
  end if;
  update profiles set institution = trim(p_institution) where id = auth.uid();
end;
$$;

revoke execute on function public.set_my_institution(text) from public, anon;
grant execute on function public.set_my_institution(text) to authenticated;

-- ¿Puede el usuario subir su foto? Solo si todavía no tiene una
-- (para cambiarla, el admin pulsa "Quitar foto" en admin.html)
create or replace function public.can_upload_my_photo()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and photo_path is null)
$$;

create policy "Estudiante sube su primera foto" on storage.objects
  for insert with check (
    bucket_id = 'photos'
    and name = auth.uid()::text || '.jpg'
    and public.can_upload_my_photo()
  );

-- Después de subirla, la enlaza a su perfil (queda bloqueada)
create or replace function public.set_my_photo()
returns text language plpgsql security definer set search_path = public as $$
declare
  v_path text := auth.uid()::text || '.jpg';
begin
  if auth.uid() is null then
    raise exception 'No has iniciado sesión';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'photos' and name = v_path) then
    raise exception 'No se ha encontrado la foto subida';
  end if;
  update profiles set photo_path = v_path where id = auth.uid() and photo_path is null;
  if not found then
    raise exception 'Ya tienes una foto. Para cambiarla, contacta con el administrador.';
  end if;
  return v_path;
end;
$$;

revoke execute on function public.set_my_photo() from public, anon;
grant execute on function public.set_my_photo() to authenticated;
