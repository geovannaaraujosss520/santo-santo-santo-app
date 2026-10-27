# Santo Santo Santo · Catálogo e Devocionário

App web instalável (PWA) para as unidades da rede Santo Santo Santo: catálogo interno de peças dos fornecedores e Devocionário com santos do mês e campanha da loja.

## Funcionalidades

- **Catálogo**: busca, filtros por fornecedor, categoria e garantia, ficha da peça, lista ou blocos.
- **Devocionário**: 463 santos, santas e títulos de Nossa Senhora, santos do mês com calendário, exportação em PDF e planilha.
- **Campanha da loja**: santos em destaque do mês atual e do seguinte, definidos pela franqueadora.
- **Admin**: edição de peças e fotos, importação por planilha, fornecedores ativos e inativos, campanha, santos novos e usuários das unidades.
- **Acesso**: login por unidade, verificação humana (hCaptcha), troca de senha e limite de tentativas.
- **Celular**: instalável na tela inicial e abre sem internet com o último catálogo carregado.

## Rodar

```bash
npm start
```

Abre em http://localhost:3000. Requisito: Node.js 18 ou mais novo. Não há dependências, então não precisa de `npm install`.

## Estrutura

```
server.js                 servidor sem dependências: arquivos do app + cabeçalhos de segurança
package.json              comando de início (npm start)
public/
  index.html              o app (arquivo único: HTML, CSS, JS e bibliotecas embutidas)
  manifest.webmanifest    dados para instalar no celular
  sw.js                   service worker (abre sem internet)
  icons/                  ícones do app (mascote)
supabase/                 scripts SQL do banco
```

## Publicar

- Comando de início: `npm start`
- Comando de build: nenhum
- A porta vem da variável `PORT`, que as hospedagens definem sozinhas.

Depois de publicar num endereço novo, cadastre o domínio no painel do hCaptcha (dashboard.hcaptcha.com). Sem isso, a verificação do login dá erro e ninguém entra.

## Banco de dados (Supabase)

Os scripts ficam em `supabase/` e rodam em **SQL Editor › New query › Run**.

| Script | Para que serve |
| --- | --- |
| `campanha_santos.sql` | Tabela da campanha de santos em destaque |
| `santos_extras.sql` | Tabela dos santos cadastrados pelo admin |
| `gestao_usuarios.sql` | Funções do painel de usuários (criar, listar, redefinir senha, excluir) |
| `corrigir_seguranca.sql` | Regras definitivas: ler só logado, alterar só admin, nada sem login |
| `auditoria_seguranca.sql` | Auditoria somente leitura; não deve aparecer nenhuma linha CRITICO |
| `exigir_troca_senha.sql` | Opcional: obriga a troca de senha no próximo acesso |

O app usa só a chave pública (`anon`) do Supabase, que pode ficar no código; a proteção dos dados está nas regras do banco. **Nunca** coloque neste repositório a chave `service_role`, a Secret Key do hCaptcha ou senhas de usuários.

## Atualizar o app

1. Troque `public/index.html`.
2. Em `public/sw.js`, mude o valor de `VERSAO` (por exemplo, `sss-2026-11-01-1`) para os celulares buscarem a versão nova.
