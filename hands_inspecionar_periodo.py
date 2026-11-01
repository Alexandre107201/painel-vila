"""Inspeciona somente os controles do periodo personalizado; nao grava dados."""
from pathlib import Path
import json
from playwright.sync_api import sync_playwright
import vault

def main():
    root = Path(__file__).resolve().parent
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=True)
        try:
            context = browser.new_context(
                storage_state=vault.read(root / 'hands-session.dpapi'),
                viewport={'width':1440,'height':1000},
                locale='pt-BR',timezone_id='America/Sao_Paulo')
            page = context.new_page()
            page.goto('https://www.clientes.hands-ai.com.br/dre',
                      wait_until='domcontentloaded',timeout=60000)
            page.get_by_role('button',name='Per\u00edodo Personalizado',exact=True).click(timeout=60000)
            page.wait_for_timeout(1000)
            controls = page.evaluate("""() => {
                const visible = e => e.getClientRects().length > 0;
                const describe = e => ({
                    tipo:e.type, texto:(e.innerText || '').trim().slice(0,140),
                    label:e.getAttribute('aria-label'),
                    placeholder:e.getAttribute('placeholder'),
                    nome:e.getAttribute('name'), id:e.id,
                    icone:e.querySelector('svg')?.getAttribute('class')
                });
                return {
                    campos:[...document.querySelectorAll('input,select')].filter(visible).map(describe),
                    dialogos:[...document.querySelectorAll('[role="dialog"],[role="alertdialog"]')]
                        .filter(visible).map(e=>e.innerText.trim().slice(0,3000)),
                    botoes:[...document.querySelectorAll('button')].filter(visible)
                        .filter(e=>!(e.getAttribute('aria-label') || '').includes('coment'))
                        .slice(0,90).map(describe)
                };
            }""")
            print(json.dumps(controls,ensure_ascii=False,indent=2))
            print('INSPECAO CONCLUIDA. Nenhum dado gravado; credenciais nao foram exibidas.')
        finally:
            browser.close()
if __name__ == '__main__':
    try:
        main()
    except Exception as erro:
        print('INSPECAO NAO CONCLUIDA: '+type(erro).__name__)
        raise SystemExit(1)
