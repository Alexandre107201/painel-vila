import sys
import unittest
from pathlib import Path
from playwright.sync_api import sync_playwright
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hands_dom import snapshot_hands

# Minimal synthetic DOM using observed structure, never a copy of the private DRE.
HTML='''<header><button aria-haspopup="menu"><img alt="VILA FIT / VILA GOURMET">VILA FIT / VILA GOURMET</button></header><button role="tab" aria-selected="true">Mês Atual</button><div class="bg-card"><h3>Demonstrativo de Resultados do Exercício</h3><p>out/26<button aria-label="Adicionar comentário ao mês"></button></p><table><thead><tr><th>Plano de Contas</th><th>Valores</th><th>%</th></tr></thead><tbody><tr><td>CUSTOS COM MERCADORIAS</td><td>R$ 192.718,18</td><td>46.09 %</td></tr><tr><td>RECEITAS SOBRE VENDAS</td><td>R$ 418.173,64</td><td>100.00 %</td></tr></tbody></table></div>'''

class HandsDomTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):cls.pw=sync_playwright().start();cls.browser=cls.pw.chromium.launch(headless=True)
 @classmethod
 def tearDownClass(cls):cls.browser.close();cls.pw.stop()
 def setUp(self):self.context=self.browser.new_context();self.page=self.context.new_page();self.page.set_content(HTML)
 def tearDown(self):self.context.close()
 def test_dot_percent(self):self.assertEqual(snapshot_hands(self.page,'2026-10-01')['cmv_percent'],46.09)
 def test_wrong_operation_month_and_tab(self):
  for source in [HTML.replace('>VILA FIT / VILA GOURMET</button>','>OUTRA OPERAÇÃO</button>'),HTML.replace('out/26','set/26'),HTML.replace('aria-selected="true"','aria-selected="false"')]:
   self.page.set_content(source)
   with self.assertRaises(ValueError):snapshot_hands(self.page,'2026-10-01')
 def test_wrong_percent_and_duplicate(self):
  for source in [HTML.replace('46.09 %','0.00 %'),HTML.replace('46.09 %','NaN %'),HTML.replace('</tbody>','<tr><td>CUSTOS COM MERCADORIAS</td><td>1</td><td>1%</td></tr></tbody>')]:
   self.page.set_content(source)
   with self.assertRaises(ValueError):snapshot_hands(self.page,'2026-10-01')

if __name__=='__main__':unittest.main()
