-- 1) Primero crea el usuario administrador en Supabase Dashboard > Authentication > Users.
-- 2) Reemplaza el correo y ejecuta ESTE bloque una sola vez.
do $$
declare uid uuid;
begin
  select id into uid from auth.users where lower(email)=lower('REPLACE_WITH_ADMIN_EMAIL') limit 1;
  if uid is null then raise exception 'ADMIN_AUTH_USER_NOT_FOUND'; end if;
  insert into public.platform_admins(user_id,role,active) values(uid,'SUPERADMIN',true)
  on conflict(user_id) do update set role='SUPERADMIN',active=true;
end $$;
