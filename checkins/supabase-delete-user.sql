-- ══════════════════════════════════════════════════════════════
--  Eliminar perfiles desde admin.html
--  Si ya ejecutaste supabase-schema.sql ANTES de que existiera esta función,
--  pega este archivo en Supabase → SQL Editor → Run (una sola vez).
--  (Si ejecutas supabase-schema.sql desde cero, ya viene incluido.)
-- ══════════════════════════════════════════════════════════════

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
