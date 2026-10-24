# Relatório de implementação — 24/10/2026

## Resultado

Preparação em branch `feat/cmv-hands-20261024`, a partir de `main` no commit `78843bb85528cdc59d0e0462b1c014dbdfc3abf0`. O backup remoto `backup-antes-cmv-hands-20261024` existe e não apresentava diferença para essa base na análise. Não houve merge, publicação, alteração de banco de produção nem instalação remota no Windows.

**Não está operacional ainda.** A estrutura e o código estão preparados; a DRE real exige autenticação e homologação do adaptador. O acesso ao Hands neste ambiente redirecionou `/dre` para `/auth`.

## Arquitetura observada

- Repositório com HTML estático, scripts de dados e service worker. Dashboard Antigo em `painel-atual.html`; V2 em `painel-executivo-v2.html`.
- Supabase identificado pelo próprio HTML: `bbhtrxuaumhpqtbcgewc`, projeto `monitor-vila-fit`, PostgreSQL 17.
- Estruturas existentes inspecionadas: `vendas_teknisa`, `painel_resumos_diarios`, `painel_revisoes_diarias`, `painel_conferencias_diarias` e políticas relevantes. O painel possui leitura pública das vendas e autenticação restrita para importação.
- Nenhuma tabela CMV existia na listagem inspecionada.
- Login de importação guarda sessão em `sessionStorage.painel_vila_import_session`. O CMV aproveita essa sessão sem conceder acesso anônimo.
- Não foram encontrados arquivos de configuração do robô Windows Teknisa neste checkout. Portanto, isolamento de arquivos/processos foi implementado, mas coexistência e consumo de recursos precisam ser testados na máquina real.

## Implementado em código

1. Indicador no topo do Dashboard Antigo, consolidado Vila Fit / Vila Gourmet, mês atual em Brasília, meta 40%, diferença em pontos percentuais, horário da captura e aviso de atraso após 2 horas.
2. Consulta automática ao banco a cada 5 minutos com timeout de 15 segundos; botão de atualização. Consulta não dispara captura.
3. Tratamento de sessão expirada, sem dados, resposta inválida e falha de rede. Falha preserva última captura válida em memória apenas enquanto autenticado e na mesma competência; nunca substitui por zero. Logout/troca de sessão limpa o valor.
4. SQL separado e transacional para histórico de capturas válidas, índice, RLS, validações de consistência e permissões por coluna. Sem UPDATE/DELETE para escritor e sem leitura anônima. Custos/receitas ficam fora das colunas liberadas ao navegador.
5. Capturador Playwright headless com contexto próprio, seleção configurável, confirmação de resposta de atualização, duas leituras estáveis, validação de operação/competência/percentual e conferência custos ÷ receitas. Somente sucessos geram INSERT.
6. Proteção DPAPI CurrentUser do estado autenticado e das credenciais do escritor Supabase. Sem senha Hands armazenada e sem chave administrativa no novo HTML ou no robô.
7. Preparação Windows: ambiente Python isolado, sessão manual de manutenção, tarefa não interativa a cada 60 minutos por 10 anos, bloqueio de sobreposição, limite de execução, código de saída e log com rotação.
8. Guia de configuração, homologação, instalação e reversão em README.md.

Os campos CMV já existentes nos demais blocos de vendas permanecem como estavam. Não associamos o percentual consolidado do Hands a operações individuais ou períodos diários. A nova meta de 40% pertence ao indicador Hands.

## Validação executada

- 9 testes Python/Chromium headless com fixtures locais: captura completa em site simulado, cabeçalhos/linhas, operação divergente, competência divergente, linhas duplicadas, bloqueio de configuração não homologada, números brasileiros, referência de 47,90%, rejeição de inconsistências, zero verdadeiro, virada de mês, UI sem login, alerta, atraso, falha após sucesso, logout e resposta inválida.
- SQL executado em PGlite local, um mecanismo PostgreSQL em WASM, com funções `auth.uid()`/`auth.jwt()` simuladas. Validado: criação, bloqueio anon, usuário comum sem leitura/escrita, `user_metadata` sem autoridade, escritor somente INSERT, administradores com leitura, restrição das colunas financeiras, rejeição de percentual inconsistente/data antiga/competência incorreta e preservação do histórico.
- Sintaxe de todos os scripts inline do HTML verificada com Node.
- Diff revisado e `git diff --check` sem erro; nenhuma alteração na V2 ou nos scripts compartilhados de vendas.

O teste SQL local não equivale ao teste da API PostgREST, Supabase Auth ou advisors do projeto real. Os testes de navegador usam fixtures: não comprovam seletores ou funcionamento da DRE Hands real.

## Não executado / depende de configuração

| Dependência | Situação |
|---|---|
| Login Hands e seletores reais da DRE | Pendente; configuração bloqueada por `selectors_validated=false` |
| Estrutura real da tabela e resposta de atualização | Pendente; pode exigir adaptação adicional do capturador |
| Projeto/banco de homologação Supabase e usuário escritor | Não provisionados |
| RLS via API real, autenticação e advisors | Pendentes em homologação |
| Captura real confrontada com o Hands | Não realizada |
| Tabela e usuário escritor na produção | Não criados |
| DPAPI e ACL no Windows | Código preparado; não testado neste ambiente Linux |
| Agendador Windows com usuário desconectado e reinício | Script preparado; não instalado/testado na máquina da empresa |
| Consumo de recursos e coexistência com Teknisa | Pendente na empresa |
| Publicação e PWA no celular | Não executados |
| Comparação visual de todo o dashboard com dados reais | Não executada; testes focaram o novo componente e o diff |

## Observações de segurança e operação

- O SQL é para revisão/homologação; não é um arquivo já aplicado ao Supabase.
- A permissão de leitura usa os dois UUIDs administrativos observados na política existente. No banco de homologação, precisam corresponder aos usuários de teste.
- O usuário escritor será criado separadamente, com escopo por RLS. Não se reutiliza conta administrativa nem chave `service_role`.
- A autenticação inicial/renovação abre janela somente durante manutenção autorizada. A execução agendada nunca faz fallback para modo visível.
- Falhas de captura são registradas localmente; não há notificação externa automática. A UI sinaliza atraso da última captura e falhas de consulta, sem afirmar que uma consulta ao banco comprova saúde do robô.
- Arquivos de sessão, configuração local e logs são ignorados pelo Git. As dependências são instaladas em `.venv` exclusiva.
- O histórico cresce com os sucessos e não possui expurgo automático. Não há histórico centralizado de falhas.

## Próxima validação necessária

Autenticar no Hands em manutenção, ajustar e homologar os seletores contra a DRE real, testar escrita em Supabase separado e instalar/testar o agendamento no Windows da empresa. Somente depois revisar a publicação do Dashboard Antigo e as alterações do banco de produção.
