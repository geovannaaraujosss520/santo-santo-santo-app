-- PEÇAS ATIVAS E INATIVAS
-- Rode no Supabase: SQL Editor > New query > colar > Run
-- 1) cria a coluna "ativo" (todas as peças começam ativas)
alter table public.produtos add column if not exists ativo boolean not null default true;

-- 2) loja só lê peças ativas; o admin lê todas (inclusive as inativas)
drop policy if exists "ler: usuarios logados" on public.produtos;
create policy "ler: usuarios logados" on public.produtos for select to authenticated
  using (ativo or (select public.is_admin()));

-- conferência
select count(*) as total, count(*) filter (where ativo) as ativas, count(*) filter (where not ativo) as inativas
from public.produtos;
