-- AUDITORIA DE SEGURANÇA · somente leitura (não altera nada)
-- Rode no Supabase: SQL Editor > New query > colar > Run
-- Depois clique em "Export" > "Copy as CSV" (ou copie a tabela) e me envie o resultado.

with
tabelas as (
  select c.oid, c.relname, c.relkind, c.relrowsecurity as rls, c.relforcerowsecurity as forcado,
         coalesce(c.reloptions @> array['security_invoker=true'], false) as invoker
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p','v','m')
),
r as (
  -- 1. tabelas e se a proteção por linha (RLS) está ligada
  select 1 as ord, 'tabela'::text as secao, t.relname::text as item,
         case t.relkind when 'v' then (case when t.invoker then 'VIEW (respeita RLS)' else 'VIEW' end) when 'm' then 'VIEW MATERIALIZADA' else (case when t.rls then 'RLS ligado' else 'RLS DESLIGADO' end) end as detalhe,
         case when t.relkind in ('r','p') and not t.rls then 'CRITICO: tabela sem RLS'
              when t.relkind = 'v' and t.invoker then 'ok'
              when t.relkind in ('v','m') then 'ATENCAO: view ignora RLS (verificar security_invoker)'
              else 'ok' end as alerta
  from tabelas t

  union all
  -- 2. permissões das funções "anon" (sem login) e "authenticated" (logado) nas tabelas
  select 2, 'permissao', g.table_name::text, g.grantee || ': ' || string_agg(g.privilege_type, ', ' order by g.privilege_type),
         case when g.grantee = 'anon' then 'CRITICO: acesso sem login' else 'ok' end
  from information_schema.role_table_grants g
  where g.table_schema = 'public' and g.grantee in ('anon','authenticated','public')
  group by g.table_name, g.grantee

  union all
  -- 3. políticas de acesso (quem pode ler e quem pode alterar)
  select 3, 'politica', p.tablename || ' · ' || p.policyname,
         p.cmd || ' para ' || array_to_string(p.roles, ',') || ' | using: ' || coalesce(p.qual, '-') || ' | check: ' || coalesce(p.with_check, '-'),
         case
           when p.cmd <> 'SELECT' and coalesce(p.qual,'') || coalesce(p.with_check,'') !~* 'is_admin' then 'CRITICO: escrita sem exigir admin'
           when ('anon' = any(p.roles) or 'public' = any(p.roles)) and p.cmd = 'SELECT' and coalesce(p.qual,'') ~* '^\(?true\)?$' then 'ATENCAO: leitura liberada a todos (depende da permissao anon)'
           else 'ok' end
  from pg_policies p
  where p.schemaname = 'public'

  union all
  -- 4. funções expostas pela API
  select 4, 'funcao', f.proname || '(' || pg_get_function_identity_arguments(f.oid) || ')',
         case when f.prosecdef then 'SECURITY DEFINER' else 'invoker' end
           || ' | anon executa: ' || has_function_privilege('anon', f.oid, 'EXECUTE')
           || ' | logado executa: ' || has_function_privilege('authenticated', f.oid, 'EXECUTE')
           || ' | search_path: ' || coalesce(array_to_string(f.proconfig, ','), 'NAO DEFINIDO'),
         case when f.prosecdef and has_function_privilege('anon', f.oid, 'EXECUTE') and f.proname <> 'is_admin' then 'CRITICO: funcao privilegiada acessivel sem login'
              when f.prosecdef and f.proconfig is null then 'ATENCAO: security definer sem search_path fixo'
              else 'ok' end
  from pg_proc f join pg_namespace n on n.oid = f.pronamespace
  where n.nspname = 'public' and f.prokind = 'f'

  union all
  -- 5. como o sistema decide quem é admin
  select 5, 'is_admin', 'definicao', regexp_replace(pg_get_functiondef(f.oid), '\s+', ' ', 'g'), 'revisar'
  from pg_proc f join pg_namespace n on n.oid = f.pronamespace
  where n.nspname = 'public' and f.proname = 'is_admin'

  union all
  -- 6. buckets de arquivos (Storage)
  select 6, 'storage', b.id::text, case when b.public then 'PUBLICO' else 'privado' end,
         case when b.public then 'ATENCAO: arquivos acessiveis por link sem login' else 'ok' end
  from storage.buckets b

  union all
  -- 7. contas
  select 7, 'contas', 'usuarios', count(*)::text || ' contas, ' || count(*) filter (where email_confirmed_at is null)::text || ' sem confirmar, '
         || count(*) filter (where last_sign_in_at is null)::text || ' nunca entraram', 'info'
  from auth.users
)
select secao, item, detalhe, alerta
from r
order by case when alerta like 'CRITICO%' then 0 when alerta like 'ATENCAO%' then 1 when alerta = 'revisar' then 2 else 3 end, ord, item;
