-- SUGESTÕES DO DEVOCIONÁRIO
-- Rode no Supabase: SQL Editor > New query > colar TUDO > Run
-- A loja envia e vê só as próprias sugestões; o admin vê todas, muda o status e responde.

create table if not exists public.sugestoes (
  id bigint generated always as identity primary key,
  criado_em timestamptz not null default now(),
  user_id uuid not null default auth.uid(),
  email text,
  unidade text,
  tipo text not null check (tipo in ('novo_santo','correcao','oracao','outro')),
  santo text check (santo is null or char_length(santo) <= 120),
  mensagem text not null check (char_length(mensagem) between 5 and 1000),
  status text not null default 'nova' check (status in ('nova','em_analise','resolvida')),
  resposta text check (resposta is null or char_length(resposta) <= 1000),
  atualizado_em timestamptz
);

-- ao enviar: quem enviou, e-mail e unidade vêm da conta (não do app); limite de 10 por hora
create or replace function public.sugestoes_ao_enviar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.user_id := auth.uid();
  if new.user_id is null then raise exception 'sem_login'; end if;
  select u.email::text, coalesce(u.raw_user_meta_data->>'unidade', '')
    into new.email, new.unidade
    from auth.users u where u.id = new.user_id;
  new.criado_em := now();
  new.status := 'nova';
  new.resposta := null;
  new.atualizado_em := null;
  if (select count(*) from public.sugestoes s
      where s.user_id = new.user_id and s.criado_em > now() - interval '1 hour') >= 10 then
    raise exception 'limite_sugestoes';
  end if;
  return new;
end;
$$;

-- ao alterar: só admin, e só status e resposta mudam
create or replace function public.sugestoes_ao_alterar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not coalesce(public.is_admin(), false) then raise exception 'sem_permissao'; end if;
  new.id := old.id; new.criado_em := old.criado_em; new.user_id := old.user_id;
  new.email := old.email; new.unidade := old.unidade; new.tipo := old.tipo; new.santo := old.santo; new.mensagem := old.mensagem;
  new.atualizado_em := now();
  return new;
end;
$$;

drop trigger if exists sugestoes_enviar on public.sugestoes;
create trigger sugestoes_enviar before insert on public.sugestoes
  for each row execute function public.sugestoes_ao_enviar();
drop trigger if exists sugestoes_alterar on public.sugestoes;
create trigger sugestoes_alterar before update on public.sugestoes
  for each row execute function public.sugestoes_ao_alterar();

revoke execute on function public.sugestoes_ao_enviar() from public, anon, authenticated;
revoke execute on function public.sugestoes_ao_alterar() from public, anon, authenticated;

alter table public.sugestoes enable row level security;
drop policy if exists "sugestoes: ver as proprias ou admin" on public.sugestoes;
drop policy if exists "sugestoes: enviar" on public.sugestoes;
drop policy if exists "sugestoes: admin altera" on public.sugestoes;
drop policy if exists "sugestoes: admin exclui" on public.sugestoes;
create policy "sugestoes: ver as proprias ou admin" on public.sugestoes for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "sugestoes: enviar" on public.sugestoes for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "sugestoes: admin altera" on public.sugestoes for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "sugestoes: admin exclui" on public.sugestoes for delete to authenticated
  using ((select public.is_admin()));

revoke all on public.sugestoes from anon, public, authenticated;
grant select, insert, update, delete on public.sugestoes to authenticated;

-- conferência
select 'sugestoes' as tabela, count(*) as registros from public.sugestoes;
