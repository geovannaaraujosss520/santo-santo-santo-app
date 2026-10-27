-- CORREÇÃO DE SEGURANÇA · versão 3
-- Rode no Supabase: SQL Editor > New query > colar TUDO > clique em Run
-- (sem nenhum trecho selecionado: com texto selecionado o Supabase roda só a seleção)
-- Cada etapa roda separada; se uma falhar, as outras continuam.
-- No fim aparece uma tabela com o resultado de cada etapa. Me envie essa tabela.
-- Não apaga nenhum dado.

create temp table if not exists _resultado (ordem serial, etapa text, status text, detalhe text);
truncate _resultado;

-- 1) cria santos_extras (cadastro de santos novos)
do $$ begin
  create table if not exists public.santos_extras (
    nome text primary key,
    tipo text not null default 'santo' check (tipo in ('santo','santa','senhora','beato')),
    padroeiro text not null default '',
    origem text not null default '',
    curiosidade text,
    oracao text,
    festa text check (festa is null or festa ~ '^\d{2}/\d{2}$'),
    criado_em timestamptz not null default now()
  );
  insert into _resultado(etapa, status, detalhe) values ('1. tabela santos_extras', 'ok', 'existe');
exception when others then
  insert into _resultado(etapa, status, detalhe) values ('1. tabela santos_extras', 'ERRO', sqlerrm);
end $$;

-- 2) tabelas do app: ler só logado, alterar só admin, nada sem login
do $$
declare t text; pol record;
begin
  foreach t in array array['produtos','fornecedores','campanha_santos','santos_extras'] loop
    begin
      if to_regclass('public.' || t) is null then
        insert into _resultado(etapa, status, detalhe) values ('2. ' || t, 'pulado', 'tabela não existe');
        continue;
      end if;
      execute format('alter table public.%I enable row level security', t);
      for pol in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
        execute format('drop policy %I on public.%I', pol.policyname, t);
      end loop;
      execute format('create policy "ler: usuarios logados" on public.%I for select to authenticated using (true)', t);
      execute format('create policy "incluir: so admin" on public.%I for insert to authenticated with check ((select public.is_admin()))', t);
      execute format('create policy "alterar: so admin" on public.%I for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()))', t);
      execute format('create policy "excluir: so admin" on public.%I for delete to authenticated using ((select public.is_admin()))', t);
      execute format('revoke all on public.%I from anon, public, authenticated', t);
      execute format('grant select, insert, update, delete on public.%I to authenticated', t);
      insert into _resultado(etapa, status, detalhe) values ('2. ' || t, 'ok', 'ler: logado · alterar: admin');
    exception when others then
      insert into _resultado(etapa, status, detalhe) values ('2. ' || t, 'ERRO', sqlerrm);
    end;
  end loop;
end $$;

-- 3) admins e backups: fechadas para a API (o is_admin continua funcionando)
do $$
declare t text;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind = 'r' and (c.relname = 'admins' or c.relname like 'backup\_%') loop
    begin
      execute format('alter table public.%I enable row level security', t);
      execute format('revoke all on public.%I from anon, public, authenticated', t);
      insert into _resultado(etapa, status, detalhe) values ('3. ' || t, 'ok', 'fechada para a API');
    exception when others then
      insert into _resultado(etapa, status, detalhe) values ('3. ' || t, 'ERRO', sqlerrm);
    end;
  end loop;
end $$;

-- 4) view produtos_ativos: respeita as regras de produtos e é só leitura para logados
do $$ begin
  if to_regclass('public.produtos_ativos') is not null then
    execute 'alter view public.produtos_ativos set (security_invoker = true)';
    execute 'revoke all on public.produtos_ativos from anon, public, authenticated';
    execute 'grant select on public.produtos_ativos to authenticated';
    insert into _resultado(etapa, status, detalhe) values ('4. view produtos_ativos', 'ok', 'só leitura, respeita as regras');
  end if;
exception when others then
  insert into _resultado(etapa, status, detalhe) values ('4. view produtos_ativos', 'ERRO', sqlerrm);
end $$;

-- 5) funções sem acesso para quem não tem login
do $$
declare f text;
begin
  foreach f in array array['public.is_admin()','public.tg_set_updated_at()','public.tg_set_updated_at_forn()'] loop
    begin
      if to_regprocedure(f) is null then continue; end if;
      execute format('revoke execute on function %s from anon, public', f);
      if f = 'public.is_admin()' then execute 'grant execute on function public.is_admin() to authenticated'; end if;
      insert into _resultado(etapa, status, detalhe) values ('5. ' || f, 'ok', 'sem acesso sem login');
    exception when others then
      insert into _resultado(etapa, status, detalhe) values ('5. ' || f, 'ERRO', sqlerrm);
    end;
  end loop;
end $$;

-- 6) tabelas criadas no futuro não nascem abertas para quem não tem login
do $$ begin
  execute 'alter default privileges in schema public revoke all on tables from anon';
  insert into _resultado(etapa, status, detalhe) values ('6. tabelas futuras', 'ok', 'nascem fechadas para anon');
exception when others then
  insert into _resultado(etapa, status, detalhe) values ('6. tabelas futuras', 'ERRO', sqlerrm);
end $$;

-- 7) bucket "fotos" (o app não usa): só admin envia, troca ou apaga
do $$
declare pol record;
begin
  if to_regclass('storage.objects') is null then return; end if;
  for pol in select policyname from pg_policies
             where schemaname = 'storage' and tablename = 'objects' and cmd <> 'SELECT'
               and coalesce(qual, '') || coalesce(with_check, '') ~ 'fotos'
               and policyname not like 'fotos: so admin%' loop
    execute format('drop policy %I on storage.objects', pol.policyname);
  end loop;
  drop policy if exists "fotos: so admin envia" on storage.objects;
  drop policy if exists "fotos: so admin altera" on storage.objects;
  drop policy if exists "fotos: so admin apaga" on storage.objects;
  create policy "fotos: so admin envia" on storage.objects for insert to authenticated
    with check (bucket_id = 'fotos' and (select public.is_admin()));
  create policy "fotos: so admin altera" on storage.objects for update to authenticated
    using (bucket_id = 'fotos' and (select public.is_admin())) with check (bucket_id = 'fotos' and (select public.is_admin()));
  create policy "fotos: so admin apaga" on storage.objects for delete to authenticated
    using (bucket_id = 'fotos' and (select public.is_admin()));
  insert into _resultado(etapa, status, detalhe) values ('7. storage fotos', 'ok', 'escrita só admin');
exception when others then
  insert into _resultado(etapa, status, detalhe) values ('7. storage fotos', 'ERRO', sqlerrm);
end $$;

-- 8) conferência final: o que ainda está aberto para quem não tem login
insert into _resultado(etapa, status, detalhe)
select '8. ainda aberto sem login: ' || table_name, 'ATENCAO', string_agg(privilege_type, ', ' order by privilege_type)
from information_schema.role_table_grants
where table_schema = 'public' and grantee = 'anon'
group by table_name;

insert into _resultado(etapa, status, detalhe)
select '8. conferência', 'ok', 'nenhuma tabela aberta sem login'
where not exists (select 1 from information_schema.role_table_grants where table_schema = 'public' and grantee = 'anon');

select etapa, status, detalhe from _resultado order by ordem;
