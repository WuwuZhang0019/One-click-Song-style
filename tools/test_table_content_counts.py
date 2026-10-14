"""日期：2026-10-14。真实 DXF 表格内容边界与忽略越界索引的 CAD 行为回归。"""
from copy import deepcopy
import json
from pathlib import Path
import unittest

from cad_fixture import CadFixture
from lisp_eval import Pair, Runtime

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'one-click-simsun.lsp'
CASE = ROOT / 'tests/table-content-count-1134B-20261014.json'


class TableContentCountTests(unittest.TestCase):
    def setUp(self):
        self.rt = Runtime(SOURCE.read_text(encoding='utf-8'))
        self.rt.load()
        self.cad = CadFixture(self.rt)

    def value(self, key):
        return self.rt.call('OCS:assocd', [key, self.rt.get('*ocs:lastreport*'), None])

    def run_command(self):
        self.rt.call('c:YJSTFIX', [])

    def test_original_1134b_dxf_has_one_content_per_cell(self):
        case = json.loads(CASE.read_text(encoding='utf-8'))
        tags = [Pair(c, v) for c, v in case['tags']]
        result = self.rt.call('OCS:tableDxfCounts', [tags, case['rows'], case['cols']])
        self.assertEqual(case['expectedCounts'], result)
        self.assertEqual('1134B', case['handle'])

    def test_api_ignoring_out_of_range_is_never_probed_out_of_bounds(self):
        table = self.cad.table()
        getter = self.rt.native['vla-gettextstring']
        reads = []
        def nonthrowing(obj, row, col, content):
            reads.append(content)
            return getter(obj, row, col, 0)  # 模拟任意内容索引均成功返回同一数据。
        self.rt.native['vla-gettextstring'] = nonthrowing
        self.run_command()
        self.assertEqual('已完成', self.value('status'))
        self.assertEqual(0, self.value('errors'))
        self.assertEqual({0}, set(reads))
        self.assertLess(len(reads), 15)
        self.assertIn('SimSun', table['cells'][0][0]['contents'][0]['text'])
        self.assertEqual(1, self.value('tableContents'))

    def test_multiple_contents_are_all_converted_without_termination_probe(self):
        table = self.cad.table([{'text':r'{\fArial;甲}'}, {'text':r'{\fSimHei;乙}'}])
        getter = self.rt.native['vla-gettextstring']
        reads = []
        def read(obj, row, col, content):
            reads.append(content)
            return getter(obj, row, col, content)
        self.rt.native['vla-gettextstring'] = read
        self.run_command()
        self.assertEqual('已完成', self.value('status'))
        self.assertEqual({0, 1}, set(reads))
        self.assertEqual(2, self.value('tableContents'))
        self.assertTrue(all('SimSun' in part['text'] for part in table['cells'][0][0]['contents']))

    def test_unknown_count_preserves_cell_and_converts_other_text(self):
        table = self.cad.table()
        table['dxf'] = [Pair(0, 'ACAD_TABLE'), Pair(100, 'AcDbTableContent')]
        before = deepcopy(table)
        reads = []
        self.rt.native['vla-gettextstring'] = lambda *args: reads.append(args) or ''
        self.run_command()
        self.assertEqual('部分完成', self.value('status'))
        self.assertEqual(0, self.value('errors'))
        self.assertEqual(before, table)
        self.assertEqual([], reads)
        self.assertIn('SimSun', self.cad.text['TextString'])
        self.assertIn('无法确认完整内容数量', str(self.value('uncoveredDetail')))

    def test_invalid_header_dimensions_do_not_guess_content_count(self):
        table = self.cad.table()
        table['dxf'] = [Pair(92, 2) if p.car == 92 else p for p in table['dxf']]
        before = deepcopy(table)
        self.run_command()
        self.assertEqual('部分完成', self.value('status'))
        self.assertEqual(before, table)
        self.assertEqual(0, self.value('errors'))

    def test_known_content_read_failure_still_stops_before_writes(self):
        self.cad.table()
        self.rt.native['vla-gettextstring'] = lambda *args: (_ for _ in ()).throw(RuntimeError('content read failed'))
        self.run_command()
        self.assertEqual('预检失败', self.value('status'))
        self.assertIn('content read failed', str(self.value('errorDetail')))
        self.assertEqual([], self.cad.events)

    def test_parser_accepts_verified_count_above_old_limit(self):
        tags = [Pair(100, 'AcDbTable'), Pair(280, 0), Pair(91, 1), Pair(92, 1), Pair(171, 1)]
        tags += [Pair(301, 'CELL_VALUE') for _ in range(1025)]
        self.assertEqual([1025], self.rt.call('OCS:tableDxfCounts', [tags, 1, 1]))

    def test_unique_command_refuses_old_version_after_menu_override(self):
        self.rt.set('*ocs:version*', '0.2.10')
        self.run_command()
        self.assertEqual([], self.cad.events)
        self.assertIsNone(self.rt.get('*ocs:lastreport*'))
        self.assertIn('已被旧版覆盖', ''.join(self.rt.output))


if __name__ == '__main__':
    unittest.main(verbosity=2)
