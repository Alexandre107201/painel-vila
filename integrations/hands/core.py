"""Pure validation; no network, credentials or browser dependencies."""
import re
from datetime import datetime
from decimal import Decimal, InvalidOperation
from zoneinfo import ZoneInfo

OPERATION = 'Vila Fit / Vila Gourmet'

def month_now(now=None):
    return (now or datetime.now(ZoneInfo('America/Sao_Paulo'))).strftime('%Y-%m-01')

def number_br(text, percent=False):
    s = str(text).strip().replace('\u00a0', ' ')
    if percent and not s.endswith('%'):
        raise ValueError('Percentual sem símbolo %')
    s = s.removesuffix('%').strip().removeprefix('R$').strip()
    if not re.fullmatch(r'-?(?:\d{1,3}(?:\.\d{3})+|\d+)(?:,\d{1,2})?', s):
        raise ValueError('Formato numérico inválido')
    try:
        n = Decimal(s.replace('.', '').replace(',', '.'))
    except InvalidOperation:
        raise ValueError('Número inválido') from None
    if not n.is_finite():
        raise ValueError('Número não finito')
    return n

def validate(raw, expected_month):
    if raw['operation'].strip() != OPERATION:
        raise ValueError('Operação divergente')
    if raw['month'] != expected_month:
        raise ValueError('Competência divergente')
    p = number_br(raw['percent'], True)
    if not 0 <= p <= 100:
        raise ValueError('Percentual fora de 0–100')
    costs = number_br(raw['costs'])
    revenue = number_br(raw['revenue'])
    if costs < 0 or revenue <= 0 or abs(costs / revenue * 100 - p) > Decimal('0.02'):
        raise ValueError('Percentual inconsistente com custos/receitas')
    return dict(operation=OPERATION, competence=expected_month, cmv_percent=float(p),
                merchandise_cost=float(costs), sales_revenue=float(revenue))
