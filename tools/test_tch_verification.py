"""日期：2026-10-13。执行实际 LISP 核验链，使用现场 DXF 已观测的公开结构。"""
from pathlib import Path
import unittest
from copy import deepcopy
from cad_fixture import CadFixture
from lisp_eval import Runtime, Pair

SOURCE = Path(__file__).resolve().parent.parent / 'one-click-simsun.lsp'


class TchVerificationTests(unittest.TestCase):
    def setUp(self):
        self.rt = Runtime(SOURCE.read_text(encoding='utf-8'))
        self.rt.load()
        self.cad = CadFixture(self.rt)
        self.rt.native['handent'] = lambda h: h if h in self.cad.styles else None

    def value(self, key):
        return self.rt.call('OCS:assocd', [key, self.rt.get('*ocs:lastcheckreport*'), None])

    def entity(self, kind, handle, text='测试', style='Standard'):
        types = {'TDbText': 'TCH_TEXT', 'TDbMText': 'TCH_MTEXT',
                 'TDbDrawingName': 'TCH_DRAWINGNAME', 'TDbSymbMultiLeader': 'TCH_MULTILEADER'}
        pairs = [(0, types[kind]), (5, handle), (100, 'AcDbEntity'), (100, 'TDbEntity')]
        if kind == 'TDbDrawingName':
            pairs += [(100, kind), (1, text), (2, '1:100'), (340, style), (341, style)]
        elif kind == 'TDbSymbMultiLeader':
            pairs += [(100, 'TDbSymbWithText'), (7, style), (100, kind), (1, text), (2, '说明')]
        else:
            pairs += [(100, 'TDbText'), (1, text), (7, style)]
            if kind == 'TDbMText':
                pairs += [(100, kind), (41, '10.0')]
        obj = self.cad.entity(kind, handle, '')
        obj['dxf'] = [Pair(c, v) for c, v in pairs]
        return self.cad.add(obj)

    def run_yjst(self):
        self.rt.steps = 0
        self.rt.call('c:YJST', [])
        self.rt.steps = 0
        self.rt.call('c:YJSTCHECK', [])

    def test_all_four_classes_pass_after_style_conversion_and_repeat(self):
        objects = [self.entity(k, str(i)) for i, k in enumerate(
            ('TDbText', 'TDbMText', 'TDbDrawingName', 'TDbSymbMultiLeader'))]
        before = deepcopy(objects)
        self.run_yjst()
        self.assertEqual('核查完成', self.value('status'))
        self.assertEqual(4, self.value('tchPassed'))
        self.assertEqual(0, self.value('uncovered'))
        self.assertEqual(before, objects)
        log = self.cad.logs.files[self.rt.get('*ocs:logpath*')]
        self.assertIn('TCH_VERIFY', log)
        self.run_yjst()
        self.assertEqual('核查完成', self.value('status'))
        self.assertEqual(4, self.value('tchPassed'))

    def test_override_mismatch_is_readonly_and_remains_partial(self):
        obj = self.entity('TDbMText', 'A', r'{\fArial;测试}')
        before = deepcopy(obj)
        self.run_yjst()
        self.assertEqual('核查完成，存在不一致或无法核验项', self.value('status'))
        self.assertEqual(1, self.value('tchMismatch'))
        self.assertEqual(1, self.value('uncovered'))
        self.assertEqual(0, self.value('errors'))
        self.assertEqual(before, obj)

    def test_missing_duplicate_fields_unresolved_ref_and_field_are_unknown(self):
        for mode in ('missing', 'duplicate', 'badref', 'field', 'split', 'wrongtype'):
            with self.subTest(mode=mode):
                self.setUp()
                obj = self.entity('TDbDrawingName', 'A')
                if mode == 'missing': obj['dxf'] = [p for p in obj['dxf'] if p.car != 341]
                if mode == 'duplicate': obj['dxf'].append(Pair(340, 'Standard'))
                if mode == 'badref': self.cad.put_dxf(obj, 341, 'NOT_FOUND')
                if mode == 'field': self.cad.put_dxf(obj, 1, '%<field>%')
                if mode == 'split': obj['dxf'].append(Pair(3, 'extra'))
                if mode == 'wrongtype': self.cad.put_dxf(obj, 0, 'ACAD_PROXY_ENTITY')
                self.run_yjst()
                self.assertEqual('核查完成，存在不一致或无法核验项', self.value('status'))
                self.assertEqual(1, self.value('tchUnknown'))
                self.assertEqual(0, self.value('tchPassed'))

    def test_unrelated_unknown_class_is_not_removed(self):
        self.entity('TDbText', 'A')
        self.cad.add(self.cad.entity('TDbOther', 'B', ''))
        self.run_yjst()
        self.assertEqual(1, self.value('tchPassed'))
        self.assertEqual(1, self.value('uncovered'))
        self.assertIn('B', str(self.value('uncoveredDetail')))

    def test_missing_entget_or_read_exception_does_not_abort_other_checks(self):
        for throws in (False, True):
            with self.subTest(throws=throws):
                self.setUp()
                bad = self.entity('TDbText', 'A')
                self.entity('TDbText', 'B')
                original = self.rt.native['entget']
                def read(ent, *args):
                    if ent is bad:
                        if throws: raise RuntimeError('private data inaccessible')
                        return None
                    return original(ent, *args)
                self.rt.native['entget'] = read
                self.run_yjst()
                self.assertEqual('核查完成，存在不一致或无法核验项', self.value('status'))
                self.assertEqual(1, self.value('tchUnknown'))
                self.assertEqual(1, self.value('tchPassed'))
                self.assertEqual(0, self.value('errors'))

    def test_reference_to_unconverted_style_is_mismatch(self):
        self.entity('TDbText', 'A', style='XREF|Text')
        self.run_yjst()
        self.assertEqual(1, self.value('tchMismatch'))
        self.assertEqual(0, self.value('tchPassed'))

    def test_conversion_skips_optional_check_and_does_not_print_details(self):
        self.entity('TDbText', 'PRIVATE_HANDLE')
        self.rt.call('c:YJST', [])
        log = self.cad.logs.files[self.rt.get('*ocs:logpath*')]
        output = ''.join(map(str, self.rt.output))
        self.assertNotIn('TCH_VERIFY', log)
        self.assertNotIn('PRIVATE_HANDLE', output)
        self.assertNotIn('PROXY_OR_PRO', output)
        self.assertIn('PRIVATE_HANDLE', log)
        self.assertIn('YJST 执行成功', output)
        self.assertIsNone(self.rt.get('*ocs:lastcheckreport*'))

    def test_check_is_standalone_readonly_and_refreshes_current_objects(self):
        self.entity('TDbText', 'A')
        before = deepcopy((self.cad.styles, self.cad.blocks))
        self.rt.call('c:YJSTCHECK', [])
        self.assertEqual(1, self.value('tchMismatch'))  # 未先转换的样式必须报不一致
        self.assertEqual(before, (self.cad.styles, self.cad.blocks))
        self.assertEqual([], self.cad.events)
        self.assertIsNone(self.rt.get('*ocs:lastreport*'))
        self.entity('TDbText', 'NEW')
        self.rt.steps = 0
        self.rt.call('c:YJSTCHECK', [])
        self.assertEqual(2, self.value('tchMismatch'))
        self.assertIsNone(self.rt.get('*ocs:plan*'))
        self.assertIsNone(self.rt.get('*ocs:checkonly*'))

    def test_check_failure_is_logged_and_next_conversion_still_runs(self):
        original = self.rt.native['vla-get-blocks']
        def broken(*args):
            raise RuntimeError('cannot enumerate drawing')
        self.rt.native['vla-get-blocks'] = broken
        self.rt.call('c:YJSTCHECK', [])
        self.assertEqual('核查失败', self.value('status'))
        self.assertEqual(1, self.value('errors'))
        self.assertFalse(self.rt.get('*ocs:running*'))
        self.assertEqual([], self.cad.events)
        self.assertIn('RUN_END', self.cad.logs.files[self.rt.get('*ocs:logpath*')])
        self.rt.native['vla-get-blocks'] = original
        self.rt.steps = 0
        self.rt.call('c:YJST', [])
        self.assertEqual('已完成', self.rt.call('OCS:assocd', ['status', self.rt.get('*ocs:lastreport*'), None]))


if __name__ == '__main__':
    unittest.main()
