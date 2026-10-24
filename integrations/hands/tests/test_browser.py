"""Offline fixtures only. No contact with Hands, Supabase or production."""
import sys
import json
import re
import unittest
from pathlib import Path
from datetime import datetime, timezone, timedelta
from playwright.sync_api import sync_playwright
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from capture import snapshot, capture
from core import month_now
ROOT=Path(__file__).resolve().parents[3]

class BrowserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pw=sync_playwright().start();cls.browser=cls.pw.chromium.launch(headless=True)
    @classmethod
    def tearDownClass(cls):cls.browser.close();cls.pw.stop()
    def setUp(self):self.context=self.browser.new_context();self.page=self.context.new_page()
    def tearDown(self):self.context.close()
    def test_dre_columns_identity_and_duplicate(self):
        self.page.set_content('''<b id="op">Vila Fit / Vila Gourmet</b><b id="month">10/2026</b><table><thead><tr><th>Descrição</th><th>Valor</th><th>%</th></tr></thead><tbody><tr><td>CUSTOS COM MERCADORIAS</td><td>192.718,18</td><td>47,90%</td></tr><tr><td>RECEITAS SOBRE VENDAS</td><td>402.366,40</td><td>100,00%</td></tr></tbody></table>''')
        cfg={'selectors':{'operation_evidence':'#op','month_evidence':'#month','report':'table'},'month_format':'%m/%Y','headers':{'label':'Descrição','percent':'%','amount':'Valor'}}
        self.assertEqual(snapshot(self.page,cfg,'2026-10-01')['cmv_percent'],47.9)
        self.page.locator('#op').evaluate('(e)=>e.textContent="Vila Sabor"')
        with self.assertRaises(ValueError):snapshot(self.page,cfg,'2026-10-01')
        self.page.locator('#op').evaluate('(e)=>e.textContent="Vila Fit / Vila Gourmet"')
        with self.assertRaises(ValueError):snapshot(self.page,cfg,'2026-11-01')
        self.page.evaluate('document.querySelector("tbody").append(document.querySelector("tbody tr").cloneNode(true))')
        with self.assertRaises(ValueError):snapshot(self.page,cfg,'2026-10-01')
    def test_complete_headless_capture_offline(self):
        label=datetime.strptime(month_now(),'%Y-%m-%d').strftime('%m/%Y')
        html='<select id="operation"><option>Vila Fit / Vila Gourmet</option></select><select id="period"><option>Mês Atual</option></select><button id="apply" onclick="fetch(&quot;/report&quot;)">Atualizar</button><b id="op">Vila Fit / Vila Gourmet</b><b id="month">'+label+'</b><table><thead><tr><th>Descrição</th><th>Valor</th><th>%</th></tr></thead><tbody><tr><td>CUSTOS COM MERCADORIAS</td><td>192.718,18</td><td>47,90%</td></tr><tr><td>RECEITAS SOBRE VENDAS</td><td>402.366,40</td><td>100,00%</td></tr></tbody></table>'
        self.context.route('https://offline.test/dre',lambda r:r.fulfill(body=html,content_type='text/html; charset=utf-8'))
        self.context.route('https://offline.test/report',lambda r:r.fulfill(body='{}',content_type='application/json'))
        cfg={'url':'https://offline.test/dre','selectors_validated':True,'report_response_url_pattern':r'https://offline\.test/report','month_format':'%m/%Y','headers':{'label':'Descrição','percent':'%','amount':'Valor'},'selectors':{'operation_select':'#operation','period_select':'#period','operation_evidence':'#op','month_evidence':'#month','report':'table','apply_button':'#apply'}}
        self.assertEqual(capture(self.context,cfg)['cmv_percent'],47.9)

    def test_unapproved_config_refuses_capture(self):
        with self.assertRaises(ValueError):capture(self.context,{'selectors_validated':False})
    def ui(self):
        html=(ROOT/'painel-atual.html').read_text()
        script=re.findall(r'<script>(.*?)</script>',html,re.S)[-1]
        self.page.route('https://fixture.test/**',lambda r:r.fulfill(body='<html><body></body></html>',content_type='text/html'))
        self.page.goto('https://fixture.test/')
        self.page.set_content('<div id="handsCmvValue"></div><p id="handsCmvStatus"></p><button id="handsCmvRefresh"></button><button id="handsCmvLogin"></button><button id="openImport"></button>')
        self.page.evaluate('''()=>{window.handsCmvPublicConfig={url:'https://db.test',key:'public-fixture'};window.payload=[];window.fail=false;window.fetch=async()=>{if(window.fail)throw Error('offline');return {ok:true,json:async()=>window.payload};};}''')
        self.page.add_script_tag(content=script)
    def login(self):
        self.page.evaluate('''()=>{sessionStorage.setItem('painel_vila_import_session',JSON.stringify({access_token:'test-only',expires_at:Date.now()/1000+3600}));dispatchEvent(new Event('hands-cmv-session'));}''')
    def row(self, hours=0):
        return {'operation':'Vila Fit / Vila Gourmet','competence':month_now(),'cmv_percent':47.9,'captured_at':(datetime.now(timezone.utc)-timedelta(hours=hours)).isoformat()}
    def test_ui_reference_failure_stale_and_logout(self):
        self.ui();self.assertEqual(self.page.locator('#handsCmvValue').inner_text(),'—')
        self.page.evaluate('(x)=>window.payload=[x]',self.row(3));self.login()
        self.page.wait_for_function('document.querySelector("#handsCmvValue").textContent==="47,90%"')
        text=self.page.locator('#handsCmvStatus').inner_text();self.assertIn('Acima da meta',text);self.assertIn('ATUALIZAÇÃO ATRASADA',text)
        self.page.evaluate('window.fail=true');self.page.locator('#handsCmvRefresh').click()
        self.assertEqual(self.page.locator('#handsCmvValue').inner_text(),'47,90%')
        self.assertIn('mantendo última captura',self.page.locator('#handsCmvStatus').inner_text())
        self.page.evaluate("sessionStorage.clear();dispatchEvent(new Event('hands-cmv-session'))")
        self.assertEqual(self.page.locator('#handsCmvValue').inner_text(),'—')
    def test_ui_rejects_wrong_month_null_and_empty(self):
        self.ui();self.login()
        for change in [{'competence':'2020-01-01'},{'cmv_percent':None},{'operation':'Vila Sabor'}]:
            row=self.row();row.update(change);self.page.evaluate('(x)=>window.payload=[x]',row);self.page.locator('#handsCmvRefresh').click()
            self.assertEqual(self.page.locator('#handsCmvValue').inner_text(),'—')
        self.page.evaluate('window.payload=[]');self.page.locator('#handsCmvRefresh').click()
        self.assertEqual(self.page.locator('#handsCmvValue').inner_text(),'—')

if __name__=='__main__':unittest.main()
