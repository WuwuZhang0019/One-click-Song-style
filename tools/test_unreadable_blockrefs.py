"""日期：2026-10-14。不可读块引用过滤与真实读取异常边界回归。"""
from copy import deepcopy
from pathlib import Path
import unittest

from cad_fixture import CadFixture
from lisp_eval import Runtime

SOURCE = Path(__file__).resolve().parent.parent / 'one-click-simsun.lsp'


class UnreadableBlockRefTests(unittest.TestCase):
    def setUp(self):
        self.rt = Runtime(SOURCE.read_text(encoding='utf-8'))
        self.rt.load()
        self.cad = CadFixture(self.rt)
        self.obj = self.cad.block_ref()
        self.obj['Handle'] = 'D5'
        self.before = deepcopy(self.obj)
        self.name_reads = []
        original_name = self.rt.native['vla-get-name']
        def name(obj):
            if obj is self.obj:
                self.name_reads.append('D5')
                raise RuntimeError('Automation 错误。 空对象 ID')
            return original_name(obj)
        self.rt.native['vla-get-name'] = name

    def run_command(self):
        self.rt.call('c:YJST', [])
        self.report = self.rt.get('*ocs:lastreport*')
        self.log = self.cad.logs.files[self.rt.get('*ocs:logpath*')]

    def value(self, key):
        return self.rt.call('OCS:assocd', [key, self.report, None])

    def nil_dxf(self):
        entget = self.rt.native['entget']
        self.rt.native['entget'] = lambda entity, *args: None if entity is self.obj else entget(entity, *args)

    def test_nil_dxf_skips_block_without_name_read_and_converts_valid_text(self):
        self.nil_dxf()
        self.run_command()
        self.assertEqual('部分完成', self.value('status'))
        self.assertEqual(0, self.value('errors'))
        self.assertEqual(1, self.value('uncovered'))
        self.assertEqual([], self.name_reads)
        self.assertEqual(self.before, self.obj)
        self.assertIn('SimSun', self.cad.text['TextString'])
        self.assertGreater(self.value('stylesModified'), 0)
        self.assertIn('ENTGET_RETURNED_NIL', self.log)
        self.assertIn('UNREADABLE_BLOCK_REFERENCE', str(self.value('uncoveredDetail')))
        self.assertIn('BLOCKREF_SKIPPED', self.log)
        self.assertNotIn('BLOCKREF_DIAG_BEGIN', self.log)
        self.assertIn('RUN_END', self.log)

    def test_missing_handle_skips_without_name_or_entity_read(self):
        self.rt.native['handent'] = lambda handle: None
        self.run_command()
        self.assertEqual('部分完成', self.value('status'))
        self.assertEqual(0, self.value('errors'))
        self.assertEqual([], self.name_reads)
        self.assertIn('HANDLE_NOT_RESOLVED', self.log)
        self.assertEqual(self.before, self.obj)

    def test_handle_exception_still_stops_before_writes(self):
        self.rt.native['handent'] = lambda handle: (_ for _ in ()).throw(RuntimeError('handle interface failed'))
        self.run_command()
        self.assertEqual('预检失败', self.value('status'))
        self.assertIn('handle interface failed', str(self.value('errorDetail')))
        self.assertEqual([], self.cad.events)
        self.assertEqual([], self.name_reads)
        self.assertNotIn('BLOCKREF_SKIPPED', self.log)

    def test_entget_exception_still_stops_before_writes(self):
        entget = self.rt.native['entget']
        def read(entity, *args):
            if entity is self.obj:
                raise RuntimeError('entity interface failed')
            return entget(entity, *args)
        self.rt.native['entget'] = read
        self.run_command()
        self.assertEqual('预检失败', self.value('status'))
        self.assertIn('entity interface failed', str(self.value('errorDetail')))
        self.assertEqual([], self.cad.events)
        self.assertEqual([], self.name_reads)
        self.assertNotIn('BLOCKREF_SKIPPED', self.log)

    def test_readable_dxf_does_not_hide_name_exception(self):
        self.run_command()
        self.assertEqual('预检失败', self.value('status'))
        self.assertIn('空对象 ID', str(self.value('errorDetail')))
        self.assertEqual(['D5'], self.name_reads)
        self.assertEqual([], self.cad.events)
        self.assertIn('BLOCKREF_DIAG_BEGIN', self.log)

    def test_duplicate_unreadable_block_is_reported_once(self):
        self.nil_dxf()
        self.cad.blocks[0]['items'].append(self.obj)
        self.run_command()
        self.assertEqual(1, self.value('uncovered'))
        self.assertEqual([], self.name_reads)


if __name__ == '__main__':
    unittest.main(verbosity=2)
