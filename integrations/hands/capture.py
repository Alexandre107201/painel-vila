"""Independent hourly one-shot. No fallback to zero, headed or persistent profile."""
import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from playwright.sync_api import sync_playwright
from core import OPERATION, month_now, validate
import vault

ROOT = Path(__file__).resolve().parent

def api(config, path, body, token=None, prefer=None):
    headers = {'apikey': config['publishable_key'], 'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if prefer:
        headers['Prefer'] = prefer
    req = Request(config['supabase_url'] + path, data=json.dumps(body).encode(), headers=headers)
    try:
        with urlopen(req, timeout=30) as r:
            data = r.read()
            return json.loads(data) if data else None
    except HTTPError as e:
        # Response bodies can contain sensitive data. Only a safe status is logged.
        raise RuntimeError('Supabase HTTP ' + str(e.code)) from None

def choose(page, selector, option_selector, label):
    control = page.locator(selector)
    if option_selector:
        control.click()
        page.locator(option_selector).get_by_text(label, exact=True).click()
    else:
        control.select_option(label=label)

def snapshot(page, config, expected):
    s = config['selectors']
    operation = page.locator(s['operation_evidence']).inner_text().strip()
    month_text = page.locator(s['month_evidence']).inner_text().strip()
    parsed = datetime.strptime(month_text, config['month_format'])
    month = parsed.strftime('%Y-%m-01')
    table = page.locator(s['report'])
    # Headers determine indexes; never assume that the last % is the correct column.
    headers = [x.strip() for x in table.locator('thead th').all_inner_texts()]
    h = config['headers']
    indexes = {}
    for key in ('label', 'percent', 'amount'):
        if headers.count(h[key]) != 1:
            raise ValueError('Cabeçalho ausente ou ambíguo')
        indexes[key] = headers.index(h[key])
    rows = table.locator('tbody tr').all()
    def cells_for(label):
        matches = []
        for row in rows:
            cells = [x.strip() for x in row.locator('td').all_inner_texts()]
            if len(cells) > max(indexes.values()) and cells[indexes['label']].upper() == label:
                matches.append(cells)
        if len(matches) != 1:
            raise ValueError('Linha ausente ou ambígua')
        return matches[0]
    costs = cells_for('CUSTOS COM MERCADORIAS')
    revenue = cells_for('RECEITAS SOBRE VENDAS')
    raw = dict(operation=operation, month=month, percent=costs[indexes['percent']],
               costs=costs[indexes['amount']], revenue=revenue[indexes['amount']])
    return validate(raw, expected)

def capture(context, config):
    if config.get('selectors_validated') is not True:
        raise ValueError('Seletores da DRE ainda não homologados')
    expected = month_now()
    s = config['selectors']
    page = context.new_page()
    page.set_default_timeout(20000)
    page.goto(config['url'], wait_until='domcontentloaded')
    if '/auth' in page.url:
        raise ValueError('Sessão Hands expirada; renovar em manutenção')
    choose(page, s['operation_select'], s.get('operation_option'), OPERATION)
    choose(page, s['period_select'], s.get('period_option'), 'Mês Atual')
    if not s.get('apply_button') or not config.get('report_response_url_pattern'):
        raise ValueError('Falta configurar atualização confirmada da DRE')
    with page.expect_response(re.compile(config['report_response_url_pattern']), timeout=30000) as pending:
        page.locator(s['apply_button']).click()
    response = pending.value
    if not response.ok:
        raise ValueError('Atualização da DRE falhou')
    response.body()  # Wait for the report response to be fully received; never log it.
    if s.get('busy'):
        page.locator(s['busy']).wait_for(state='hidden')
    # Require report-bound identity/month and two identical validated snapshots.
    # Config approval must confirm these evidences belong to the loaded report.
    previous = None
    for _ in range(30):
        try:
            current = snapshot(page, config, expected)
        except (ValueError, TimeoutError):
            current = None
        if current is not None and current == previous:
            if month_now() != expected:
                raise ValueError('Mês mudou durante a captura')
            return current
        previous = current
        page.wait_for_timeout(1000)
    raise ValueError('DRE não estabilizou com operação e competência válidas')

def run(dry_run=False):
    config = json.loads((ROOT / 'config.json').read_text(encoding='utf-8-sig'))
    if config['url'] != 'https://www.clientes.hands-ai.com.br/dre':
        raise ValueError('Origem Hands inválida')
    if not config['supabase_url'].startswith('https://'):
        raise ValueError('Supabase deve usar HTTPS')
    secrets = vault.read(ROOT / 'secrets.dpapi')
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=True)
        try:
            context = browser.new_context(storage_state=secrets['hands_state'], locale='pt-BR', timezone_id='America/Sao_Paulo')
            payload = capture(context, config)
            if not dry_run:
                token = api(config, '/auth/v1/token?grant_type=password',
                            {'email': secrets['writer_email'], 'password': secrets['writer_password']})['access_token']
                payload['captured_at'] = datetime.now(timezone.utc).isoformat()
                # Append-only audit history: failures never mutate successful captures.
                api(config, '/rest/v1/hands_cmv_captures', payload, token, 'return=minimal')
            secrets['hands_state'] = context.storage_state(indexed_db=True)
            vault.write(ROOT / 'secrets.dpapi', secrets)
            print('VALIDADO ' + payload['competence'] + ' CMV=' + str(payload['cmv_percent']) + (' (SEM GRAVAR)' if dry_run else ' GRAVADO'))
        finally:
            browser.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    try:
        run(args.dry_run)
    except Exception as e:
        # Never emit traceback, page DOM, response body, credentials or session.
        safe = str(e) if isinstance(e, ValueError) else type(e).__name__
        print('FALHA CMV: ' + safe, file=sys.stderr)
        sys.exit(1)
