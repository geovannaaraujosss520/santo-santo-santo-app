-- Gestão de usuários pelo app (só administradores)
-- Rode uma única vez no Supabase: SQL Editor > New query > colar > Run
-- Cria 4 funções seguras: listar, criar, redefinir senha e excluir usuários.
-- Todas recusam o pedido se quem chama não for administrador (função is_admin()).

-- 1) listar
create or replace function public.admin_listar_usuarios()
returns table (id uuid, email text, unidade text, criado_em timestamptz, ultimo_acesso timestamptz, eu boolean)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return query
    select u.id, u.email::text, coalesce(u.raw_user_meta_data->>'unidade', '')::text,
           u.created_at, u.last_sign_in_at, (u.id = auth.uid())
    from auth.users u
    order by coalesce(u.raw_user_meta_data->>'unidade', u.email::text);
end;
$$;

-- 2) criar
create or replace function public.admin_criar_usuario(p_email text, p_senha text, p_unidade text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(p_email));
  v_id uuid := gen_random_uuid();
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'email_invalido';
  end if;
  if length(coalesce(p_senha, '')) < 6 then
    raise exception 'senha_curta';
  end if;
  if exists (select 1 from auth.users u where lower(u.email) = v_email) then
    raise exception 'email_existe';
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
    extensions.crypt(p_senha, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('unidade', trim(coalesce(p_unidade, ''))), now(), now(),
    '', '', '', ''
  );
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (
    gen_random_uuid(), v_id, v_id::text,
    jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
    'email', now(), now(), now()
  );
  return v_id;
end;
$$;

-- 3) redefinir senha
create or replace function public.admin_redefinir_senha(p_id uuid, p_senha text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if length(coalesce(p_senha, '')) < 6 then
    raise exception 'senha_curta';
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_senha, extensions.gen_salt('bf')), updated_at = now()
   where id = p_id;
  if not found then raise exception 'usuario_nao_encontrado'; end if;
end;
$$;

-- 4) excluir (não deixa excluir a própria conta)
create or replace function public.admin_excluir_usuario(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  if p_id = auth.uid() then
    raise exception 'nao_pode_excluir_a_si';
  end if;
  delete from auth.identities where user_id = p_id;
  delete from auth.users where id = p_id;
  if not found then raise exception 'usuario_nao_encontrado'; end if;
end;
$$;

-- só usuários logados podem chamar (e as funções ainda conferem se é admin)
revoke all on function public.admin_listar_usuarios() from public, anon;
revoke all on function public.admin_criar_usuario(text, text, text) from public, anon;
revoke all on function public.admin_redefinir_senha(uuid, text) from public, anon;
revoke all on function public.admin_excluir_usuario(uuid) from public, anon;
grant execute on function public.admin_listar_usuarios() to authenticated;
grant execute on function public.admin_criar_usuario(text, text, text) to authenticated;
grant execute on function public.admin_redefinir_senha(uuid, text) to authenticated;
grant execute on function public.admin_excluir_usuario(uuid) to authenticated;
