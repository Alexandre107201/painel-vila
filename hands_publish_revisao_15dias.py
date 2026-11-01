"""CMV: captura horaria atual e revisao diaria do fechamento ate o dia 15."""
import argparse
import json
import re
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo
from playwright.sync_api import sync_playwright, TimeoutError as BrowserTimeout
from capture import api
from core import OPERATION, month_now, validate
from setup_writer import EXPECTED_ID, EXPECTED_EMAIL, PUBLIC_CONFIG
import vault

ROOT = Path(__file__).resolve().parent
MONTHS = ['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez']

def previous_month(current):
    return (date.fromisoformat(current) - timedelta(days=1)).replace(day=1).isoformat()

def review_allowed(today):
    return today.day <= 15

def snapshot(page, expected, tab_name):
    operation = page.locator('header button[aria-haspopup="menu"]').filter(
        has=page.locator('img[alt="VILA FIT / VILA GOURMET"]')).filter(visible=True)
    if operation.count() != 1 or ' '.join(operation.inner_text().split()).upper() != OPERATION.upper():
        raise ValueError('Operacao diferente de VILA FIT / VILA GOURMET')
    tab = page.get_by_role('tab', name=tab_name, exact=True)
    if tab.count() != 1 or tab.get_attribute('aria-selected') != 'true':
        raise ValueError('Aba da competencia nao confirmada')
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
    pct = costs[indexes[2]]
    if not re.fullmatch(r'\d{1,3}(?:[.,]\d{1,2})?\s*%', pct):
        raise ValueError('Formato do percentual Hands mudou')
    return validate(dict(operation=OPERATION, month=expected, percent=pct.replace('.', ','),
                         costs=costs[indexes[1]], revenue=revenue[indexes[1]]), expected)

def refresh_and_capture(page, expected, tab_name):
    page.get_by_role('tab', name=tab_name, exact=True).click()
    page.wait_for_load_state('networkidle', timeout=45000)
    responses = []
    def record_response(response):
        if response.request.resource_type in ('xhr', 'fetch'):
            responses.append(response.status)
    page.on('response', record_response)
    try:
        page.get_by_role('button', name='Atualizar', exact=True).click()
        page.wait_for_load_state('networkidle', timeout=45000)
        if not responses or any(status >= 400 for status in responses):
            raise ValueError('Atualizacao do Hands nao confirmada; nenhum valor sera gravado')
    finally:
        page.remove_listener('response', record_response)
    previous = None
    last_error = 'DRE nao estabilizou'
    for _ in range(20):
        try:
            current = snapshot(page, expected, tab_name)
        except (ValueError, BrowserTimeout) as erro:
            current = None
            last_error = str(erro) if isinstance(erro, ValueError) else 'Tempo de leitura excedido'
        if current is not None and current == previous:
            return current
        previous = current
        page.wait_for_timeout(1000)
    raise ValueError(last_error + '; nada gravado')

def run(dry_run=False, closed=False):
    today = datetime.now(ZoneInfo('America/Sao_Paulo')).date()
    if closed and not review_allowed(today):
        print('REVISAO DISPENSADA: apos o dia 15; ultimo fechamento preservado.')
        return
    current_month = month_now()
    expected = previous_month(current_month) if closed else current_month
    tab_name = 'M\u00eas Anterior' if closed else 'M\u00eas Atual'
    config = json.loads((ROOT / 'config.json').read_text(encoding='utf-8-sig'))
    if any(config.get(k) != v for k, v in PUBLIC_CONFIG.items()):
        raise ValueError('Conexao diferente da configuracao validada')
    writer = vault.read(ROOT / 'writer.dpapi')
    state = vault.read(ROOT / 'hands-session.dpapi')
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=True)
        try:
            context = browser.new_context(storage_state=state, viewport={'width':1440,'height':1000},
                                          locale='pt-BR', timezone_id='America/Sao_Paulo')
            page = context.new_page()
            page.set_default_timeout(20000)
            page.goto('https://www.clientes.hands-ai.com.br/dre', wait_until='domcontentloaded', timeout=60000)
            page.get_by_role('heading', name='Demonstrativo de Resultados do Exerc\u00edcio', exact=True).wait_for(timeout=60000)
            payload = refresh_and_capture(page, expected, tab_name)
            if month_now() != current_month:
                raise ValueError('Mes mudou durante a captura; nada gravado')
            if closed and not review_allowed(datetime.now(ZoneInfo('America/Sao_Paulo')).date()):
                raise ValueError('Prazo de revisao terminou durante a captura; nada gravado')
            if not dry_run:
                session = api(config, '/auth/v1/token?grant_type=password',
                              {'email':writer['writer_email'], 'password':writer['writer_password']})
                user = session.get('user') or {}
                if (user.get('id') != EXPECTED_ID or user.get('email','').lower() != EXPECTED_EMAIL
                        or (user.get('app_metadata') or {}).get('hands_cmv_writer') is not True):
                    raise ValueError('Usuario CMV nao autorizado; nada gravado')
                payload['captured_at'] = datetime.now(timezone.utc).isoformat()
                api(config, '/rest/v1/hands_cmv_captures', payload,
                    session['access_token'], 'return=minimal')
                # No encerramento, restaura a aba atual antes de reutilizar a sessao.
                if closed:
                    try:
                        page.get_by_role('tab', name='M\u00eas Atual', exact=True).click()
                        page.wait_for_load_state('networkidle', timeout=30000)
                    except BrowserTimeout:
                        pass
                vault.write(ROOT / 'hands-session.dpapi', context.storage_state(indexed_db=True))
            pct = f"{payload['cmv_percent']:.2f}".replace('.', ',')
            print(('LEITURA VALIDADA' if dry_run else 'GRAVACAO CONFIRMADA') +
                  ' | ' + payload['operation'] + ' | ' + expected[:7] + ' | CMV ' + pct + '%' +
                  (' | REVISAO DO FECHAMENTO ATE DIA 15' if closed else ' | MES ATUAL'))
            print('SEM GRAVAR NO BANCO' if dry_run else 'Captura enviada ao banco; ultima leitura valida preservada no historico.')
        finally:
            browser.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--closed', action='store_true')
    args = parser.parse_args()
    try:
        run(args.dry_run, args.closed)
    except Exception as e:
        safe = str(e) if isinstance(e, ValueError) or (
            isinstance(e, RuntimeError) and str(e).startswith('Supabase HTTP ')) else type(e).__name__
        print('CAPTURA NAO CONCLUIDA: ' + safe, file=sys.stderr)
        sys.exit(1)

