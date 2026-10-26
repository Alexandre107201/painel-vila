"""Headless one-shot using the validated Hands adapter and separate DPAPI vaults."""
import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from playwright.sync_api import sync_playwright, TimeoutError as BrowserTimeout
from capture import api
from core import month_now
from hands_dom import snapshot_hands
from setup_writer import EXPECTED_ID, EXPECTED_EMAIL, PUBLIC_CONFIG
import vault

ROOT = Path(__file__).resolve().parent

def run(dry_run=False):
    config = json.loads((ROOT / 'config.json').read_text(encoding='utf-8-sig'))
    if any(config.get(k) != v for k, v in PUBLIC_CONFIG.items()):
        raise ValueError('Conexão diferente da configuração validada')
    writer = vault.read(ROOT / 'writer.dpapi')
    state = vault.read(ROOT / 'hands-session.dpapi')
    expected = month_now()
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=True)
        try:
            context = browser.new_context(storage_state=state, viewport={'width':1440,'height':1000},
                                          locale='pt-BR', timezone_id='America/Sao_Paulo')
            page = context.new_page()
            page.set_default_timeout(20000)
            page.goto('https://www.clientes.hands-ai.com.br/dre', wait_until='domcontentloaded', timeout=60000)
            page.get_by_role('heading', name='Demonstrativo de Resultados do Exercício', exact=True).wait_for(timeout=60000)
            previous = None
            payload = None
            for _ in range(15):
                try:
                    current = snapshot_hands(page, expected)
                except (ValueError, BrowserTimeout):
                    current = None
                if current is not None and current == previous:
                    payload = current
                    break
                previous = current
                page.wait_for_timeout(1000)
            if payload is None or month_now() != expected:
                raise ValueError('DRE não estabilizou com operação e mês válidos; nada gravado')
            vault.write(ROOT / 'hands-session.dpapi', context.storage_state(indexed_db=True))
            if not dry_run:
                session = api(config, '/auth/v1/token?grant_type=password',
                              {'email':writer['writer_email'], 'password':writer['writer_password']})
                user = session.get('user') or {}
                if (user.get('id') != EXPECTED_ID or user.get('email','').lower() != EXPECTED_EMAIL
                        or (user.get('app_metadata') or {}).get('hands_cmv_writer') is not True):
                    raise ValueError('Usuário CMV não autorizado; nada gravado')
                if month_now() != expected:
                    raise ValueError('Mês mudou durante a captura; nada gravado')
                payload['captured_at'] = datetime.now(timezone.utc).isoformat()
                api(config, '/rest/v1/hands_cmv_captures', payload,
                    session['access_token'], 'return=minimal')
            pct = f"{payload['cmv_percent']:.2f}".replace('.', ',')
            print(('LEITURA VALIDADA' if dry_run else 'GRAVAÇÃO CONFIRMADA') +
                  ' | ' + payload['operation'] + ' | ' + expected[:7] + ' | CMV ' + pct + '%')
            print('SEM GRAVAR NO BANCO' if dry_run else 'Captura enviada ao banco. Dashboard e agendamento não alterados.')
        finally:
            browser.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    try:
        run(args.dry_run)
    except Exception as e:
        safe = str(e) if isinstance(e, ValueError) or (isinstance(e, RuntimeError) and str(e).startswith('Supabase HTTP ')) else type(e).__name__
        print('CAPTURA NÃO CONCLUÍDA: ' + safe, file=sys.stderr)
        sys.exit(1)
