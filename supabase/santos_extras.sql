-- Santos cadastrados pelo admin que não estão na lista original do Devocionário
-- Rode uma única vez no Supabase: SQL Editor > New query > colar > Run

create table if not exists public.santos_extras (
  nome text primary key,
  tipo text not null default 'santo' check (tipo in ('santo','santa','senhora','beato')),
  padroeiro text not null default '',
  origem text not null default '',
  curiosidade text,
  oracao text,
  festa text check (festa is null or festa ~ '^\d{2}/\d{2}$'),   -- ex.: 15/11
  criado_em timestamptz not null default now()
);

alter table public.santos_extras enable row level security;

drop policy if exists "extras leitura" on public.santos_extras;
create policy "extras leitura" on public.santos_extras
  for select using (true);

drop policy if exists "extras escrita admin" on public.santos_extras;
create policy "extras escrita admin" on public.santos_extras
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select on public.santos_extras to anon, authenticated;
grant insert, update, delete on public.santos_extras to authenticated;
