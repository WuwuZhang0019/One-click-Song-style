"""日期：2026-10-14。无文字专业对象、受保护字段只读核验及真实 DXF 边界回归。"""
from copy import deepcopy
import json
from pathlib import Path
import unittest

from cad_fixture import CadFixture, TRUE, FALSE
from lisp_eval import Runtime, Pair

ROOT = Path(__file__).resolve().parent.parent
CASE = ROOT / 'tests/protected-table-fields-20261014.json'


class VerificationRuleTests(unittest.TestCase):
    def setUp(self):
        self.rt = Runtime((ROOT / 'one-click-simsun.lsp').read_text(encoding='utf-8'))
        self.rt.load()
        self.cad = CadFixture(self.rt)
        self.case = json.loads(CASE.read_text(encoding='utf-8'))
        self.cad.styles['ICDA-STYLE1'] = self.cad.style('ICDA-STYLE1', '', '')
        for name in ('Standard', 'ICDA-STYLE1'):
            style = self.cad.styles[name]
            self.cad.put_dxf(style, 3, '')
            self.cad.put_dxf(style, 4, '')
            style['font'] = ['SimSun', TRUE, FALSE, 134, 22]
        self.cad.text['TextString'] = '标题'
        self.cad.dynamic['TextString'] = '动态文字'
        for handle, tags in self.case['fields'].items():
            self.cad.records[handle] = {'Handle': handle, 'dxf': [Pair(c, v) for c, v in tags]}

    def value(self, key):
        return self.rt.call('OCS:assocd', [key, self.rt.get('*ocs:lastreport*'), None])

    def run_command(self):
        self.rt.call('c:YJSTFIX', [])
        self.assertEqual(0, self.value('errors'))
        self.assertEqual(0, self.value('recoverFailed'))

    def table_from_cells(self, handle, tags):
        obj = self.cad.table()
        obj['Handle'] = handle
        obj['Columns'] = len(tags)
        obj['widths'] = [50.0] * len(tags)
        obj['dxf'] = [Pair(0, 'ACAD_TABLE'), Pair(100, 'AcDbTable'), Pair(280, 0),
                      Pair(91, 1), Pair(92, len(tags))]
        cells = []
        for cell in tags:
            obj['dxf'].extend(Pair(c, v) for c, v in cell)
            field = next((v for c, v in cell if c == 344), None)
            text = next((v for c, v in cell if c == 302), '')
            cells.append(dict(type=2 if field else 1, state=0,
                              contents=[dict(text='%<\\_FldIdx 0>%' if field else text,
                                             style='ICDA-STYLE1', field=1 if field else 0,
                                             formula=TRUE if field else FALSE)]))
        obj['cells'] = [cells]
        return obj

    def single_field(self):
        return self.table_from_cells('1134B', [self.case['tables'][0]['cells'][2]])

    def field_value(self, handle, code, value):
        self.cad.put_dxf(self.cad.records[handle], code, value)

    def assert_preserved(self, table, before, fields):
        self.assertEqual(before, table)
        self.assertEqual(fields, self.cad.records)
        self.assertEqual(0, self.value('stylesModified'))
        self.assertEqual(0, self.value('tableContents'))
        self.assertNotIn('start', self.cad.events)

    def test_real_twenty_fields_pass_without_writes_and_fontless_objects_are_excluded(self):
        tables = [self.table_from_cells(row['handle'], row['cells']) for row in self.case['tables']]
        for i in range(47):
            kind = 'TDbECabletry' if i < 25 else 'TDbEFitting'
            self.cad.add(self.cad.entity(kind, f'PRO-{i}', ''))
        before = deepcopy(tables)
        fields = deepcopy(self.cad.records)
        self.run_command()
        self.assertEqual('无需修改', self.value('status'))
        self.assertEqual(47, self.value('nonTextExcluded'))
        self.assertEqual(20, self.value('tableProtectedPassed'))
        self.assertEqual(0, self.value('tableProtectedMismatch'))
        self.assertEqual(0, self.value('tableProtectedUnknown'))
        self.assertEqual(0, self.value('uncovered'))
        for obj, old in zip(tables, before):
            self.assert_preserved(obj, old, fields)
        log = self.cad.logs.files[self.rt.get('*ocs:logpath*')]
        self.assertEqual(20, log.count('TABLE_PROTECTED_VERIFY'))
        self.assertEqual(47, log.count('NON_TEXT_EXCLUDED'))

    def test_field_table_display_cache_retains_two_nontarget_font_runs(self):
        table = self.single_field()
        table['dxf'].extend((Pair(2, '*T3'), Pair(343, '101')))
        block = {'dxf': [Pair(0, 'BLOCK_RECORD'), Pair(5, '101')]}
        first = {'dxf': [Pair(0, 'MTEXT'), Pair(5, '105'),
                         Pair(1, r'{\Fsimplex,hztxt|c134;9.5}')]}
        second = {'dxf': [Pair(0, 'MTEXT'), Pair(5, '108'),
                          Pair(1, r'{\Fsimplex,hztxt|c134;10.4}')]}
        end = {'dxf': [Pair(0, 'ENDBLK')]}
        self.rt.native['tblobjname'] = lambda kind, name: block if kind == 'BLOCK' and name == '*T3' else self.cad.styles.get(name)
        self.rt.native['tblsearch'] = lambda kind, name: [Pair(-2, first)] if kind == 'BLOCK' and name == '*T3' else None
        self.rt.native['entnext'] = lambda obj: second if obj is first else end if obj is second else None
        before, fields = deepcopy(table), deepcopy(self.cad.records)
        self.run_command()
        self.assertEqual('部分完成', self.value('status'))
        self.assertEqual(1, self.value('tableProtectedPassed'))
        self.assertEqual(2, self.value('uncovered'))
        self.assertEqual(2, self.value('tableDisplayMismatch'))
        self.assertEqual(before, table)
        self.assertEqual(fields, self.cad.records)
        self.assertNotIn('start', self.cad.events)

    def test_unknown_professional_class_stays_uncovered(self):
        for kind in ('TDbECabletry', 'TDbEFitting', 'TDbOther', 'TDbECabletryText'):
            self.cad.add(self.cad.entity(kind, kind, ''))
        self.run_command()
        self.assertEqual(2, self.value('nonTextExcluded'))
        self.assertEqual(2, self.value('uncovered'))
        self.assertEqual('部分完成', self.value('status'))

    def test_locked_numeric_field_is_verified_without_unlocking_or_rewriting(self):
        table = self.single_field()
        table['cells'][0][0]['state'] = 31
        before, fields = deepcopy(table), deepcopy(self.cad.records)
        self.run_command()
        self.assertEqual(1, self.value('tableProtectedPassed'))
        self.assertEqual(0, self.value('uncovered'))
        self.assert_preserved(table, before, fields)

    def test_native_entity_name_references_are_supported(self):
        table = self.single_field()
        root = self.cad.records['11ADE']
        child = self.cad.records['11ADF']
        self.cad.put_dxf(table, 344, root)
        self.cad.put_dxf(root, 360, child)
        before, fields = deepcopy(table), deepcopy(self.cad.records)
        self.run_command()
        self.assertEqual(1, self.value('tableProtectedPassed'))
        self.assertEqual(0, self.value('uncovered'))
        self.assert_preserved(table, before, fields)

    def test_font_override_in_field_wrapper_is_mismatch(self):
        table = self.single_field()
        self.field_value('11ADE', 2, r'{\fArial;说明}%<\_FldIdx 0>%')
        before, fields = deepcopy(table), deepcopy(self.cad.records)
        self.run_command()
        self.assertEqual(1, self.value('tableProtectedMismatch'))
        self.assertEqual(1, self.value('uncovered'))
        self.assertEqual('部分完成', self.value('status'))
        self.assert_preserved(table, before, fields)

    def test_nontarget_cell_style_is_mismatch(self):
        table = self.single_field()
        table['cells'][0][0]['contents'][0]['style'] = 'XREF|Text'
        self.run_command()
        self.assertEqual(1, self.value('tableProtectedMismatch'))
        self.assertEqual(1, self.value('uncovered'))

    def test_missing_child_cycle_bad_child_count_and_unknown_evaluator_are_unknown(self):
        for mode in ('missing', 'cycle', 'count', 'evaluator', 'unresolved_slot', 'unreferenced_child'):
            with self.subTest(mode=mode):
                self.setUp()
                table = self.single_field()
                if mode == 'missing':
                    self.field_value('11ADE', 360, 'NOT_FOUND')
                elif mode == 'cycle':
                    self.field_value('11ADE', 360, '11ADE')
                elif mode == 'count':
                    self.field_value('11ADE', 90, 2)
                elif mode == 'evaluator':
                    self.field_value('11ADF', 1, 'UnknownEvaluator')
                elif mode == 'unresolved_slot':
                    self.field_value('11ADE', 2, r'%<\_FldIdx 3>%')
                else:
                    self.field_value('11ADE', 2, 'unreferenced child')
                before, fields = deepcopy(table), deepcopy(self.cad.records)
                self.run_command()
                self.assertEqual(1, self.value('tableProtectedUnknown'))
                self.assertEqual(0, self.value('tableProtectedPassed'))
                self.assertEqual(1, self.value('uncovered'))
                self.assert_preserved(table, before, fields)

    def test_unsuccessful_evaluation_or_non_numeric_cache_is_unknown(self):
        for mode in ('eval', 'cache', 'overflow'):
            with self.subTest(mode=mode):
                self.setUp()
                self.single_field()
                if mode == 'eval':
                    self.field_value('11ADF', 95, 8)
                elif mode == 'cache':
                    cache = self.cad.records['11ADF']['dxf']
                    after_key = next(i for i, p in enumerate(cache) if p.car == 7 and p.cdr == 'ACFD_FIELD_VALUE')
                    next(p for p in cache[after_key:] if p.car == 90).cdr = 4
                else:
                    self.cad.records['11ADF']['dxf'].insert(-1, Pair(9, 'unhandled continuation'))
                self.run_command()
                self.assertEqual(1, self.value('tableProtectedUnknown'))
                self.assertEqual(1, self.value('uncovered'))

    def test_cached_display_font_override_is_mismatch(self):
        self.single_field()
        self.field_value('11ADF', 302, r'{\fArial;40.50}')
        self.run_command()
        self.assertEqual(1, self.value('tableProtectedMismatch'))
        self.assertEqual(0, self.value('tableProtectedPassed'))

    def test_readonly_error_is_unknown_and_does_not_abort_other_cells(self):
        row = self.case['tables'][0]
        table = self.table_from_cells('1134B', row['cells'])
        getter = self.rt.native['vla-gettextstyle2']
        def failing(obj, r, c, n):
            if obj is table and c == 2:
                raise RuntimeError('font read unavailable')
            return getter(obj, r, c, n)
        self.rt.native['vla-gettextstyle2'] = failing
        self.rt.native['exit'] = lambda: (_ for _ in ()).throw(RuntimeError('quit / exit abort'))
        self.run_command()
        self.assertEqual(1, self.value('tableProtectedUnknown'))
        self.assertEqual(1, self.value('tableProtectedPassed'))
        self.assertEqual(1, self.value('uncovered'))
        self.assertIn('font read unavailable', str(self.value('tableProtectedDetails')))

    def test_block_content_and_ambiguous_return_do_not_pass(self):
        for mode in ('block', 'formula_return'):
            with self.subTest(mode=mode):
                self.setUp()
                table = self.single_field()
                if mode == 'block':
                    table['cells'][0][0]['type'] = 4
                else:
                    self.rt.native['vla-gethasformula'] = lambda *args: None
                self.run_command()
                self.assertEqual(1, self.value('tableProtectedUnknown'))
                self.assertEqual(0, self.value('tableProtectedPassed'))

    def test_pass_removes_only_matching_protected_detail(self):
        self.single_field()
        self.cad.add(self.cad.entity('TDbOther', 'OTHER', ''))
        self.run_command()
        self.assertEqual(1, self.value('tableProtectedPassed'))
        self.assertEqual(1, self.value('uncovered'))
        self.assertIn('OTHER', str(self.value('uncoveredDetail')))
        self.assertNotIn('PROTECTED_CONTENT', str(self.value('uncoveredDetail')))

    def test_long_field_tree_stops_at_bound_without_recursive_calls(self):
        self.single_field()
        self.field_value('11ADE', 360, 'CHAIN-0')
        for i in range(129):
            tags = [(0, 'FIELD'), (5, f'CHAIN-{i}'), (100, 'AcDbField'), (1, 'AcExpr'),
                    (2, r'\AcExpr 1'), (90, 1 if i < 128 else 0)]
            if i < 128:
                tags.append((360, f'CHAIN-{i+1}'))
            tags += [(95, 2), (7, 'ACFD_FIELD_VALUE'), (90, 2), (140, 1.0), (301, '1.00')]
            self.cad.records[f'CHAIN-{i}'] = {'Handle': f'CHAIN-{i}', 'dxf': [Pair(c, v) for c, v in tags]}
        self.run_command()
        self.assertEqual(1, self.value('tableProtectedUnknown'))
        self.assertIn('超过核验边界', str(self.value('tableProtectedDetails')))


if __name__ == '__main__':
    unittest.main(verbosity=2)
