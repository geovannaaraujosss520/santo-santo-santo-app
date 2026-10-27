-- EXIGIR TROCA DE SENHA NO PRIMEIRO ACESSO (opcional)
-- Rode no Supabase: SQL Editor > New query > colar > Run
--
-- O que faz:
--   1) marca todas as contas para trocar a senha no próximo acesso;
--   2) a partir de agora, contas criadas ou senhas redefinidas pelo painel de admin
--      também pedem a troca no primeiro acesso.
-- Administradores não são obrigados a trocar (o app pula a tela para eles).
-- Depois da troca, nem você nem ninguém sabe a senha nova; se a loja esquecer, use "Nova senha" no painel.

update auth.users
   set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || '{"trocar_senha": true}'::jsonb;

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
    jsonb_build_object('unidade', trim(coalesce(p_unidade, '')), 'trocar_senha', true), now(), now(),
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
     set encrypted_password = extensions.crypt(p_senha, extensions.gen_salt('bf')), updated_at = now(),
         raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || '{"trocar_senha": true}'::jsonb
   where id = p_id;
  if not found then raise exception 'usuario_nao_encontrado'; end if;
end;
$$;


-- conferência
select count(*) filter (where raw_user_meta_data->>'trocar_senha' = 'true') as contas_que_vao_trocar, count(*) as total
from auth.users;

-- PARA DESFAZER (se mudar de ideia antes da terça):
-- update auth.users set raw_user_meta_data = raw_user_meta_data - 'trocar_senha';
