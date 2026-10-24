import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from core import validate, number_br, month_now
from datetime import datetime
from zoneinfo import ZoneInfo

class ValidationTests(unittest.TestCase):
    def raw(self, **changes):
        return dict(operation='Vila Fit / Vila Gourmet', month='2026-10-01', percent='47,90%', costs='R$ 192.718,18', revenue='R$ 402.366,40', **changes)
    def test_reference(self):
        self.assertEqual(validate(self.raw(), '2026-10-01')['cmv_percent'], 47.9)
    def test_reject_identity_month_and_numbers(self):
        for key, value in [('operation','Vila Sabor'),('month','2026-09-01'),('percent',''),('percent','NaN%'),('percent','101%'),('percent','-1%'),('percent','47.90%'),('percent','0%'),('revenue','0'),('costs','—')]:
            raw=self.raw();raw[key]=value
            with self.subTest(key=key,value=value), self.assertRaises(ValueError):validate(raw,'2026-10-01')
    def test_real_zero_allowed(self):
        raw=self.raw();raw.update(percent='0,00%',costs='0,00')
        self.assertEqual(validate(raw,'2026-10-01')['cmv_percent'],0)
    def test_brazil_month_boundary(self):
        self.assertEqual(month_now(datetime(2026,10,31,23,59,tzinfo=ZoneInfo('America/Sao_Paulo'))),'2026-10-01')
        self.assertEqual(month_now(datetime(2026,11,1,0,0,tzinfo=ZoneInfo('America/Sao_Paulo'))),'2026-11-01')

if __name__=='__main__':unittest.main()
