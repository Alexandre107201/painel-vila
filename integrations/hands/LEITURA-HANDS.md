# Etapa de leitura autenticada, antes de configurar o banco

Atualização de 24/10/2026: a estrutura da DRE carregada foi fornecida pelo usuário e analisada localmente. O novo adaptador `hands_dom.py` foi executado sobre esse DOM, sem acesso à rede, e retornou corretamente operação, competência, percentual com ponto decimal e valores. O HTML privado não está incluído no repositório.

`hands_check.py` permite criar a sessão DPAPI e testar a leitura sem configurar Supabase nem informar credenciais de escritor. Execute na pasta exclusiva e na mesma conta Windows que irá executar o robô:

```cmd
.venv\Scripts\python.exe hands_check.py --login
```

Faça login diretamente na janela de manutenção, selecione a operação Vila Fit / Vila Gourmet e Mês Atual. Volte ao terminal e pressione Enter. Somente se a DRE validar, será salvo `hands-session.dpapi` protegido com DPAPI CurrentUser. Não envie esse arquivo. Nenhuma senha Hands é solicitada pelo terminal.

Depois, execute um teste sem janela:

```cmd
.venv\Scripts\python.exe hands_check.py
```

O teste abre contexto novo, reutiliza a sessão criptografada e confere duas leituras consecutivas da DRE. Valida o tab Mês Atual, a operação completa, a competência do próprio relatório e o percentual contra os valores financeiros. Não envia dados ao banco nem atualiza o dashboard. Se a sessão expirar, encerra com falha; não abre janela como fallback.

Este comando apenas verifica a operação selecionada; não troca automaticamente uma operação incorreta. O seletor aberto de operações e o ciclo de atualização via rede ainda precisam ser homologados antes de integrar o adaptador ao `capture.py` agendado. A tabela Supabase, as credenciais do escritor e a publicação continuam pendentes. Não instale o agendamento nesta etapa.

Para proteção contra funcionários que utilizem a mesma conta Windows, DPAPI sozinho não basta: antes da operação permanente, utilize conta dedicada e ACL restrita, como descrito no guia. O teste pode ser realizado em manutenção na conta atual; eventual troca de conta exige nova autenticação.
