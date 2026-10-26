"""Configure the dedicated writer locally. No Hands login or database writes."""
import getpass
import json
import os
import sys
from pathlib import Path
from capture import api
import vault

ROOT = Path(__file__).resolve().parent
PUBLIC_CONFIG = {
    'supabase_url': 'https://bbhtrxuaumhpqtbcgewc.supabase.co',
    'publishable_key': 'sb_publishable_VO0CBuxqDHhk3n5IwcFjBA_cDwfq0JK',
}
EXPECTED_ID = '46e17927-aa7d-48d4-9745-4626c1d143c2'
EXPECTED_EMAIL = 'vilafituberlandia+cmv@gmail.com'

def main():
    if os.name != 'nt':
        raise ValueError('Execute este comando no Windows do computador da empresa')
    if not (ROOT / 'hands-session.dpapi').exists():
        raise ValueError('Sessão Hands não encontrada nesta conta Windows; use o computador da empresa')
    # Prove that this Windows account can decrypt its existing Hands session.
    vault.read(ROOT / 'hands-session.dpapi')
    print('Usuário exclusivo do CMV: ' + EXPECTED_EMAIL)
    password = getpass.getpass('Digite a senha criada para esse usuário (não aparece na tela): ')
    if not password:
        raise ValueError('Senha não informada')
    session = api(PUBLIC_CONFIG, '/auth/v1/token?grant_type=password',
                  {'email': EXPECTED_EMAIL, 'password': password})
    user = session.get('user') or {}
    if (user.get('id') != EXPECTED_ID or user.get('email', '').lower() != EXPECTED_EMAIL
            or (user.get('app_metadata') or {}).get('hands_cmv_writer') is not True):
        raise ValueError('Usuário ou permissão de CMV não confirmados')
    config_path = ROOT / 'config.json'
    config = json.loads(config_path.read_text(encoding='utf-8-sig')) if config_path.exists() else {}
    config.update(PUBLIC_CONFIG)
    # Config contains only public connection data. Password is DPAPI CurrentUser.
    vault.write(ROOT / 'writer.dpapi', {'writer_email': EXPECTED_EMAIL, 'writer_password': password})
    temp = config_path.with_suffix('.tmp')
    temp.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding='utf-8')
    os.replace(temp, config_path)
    print('CONEXÃO VALIDADA | usuário CMV autorizado | senha protegida no Windows')
    print('Nenhuma captura gravada no banco. Dashboard e agendamento não alterados.')

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print('CONFIGURAÇÃO NÃO CONCLUÍDA: ' + (str(e) if isinstance(e, ValueError) else type(e).__name__), file=sys.stderr)
        sys.exit(1)
