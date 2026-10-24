"""Maintenance login and headless read-only check. Never calls Supabase API."""
import argparse
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright
from core import month_now
from hands_dom import snapshot_hands
import vault

ROOT = Path(__file__).resolve().parent
URL = 'https://www.clientes.hands-ai.com.br/dre'

def check(login=False):
    path = ROOT / 'hands-session.dpapi'
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=not login)
        try:
            saved = vault.read(path) if path.exists() else None
            if not login and saved is None:
                raise ValueError('Execute hands_check.py --login primeiro')
            context = browser.new_context(storage_state=saved, viewport={'width':1440,'height':1000},
                                          locale='pt-BR', timezone_id='America/Sao_Paulo')
            page = context.new_page()
            page.set_default_timeout(20000)
            page.goto(URL, wait_until='domcontentloaded')
            if login:
                print('Na janela aberta, faça login no Hands e selecione VILA FIT / VILA GOURMET e Mês Atual.')
                input('Quando a DRE estiver carregada, volte aqui e pressione Enter: ')
            expected = month_now()
            page.get_by_role('heading', name='Demonstrativo de Resultados do Exercício', exact=True).wait_for()
            previous = snapshot_hands(page, expected)
            page.wait_for_timeout(1000)
            current = snapshot_hands(page, expected)
            if previous != current or month_now() != expected:
                raise ValueError('Dados mudaram durante a leitura; repita o teste')
            vault.write(path, context.storage_state(indexed_db=True))
            pct = f"{current['cmv_percent']:.2f}".replace('.', ',')
            print('LEITURA VALIDADA | '+current['operation']+' | '+expected[:7]+' | CMV '+pct+'% | SEM GRAVAR NO BANCO')
            print('Sessão protegida salva para este usuário Windows. Não envie o arquivo .dpapi.')
        finally:
            browser.close()

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--login', action='store_true')
    args = p.parse_args()
    try:
        check(args.login)
    except Exception as e:
        print('TESTE NÃO CONCLUÍDO: '+(str(e) if isinstance(e, ValueError) else type(e).__name__),file=sys.stderr)
        sys.exit(1)
