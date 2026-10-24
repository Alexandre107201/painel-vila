"""Read-only adapter based on the user-supplied rendered Hands DRE DOM."""
import re
from core import OPERATION, validate

MONTHS = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']

def snapshot_hands(page, expected):
    # Desktop layout is intentional: company selector is hidden on narrow screens.
    operation = page.locator('header button[aria-haspopup="menu"]').filter(
        has=page.locator('img[alt="VILA FIT / VILA GOURMET"]')).filter(visible=True)
    if operation.count() != 1 or ' '.join(operation.inner_text().split()).upper() != OPERATION.upper():
        raise ValueError('Selecione a operação VILA FIT / VILA GOURMET')
    tab = page.get_by_role('tab', name='Mês Atual', exact=True)
    if tab.count() != 1 or tab.get_attribute('aria-selected') != 'true':
        raise ValueError('Selecione Mês Atual')
    heading = page.get_by_role('heading', name='Demonstrativo de Resultados do Exercício', exact=True)
    if heading.count() != 1:
        raise ValueError('DRE ausente ou ambígua')
    card = heading.locator('xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " bg-card ")][1]')
    if card.count() != 1:
        raise ValueError('Bloco da DRE não identificado')
    month_label = card.locator('p').filter(has=page.locator('button[aria-label="Adicionar comentário ao mês"]'))
    year, month = int(expected[:4]), int(expected[5:7])
    wanted = MONTHS[month-1] + '/' + str(year)[2:]
    if month_label.count() != 1 or month_label.inner_text().strip().lower() != wanted:
        raise ValueError('Competência da DRE divergente do mês atual')
    table = card.locator('table')
    if table.count() != 1:
        raise ValueError('Tabela ausente ou ambígua')
    headers = [x.strip() for x in table.locator('thead th').all_inner_texts()]
    required = ['Plano de Contas', 'Valores', '%']
    if any(headers.count(x) != 1 for x in required):
        raise ValueError('Cabeçalhos da DRE mudaram')
    indexes = [headers.index(x) for x in required]
    def row(label):
        matches = []
        for r in table.locator('tbody tr').all():
            values = [x.strip() for x in r.locator('td').all_inner_texts()]
            if len(values) == len(headers) and values[indexes[0]] == label:
                matches.append(values)
        if len(matches) != 1:
            raise ValueError('Linha financeira ausente ou ambígua')
        return matches[0]
    costs, revenue = row('CUSTOS COM MERCADORIAS'), row('RECEITAS SOBRE VENDAS')
    pct = costs[indexes[2]]
    if not re.fullmatch(r'\d{1,3}(?:[.,]\d{1,2})?\s*%', pct):
        raise ValueError('Formato do percentual Hands mudou')
    return validate(dict(operation=OPERATION, month=expected, percent=pct.replace('.', ','),
                         costs=costs[indexes[1]], revenue=revenue[indexes[1]]), expected)
