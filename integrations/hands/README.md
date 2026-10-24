# CMV Hands — instalação e homologação no Windows

Estado: implementação preparada, ainda NÃO homologada com a DRE real nem instalada no computador da empresa. Produção não alterada. Leia também RELATORIO.md.

## Arquivos e arquitetura

- `../../painel-atual.html`: indicador no topo, consolidado Vila Fit / Vila Gourmet, sempre mês atual em Brasília, independente dos filtros de vendas. Meta 40%; alerta acima dela; data da captura; aviso após 2 horas sem atualização. Não atribui o consolidado individualmente à Fit ou à Gourmet.
- `../../sql/hands-cmv-setup.sql`: tabela independente, histórico de sucessos, restrições e RLS. Não altera tabelas ou funções da Teknisa. NÃO executar na produção nesta etapa.
- `capture.py`: captura única headless, conferência de operação/competência e custos/receitas, escrita somente após validação.
- `vault.py`: sessão Hands e credenciais do usuário Supabase exclusivo protegidas com DPAPI CurrentUser. Senha do Hands não é armazenada; usa a sessão autenticada.
- `setup_session.py`: autenticação manual inicial ou renovação, exclusivamente em manutenção.
- `run.ps1`: execução sem sobreposição e log limitado; `install-task.ps1`: agenda a cada 60 minutos por 10 anos, inclusive sem usuário conectado.
- `config.example.json`: modelo sem segredos; `requirements.txt`: dependências fixadas; `tests/`: validações locais.

Fluxo: Agendador Windows → Playwright isolado → Hands DRE → validação → Supabase Auth com usuário exclusivo → INSERT no histórico → painel consulta o último sucesso da competência corrente.

O painel reaproveita o login já existente em “Importar relatório”. Não é necessário importar qualquer arquivo para consultar o CMV. Apenas os dois administradores já autorizados na política atual de importação podem ler o novo indicador; valores financeiros de custos e receitas não são expostos à consulta do navegador. O robô usa `app_metadata.hands_cmv_writer=true`, atribuída por administrador, e não recebe chave administrativa.

## 1. Preparar o computador da empresa

1. Use Windows atualizado, com internet, data/hora corretas e sem suspensão durante o horário de operação. Tela pode ficar bloqueada; computador desligado não captura. A tarefa executa ao retornar após horário perdido, sem reconstruir capturas passadas.
2. Peça ao técnico uma conta Windows exclusiva, por exemplo `VilaHands`, com senha. Funcionários devem usar outra conta sem acesso à pasta. Não use a conta ou o perfil de navegador do robô Teknisa.
3. Instale Python 3.12 ou superior de python.org, com `py` disponível. Não altere a instalação Python usada pela Teknisa.
4. Baixe a branch `feat/cmv-hands-20261024`. Copie a pasta `integrations\hands` para `C:\VilaHands\hands`. Não substitua arquivos do robô antigo.
5. Entre na conta exclusiva. Em PowerShell, configure a pasta (ajuste o caminho se necessário):

```powershell
Set-Location C:\VilaHands\hands
$account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
icacls . /inheritance:r
icacls . /grant:r "${account}:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" /T
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m playwright install chromium
Copy-Item config.example.json config.json
```

Em Windows traduzido, o grupo `BUILTIN\Administrators` pode precisar ser substituído por seu nome local ou SID `*S-1-5-32-544`. Confirme as permissões com o técnico. DPAPI depende dessa mesma conta e máquina; o arquivo criptografado não é um backup portável de sessão.

## 2. Preparar banco de homologação separado

1. Use um projeto Supabase de homologação separado. Não direcione `config.json` ao banco de produção durante os testes de escrita.
2. Execute `sql/hands-cmv-setup.sql` nesse banco. O arquivo é transacional e intencionalmente falha se a tabela já existir, evitando reconfiguração silenciosa.
3. Os UUIDs da política de leitura correspondem aos dois administradores encontrados no projeto original. No ambiente de homologação, ajuste esses UUIDs para o usuário de teste autorizado. Para a futura produção, mantenha os UUIDs verificados ou revise explicitamente a lista.
4. Crie em Supabase Authentication um usuário exclusivo para o capturador, com e-mail confirmado e senha forte; não conceda a ele permissões de importação da Teknisa.
5. Um administrador deve definir **app_metadata**, e nunca user_metadata, para esse usuário. Exemplo para revisão no SQL Editor do ambiente correto (substitua o UUID; não execute literalmente):

```sql
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
                       || '{"hands_cmv_writer":true}'::jsonb
where id = 'UUID_DO_USUARIO_EXCLUSIVO';
```

6. Em `config.json`, informe `supabase_url` do ambiente de homologação e a chave publicável correspondente em `publishable_key`. Não use `service_role` ou chave secreta. Nunca coloque a senha na configuração ou no HTML.
7. Para testar o indicador contra homologação, use uma cópia local do HTML e a URL/chave pública do banco de teste. O HTML na branch preserva o endereço original para a futura publicação; não aplique o SQL na produção apenas para testar essa branch.

## 3. Autenticar o Hands em manutenção

Faça isto fora da visão dos funcionários, na conta exclusiva do Windows (ou em sessão administrativa remota privada). Este é o único passo que abre uma janela visível; a captura agendada nunca abre janela.

```powershell
Set-Location C:\VilaHands\hands
.\.venv\Scripts\python.exe setup_session.py
```

1. Informe o e-mail e a senha do usuário exclusivo do Supabase quando o terminal pedir. A senha fica oculta na digitação.
2. Na janela isolada, faça login no Hands diretamente. Resolva autenticação adicional se solicitada.
3. Abra a DRE e volte ao terminal para pressionar Enter.
4. O script salva `secrets.dpapi`, criptografado para essa conta Windows. Não envie esse arquivo por WhatsApp, chat ou GitHub.

Se a sessão expirar, o robô falha sem abrir navegador visível e sem gravar zero. Renove com esse mesmo procedimento em manutenção. Não há promessa de sessão eterna: a duração é controlada pelo Hands.

## 4. Homologar os seletores reais da DRE — etapa pendente

A sessão Hands não estava autenticada no ambiente de desenvolvimento; os seletores internos não foram inventados. O código recusa captura enquanto `selectors_validated` for `false`.

Um técnico com acesso autenticado deve inspecionar a DRE e preencher `config.json`:

| Campo | O que deve apontar |
|---|---|
| operation_select | Select nativo ou controle para escolher operação |
| operation_option | Contêiner da lista de opções, se customizado; `null` para select nativo |
| period_select / period_option | Controles equivalentes do período “Mês Atual” |
| apply_button | Botão de aplicar/atualizar que dispara a atualização da DRE |
| report_response_url_pattern | Regex específica do endpoint de atualização, observado na rede após o clique |
| operation_evidence | Texto da operação efetivamente carregada no relatório, não apenas uma opção de menu |
| month_evidence | Competência efetivamente carregada no relatório, incluindo ano |
| month_format | Formato Python `strptime` dessa evidência, por exemplo `%m/%Y` |
| report | Uma única tabela da DRE, com `thead th` e `tbody tr/td` |
| busy | Indicador de carregamento que deve sumir; `null` se não houver |
| headers | Textos exatos dos cabeçalhos de descrição, valor e percentual |

O adaptador atual exige uma tabela HTML, cabeçalhos únicos e linhas exatas “CUSTOS COM MERCADORIAS” e “RECEITAS SOBRE VENDAS”. Se a DRE usar grid virtual, cabeçalhos repetidos, datas em texto não compatíveis, atualização automática sem botão ou outra estrutura, será necessário ajustar `capture.py` e seus testes antes de homologar. Não basta mudar `selectors_validated`.

Confirme que operação e competência pertencem ao resultado carregado, que a resposta de atualização é específica da DRE e que valores antigos não aparecem como resultado novo durante carregamento. Só depois marque `selectors_validated=true`.

## 5. Testar antes de gravar

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\.venv\Scripts\python.exe capture.py --dry-run
```

`--dry-run` não autentica no Supabase nem grava no banco; lê o Hands, valida e renova apenas o arquivo local da sessão. O provisionamento inicial ainda solicita as credenciais do usuário exclusivo, pois o mesmo cofre será usado depois.

Confira simultaneamente no Hands:

1. Operação Vila Fit / Vila Gourmet e competência corrente.
2. Percentual da coluna `%` da linha CUSTOS COM MERCADORIAS.
3. Custos e receitas; tolerância de arredondamento de 0,02 ponto percentual.
4. A referência informada de outubro/2026 (47,90%, custos R$ 192.718,18 e receitas R$ 402.366,40) foi usada em testes, NÃO foi gravada como captura real. Valores atuais podem ter mudado.
5. Simule sessão expirada e seletores errados: a execução deve terminar com código 1, sem INSERT.

Depois, com a URL de homologação conferida:

```powershell
.\.venv\Scripts\python.exe capture.py
```

No SQL Editor da homologação, confira competência, operação e horário da última linha. Teste também anon sem acesso, usuário comum sem leitura, administrador autorizado e escritor sem UPDATE/DELETE. Execute os advisors do Supabase antes da aprovação.

## 6. Validar painel e instalar a tarefa

1. Abra a cópia do Dashboard Antigo em servidor local; entre pelo botão “Entrar para ver CMV”, usando administrador autorizado da homologação. Feche o modal sem importar arquivo.
2. Confira percentual, meta, alerta, competência e última captura.
3. Mude filtros de vendas: o CMV deve continuar identificado como consolidado do mês atual.
4. Simule falha de consulta após sucesso: mantenha último valor com aviso. Sem sucesso anterior, mostre “—”. Captura com mais de 2 horas deve exibir atraso.
5. Saia/troque o usuário: o indicador deve ocultar o dado.
6. Com a tarefa aprovada para esse ambiente, abra PowerShell elevado **na mesma conta Windows** da sessão DPAPI:

```powershell
Set-Location C:\VilaHands\hands
.\install-task.ps1
Start-ScheduledTask -TaskName Vila-Hands-CMV
Get-ScheduledTaskInfo -TaskName Vila-Hands-CMV
Get-Content .\capture.log -Tail 20
```

A tarefa usa logon com senha e roda sem sessão interativa. Não utiliza o notebook pessoal. Se uma política corporativa impedir scripts/agendamento ou logon em lote, o técnico deve revisar a política aplicável; não desative proteções globalmente.

Valide com tela bloqueada e usuário desconectado, reinicie o computador e confirme nova execução. Verifique código de saída 0, nova linha no banco e ausência de janela. O agendamento dura 10 anos e deve ser renovado antes do vencimento. Teste coexistência com a Teknisa e monitore CPU/RAM na máquina real. Esta coexistência ainda não foi medida.

## 7. Publicação futura — somente após validação

Nenhuma destas ações foi executada na produção:

1. Revisar/aprovar o diff e os resultados da homologação.
2. Aplicar o SQL no Supabase original e criar o usuário escritor exclusivo nele; conferir RLS/advisors.
3. Configurar o robô Windows com URL/chave pública e credenciais do escritor de produção; repetir captura real conferida.
4. Publicar somente `painel-atual.html` após aprovação. V2, Teknisa e demais arquivos compartilhados permanecem como estão.
5. Testar no desktop e no PWA; a estratégia atual de navegação busca HTML na rede. Se o aparelho permanecer com versão antiga, feche/reabra online e confira o novo indicador. Não mudamos o service worker nesta branch.

## Operação e reversão

- Atualizar no painel consulta o Supabase; não dispara o robô nem altera a DRE.
- Logs ficam em `capture.log`, com rotação para `.log.1`; falhas geram código 1. Não há alerta externo automático: revisar Histórico da tarefa/log e o aviso de atraso no painel.
- Em virada de mês, nenhuma captura do mês anterior será mostrada como atual.
- A tabela é histórica e recebe apenas sucessos. Falhas ficam no log local. Não há limpeza automática do histórico; aproximadamente 24 linhas/dia por máquina.
- Desativar apenas esta integração: `Disable-ScheduledTask -TaskName Vila-Hands-CMV`. Não pare tarefas da Teknisa.
- Reverter UI: restaurar `painel-atual.html` a partir do backup `backup-antes-cmv-hands-20261024`, após conferir mudanças posteriores. Preserve a tabela para auditoria.
- Se uma conta/sessão for comprometida, revogue as sessões no respectivo serviço e troque credenciais. Remover o arquivo local sozinho não revoga tokens já emitidos.
