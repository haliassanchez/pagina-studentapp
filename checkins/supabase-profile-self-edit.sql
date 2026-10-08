-- ══════════════════════════════════════════════════════════════
--  Foto y universidad editables por el propio estudiante
--  Si ya ejecutaste supabase-schema.sql, pega este archivo en
--  Supabase → SQL Editor → Run (una sola vez).
-- ══════════════════════════════════════════════════════════════

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
