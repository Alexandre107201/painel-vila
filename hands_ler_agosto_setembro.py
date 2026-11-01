"""Captura somente leitura dos fechamentos de agosto e setembro de 2026."""
from pathlib import Path
from datetime import datetime, timezone
import calendar
import json
import re
import sys
from playwright.sync_api import sync_playwright, TimeoutError as BrowserTimeout
from core import OPERATION, validate, number_br
from hands_publish import MONTHS, validated_percent, empty_report_confirmed
import vault

ROOT = Path(__file__).resolve().parent
MONTH_NAMES = ['Janeiro','Fevereiro','Mar\u00e7o','Abril','Maio','Junho',
               'Julho','Agosto','Setembro','Outubro','Novembro','Dezembro']

STEP = 'inicio'
def step(message):
    global STEP
    STEP = message
    print('ETAPA: '+message,flush=True)

def snapshot_month(page, expected):
    operation = page.locator('header button[aria-haspopup="menu"]').filter(
        has=page.locator('img[alt="VILA FIT / VILA GOURMET"]')).filter(visible=True)
    if operation.count() != 1 or ' '.join(operation.inner_text().split()).upper() != OPERATION.upper():
        raise ValueError('Operacao diferente de VILA FIT / VILA GOURMET')
    heading = page.get_by_role('heading', name='Demonstrativo de Resultados do Exerc\u00edcio', exact=True)
    if heading.count() != 1:
        raise ValueError('DRE ausente ou ambigua')
    card = heading.locator('xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " bg-card ")][1]')
    if card.count() != 1:
        raise ValueError('Bloco da DRE nao identificado')
    month_label = card.locator('p').filter(has=page.locator('button[aria-label="Adicionar coment\u00e1rio ao m\u00eas"]'))
    year, month = int(expected[:4]), int(expected[5:7])
    wanted = MONTHS[month-1] + '/' + str(year)[2:]
    if month_label.count() != 1 or month_label.inner_text().strip().lower() != wanted:
        raise ValueError('Competencia da DRE diferente da solicitada')
    table = card.locator('table')
    if table.count() != 1:
        raise ValueError('Tabela ausente ou ambigua')
    headers = [x.strip() for x in table.locator('thead th').all_inner_texts()]
    required = ['Plano de Contas', 'Valores', '%']
    if any(headers.count(x) != 1 for x in required):
        raise ValueError('Cabecalhos da DRE mudaram')
    indexes = [headers.index(x) for x in required]
    def row(label):
        matches = []
        for r in table.locator('tbody tr').all():
            values = [x.strip() for x in r.locator('td').all_inner_texts()]
            if len(values) == len(headers) and values[indexes[0]] == label:
                matches.append(values)
        if len(matches) != 1:
            raise ValueError('Linha financeira ausente ou ambigua')
        return matches[0]
    costs, revenue = row('CUSTOS COM MERCADORIAS'), row('RECEITAS SOBRE VENDAS')
    if empty_report_confirmed(costs[indexes[2]], costs[indexes[1]], revenue[indexes[1]]):
        return dict(operation=OPERATION, competence=expected, cmv_percent=0.0,
                    merchandise_cost=0.0, sales_revenue=0.0)
    pct = validated_percent(costs[indexes[2]], costs[indexes[1]], revenue[indexes[1]])
    if number_br(costs[indexes[1]]) == 0 and number_br(revenue[indexes[1]]) == 0 and pct == '0,00%':
        # Competencia, operacao, linhas e cabecalhos ja foram conferidos.
        return dict(operation=OPERATION, competence=expected, cmv_percent=0.0,
                    merchandise_cost=0.0, sales_revenue=0.0)
    return validate(dict(operation=OPERATION, month=expected, percent=pct,
                         costs=costs[indexes[1]], revenue=revenue[indexes[1]]), expected)


def calendar_scope(dialog, index):
    arrows = dialog.locator('button:has(svg.lucide-chevron-left)')
    if arrows.count() != 2:
        raise ValueError('Esperava dois calendarios independentes')
    root = arrows.nth(index).locator('xpath=ancestor::div[.//button[@name="day"]][1]')
    if root.count() != 1 or root.locator('button[name="day"]').count() < 28:
        raise ValueError('Calendario nao identificado com seguranca')
    if root.locator('button:has(svg.lucide-chevron-left)').count() != 1:
        raise ValueError('Escopo do calendario ambiguo')
    return root

def navigate(dialog, index, year, month):
    expected_name = MONTH_NAMES[month-1]
    for _ in range(15):
        step('localizar calendario '+str(index+1)+' para '+expected_name+'/'+str(year))
        root = calendar_scope(dialog,index)
        print('CALENDARIO '+str(index+1)+': '+repr(root.locator('button:not([name="day"])').all_inner_texts()),flush=True)
        if (root.get_by_role('button',name=expected_name,exact=True).count() == 1
            and root.get_by_role('button',name=str(year),exact=True).count() == 1):
            return
        step('voltar um mes no calendario '+str(index+1))
        root.locator('button:has(svg.lucide-chevron-left)').click()
    raise ValueError('Nao alcancei o mes solicitado; leitura cancelada')


def select_day(dialog, index, day, last=False):
    root = calendar_scope(dialog,index)
    buttons = root.locator('button[name="day"]')
    matches = []
    for position in range(buttons.count()):
        button = buttons.nth(position)
        if button.inner_text().strip() == str(day):
            matches.append(button)
    print('DIA '+str(day)+': '+str(len(matches))+' botao(oes) com texto exato',flush=True)
    if not matches:
        raise ValueError('Dia nao encontrado pelo texto no calendario')
    button = matches[-1] if last else matches[0]
    if not button.is_visible() or not button.is_enabled():
        raise ValueError('Dia selecionado esta oculto ou desabilitado; nada importado')
    button.click(timeout=10000)

def select_month(page, competence):
    year,month = int(competence[:4]),int(competence[5:7])
    last = calendar.monthrange(year,month)[1]
    start = f'{year:04d}-{month:02d}-01'
    end = f'{year:04d}-{month:02d}-{last:02d}'
    step('abrir Periodo Personalizado')
    page.get_by_role('button',name='Per\u00edodo Personalizado',exact=True).click()
    dialog = page.get_by_role('dialog').filter(has_text='Selecione o per\u00edodo')
    if dialog.count()!=1:
        raise ValueError('Dialogo de datas ausente ou ambiguo')
    navigate(dialog,0,year,month)
    navigate(dialog,1,year,month)
    step('selecionar dia 1 do mes inicial')
    select_day(dialog,0,1)
    if not dialog.is_visible():
        raise ValueError('Filtro fechou antes de selecionar a data final')
    navigate(dialog,1,year,month)
    step('selecionar dia '+str(last)+' do mes final')
    select_day(dialog,1,last,last=True)
    if dialog.is_visible():
        page.keyboard.press('Escape')
    step('aguardar atualizacao apos datas')
    page.wait_for_load_state('networkidle',timeout=45000)
    return start,end


def safe_date_evidence(bodies):
    evidence = []
    def walk(value, path='', date_context=False):
        if isinstance(value,dict):
            for key, child in value.items():
                marked = re.search(r'date|data|start|end|from|to$|month|mes|period|ano|year|inicio|fim',str(key),re.I) is not None
                walk(child,path+'.'+str(key),date_context or marked)
        elif isinstance(value,list):
            for index,child in enumerate(value):
                walk(child,path+'['+str(index)+']',date_context)
        elif date_context and isinstance(value,str):
            if re.fullmatch(r'\d{4}-\d{2}(?:-\d{2})?(?:T[0-9:.,+Z-]+)?|\d{2}/\d{2}/\d{4}',value):
                evidence.append({'campo':path,'data':value[:32]})
    for body in bodies:
        try:
            walk(json.loads(body))
        except (ValueError,TypeError):
            pass
    # Nunca imprime corpos completos, senhas, tokens ou valores financeiros.
    unique = {json.dumps(item,sort_keys=True):item for item in evidence}
    return list(unique.values())

def read_month(page, competence):
    requests_seen = []
    statuses = []
    def record_request(request):
        if request.resource_type not in ('xhr','fetch'):
            return
        # Datas sao conferidas em memoria; nao imprime corpo, cabecalhos ou tokens.
        body = request.post_data or ''
        requests_seen.append(body)
    def record_response(response):
        if response.request.resource_type in ('xhr','fetch'):
            statuses.append(response.status)
    page.on('request',record_request)
    page.on('response',record_response)
    try:
        start,end = select_month(page,competence)
        step('confirmar resposta ao clicar Atualizar')
        with page.expect_response(lambda r:r.request.resource_type in ('xhr','fetch')
                                  and '/rest/v1/rpc' in r.url,timeout=45000) as pending:
            page.get_by_role('button',name='Atualizar',exact=True).click()
        pending.value.body()
        page.wait_for_load_state('networkidle',timeout=45000)
        if not statuses or any(code>=400 for code in statuses):
            raise ValueError('Resposta do Hands nao confirmada')
        start_br=datetime.strptime(start,'%Y-%m-%d').strftime('%d/%m/%Y')
        end_br=datetime.strptime(end,'%Y-%m-%d').strftime('%d/%m/%Y')
        if not any((start in body or start_br in body) and (end in body or end_br in body)
                   for body in requests_seen):
            print('DATAS DETECTADAS NAS CONSULTAS:',json.dumps(safe_date_evidence(requests_seen),ensure_ascii=False),flush=True)
            try:
                observed=snapshot_month(page,competence)
                print('DRE EXIBIDA E VALIDADA:',observed['competence'],'CMV:',observed['cmv_percent'],flush=True)
            except (ValueError,BrowserTimeout) as erro:
                print('VALIDACAO DA DRE:',str(erro) if isinstance(erro,ValueError) else 'Tempo excedido',flush=True)
            raise ValueError('Datas inicial e final nao confirmadas nas consultas; nada importado')
        previous=None
        last_error='DRE historica nao estabilizou'
        for _ in range(20):
            try:
                current=snapshot_month(page,competence)
            except (ValueError,BrowserTimeout) as erro:
                current=None
                last_error=str(erro) if isinstance(erro,ValueError) else 'Tempo excedido'
            if current is not None and current==previous:
                current['captured_at']=datetime.now(timezone.utc).isoformat()
                return current
            previous=current
            page.wait_for_timeout(1000)
        raise ValueError(last_error)
    finally:
        page.remove_listener('request',record_request)
        page.remove_listener('response',record_response)

def main():
    with sync_playwright() as pw:
        browser=pw.chromium.launch(headless=True)
        try:
            context=browser.new_context(storage_state=vault.read(ROOT/'hands-session.dpapi'),
                viewport={'width':1440,'height':1000},locale='pt-BR',timezone_id='America/Sao_Paulo')
            results=[]
            for competence in ('2026-08-01','2026-09-01'):
                print('CONSULTANDO PERIODO COMPLETO: '+competence[:7],flush=True)
                page=context.new_page()
                page.set_default_timeout(20000)
                try:
                    step('abrir pagina DRE')
                    page.goto('https://www.clientes.hands-ai.com.br/dre',
                              wait_until='domcontentloaded',timeout=60000)
                    step('aguardar titulo DRE')
                    page.get_by_role('heading',name='Demonstrativo de Resultados do Exerc\u00edcio',
                                     exact=True).wait_for(timeout=60000)
                    step('aguardar carregamento inicial')
                    page.wait_for_load_state('networkidle',timeout=45000)
                    result=read_month(page,competence)
                    results.append(result)
                    print('LEITURA VALIDADA: '+competence[:7]+' | CMV '+str(result['cmv_percent'])+'%',flush=True)
                finally:
                    page.close()
            output=ROOT/'cmv_agosto_setembro_leitura.json'
            output.write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
            print('RESULTADO PARA CONFERENCIA:')
            print(json.dumps(results,ensure_ascii=False,indent=2))
            print('LEITURA CONCLUIDA. Nenhum dado gravado no banco; robos e sessoes preservados.')
        finally:
            browser.close()

if __name__=='__main__':
    try:
        main()
    except Exception as erro:
        safe=str(erro) if isinstance(erro,ValueError) else type(erro).__name__
        if isinstance(erro,BrowserTimeout):
            safe += ' | '+str(erro).splitlines()[0][:180]
        safe += ' | ETAPA: '+STEP
        print('LEITURA NAO CONCLUIDA: '+safe,file=sys.stderr)
        raise SystemExit(1)


