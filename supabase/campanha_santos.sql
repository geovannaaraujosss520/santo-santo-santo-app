-- Tabela da campanha de santos em destaque (Devocionário)
-- Rode uma única vez no Supabase: SQL Editor > New query > colar > Run

create table if not exists public.campanha_santos (
  mes text primary key check (mes ~ '^\d{4}-\d{2}$'),   -- ex.: 2026-11
  santos jsonb not null default '[]'::jsonb,            -- nomes dos santos, na ordem de exibição
  atualizado_em timestamptz not null default now()
);

alter table public.campanha_santos enable row level security;

-- todas as unidades podem ler
drop policy if exists "campanha leitura" on public.campanha_santos;
create policy "campanha leitura" on public.campanha_santos
  for select using (true);

-- só administradores podem criar, alterar ou apagar
drop policy if exists "campanha escrita admin" on public.campanha_santos;
create policy "campanha escrita admin" on public.campanha_santos
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select on public.campanha_santos to anon, authenticated;
grant insert, update, delete on public.campanha_santos to authenticated;
