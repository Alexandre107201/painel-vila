"""Maintenance only: manually authenticate in an isolated visible browser."""
import getpass
import json
from playwright.sync_api import sync_playwright
from capture import ROOT
import vault

def main():
    config = json.loads((ROOT / 'config.json').read_text(encoding='utf-8-sig'))
    if (ROOT / 'secrets.dpapi').exists():
        secrets = vault.read(ROOT / 'secrets.dpapi')
    else:
        secrets = {'writer_email': input('E-mail do usuário Supabase exclusivo de CMV: ').strip(),
                   'writer_password': getpass.getpass('Senha desse usuário (oculta): ')}
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=False)
        try:
            context = browser.new_context(locale='pt-BR', timezone_id='America/Sao_Paulo')
            page = context.new_page()
            page.goto('https://www.clientes.hands-ai.com.br/dre')
            input('Faça login no Hands na janela de manutenção e abra a DRE. Depois pressione Enter aqui: ')
            if not page.url.startswith('https://www.clientes.hands-ai.com.br/dre'):
                raise ValueError('DRE não aberta; sessão não salva')
            secrets['hands_state'] = context.storage_state(indexed_db=True)
            vault.write(ROOT / 'secrets.dpapi', secrets)
            print('Sessão criptografada para este usuário Windows. Nenhuma senha Hands foi gravada.')
        finally:
            browser.close()

if __name__ == '__main__':
    main()
