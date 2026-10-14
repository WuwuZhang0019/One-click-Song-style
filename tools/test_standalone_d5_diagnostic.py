"""日期：2026-10-14。手动 DXF 诊断、调用前关闭日志及旧入口撤回回归。"""
from copy import deepcopy
import json
from pathlib import Path
import unittest

from cad_fixture import CadFixture
from lisp_eval import Pair, Runtime, arity_errors

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'tests/native/YJST-D5-DXF-20261014.lsp'
RETIRED = ROOT / 'tests/native/YJST-D5-CHECK-20261014.lsp'


class StandaloneD5Tests(unittest.TestCase):
    def setUp(self):
        self.rt = Runtime(SOURCE.read_text(encoding='utf-8'))
        self.cad = CadFixture(self.rt)
        self.reads = []
        def checkpoint(fn):
            self.assertEqual(set(), self.cad.logs.handles)
            rows = self.rows()
            self.assertEqual('CALL_BEGIN', rows[-1][0])
            self.assertIn(fn, rows[-1][1])
            self.reads.append(fn)
        def handent(handle):
            checkpoint('HANDENT')
            return 'D5entity'
        def entget(ent):
            checkpoint('ENTGET')
            return [Pair(0, 'INSERT'), Pair(2, 'ATTR_BLOCK'), Pair(5, 'D5'), Pair(330, 'B1'), Pair(10, [1, 2, 3])]
        self.rt.native.update({'handent': handent, 'entget': entget})
        self.before = deepcopy(self.cad.tracked())
        self.rt.load()

    def rows(self):
        return [json.loads(row) for row in self.cad.logs.files[self.rt.get('*yjstd5dxf:logpath*')].splitlines()]

    def run_diagnostic(self):
        self.rt.call('c:YJSTD5DXF', [])

    def test_load_performs_no_file_or_drawing_access_and_old_entry_is_disabled(self):
        self.assertEqual([], arity_errors(SOURCE.read_text(encoding='utf-8')))
        self.assertEqual([], self.reads)
        self.assertEqual([], self.cad.logs.opened)
        self.assertEqual({}, self.cad.logs.files)
        self.assertIn('输入 YJSTD5DXF 才开始检查', ''.join(self.rt.output))
        old = Runtime(RETIRED.read_text(encoding='utf-8'))
        old.load()
        old.call('c:YJSTD5CHECK', [])
        self.assertIn('已停用', ''.join(old.output))

    def test_manual_read_persists_checkpoints_before_native_calls_without_active_x(self):
        self.run_diagnostic()
        self.assertEqual(['HANDENT', 'ENTGET'], self.reads)
        self.assertEqual('RUN_BEGIN', self.rows()[0][0])
        self.assertEqual('RUN_END', self.rows()[-1][0])
        self.assertIn('YJST-D5-20261014-v3-DXF', str(self.rows()[0]))
        self.assertIn('ATTR_BLOCK', str(self.rows()))
        dxf = next(row for row in self.rows() if row[0] == 'DXF')
        self.assertNotIn('[1, 2, 3]', str(dxf))
        self.assertEqual(self.before, self.cad.tracked())
        self.assertEqual([], self.cad.events)
        self.assertEqual(set(), self.cad.logs.handles)
        self.assertNotIn('vla-', SOURCE.read_text(encoding='utf-8').lower())
        self.assertNotIn('vlax-', SOURCE.read_text(encoding='utf-8').lower())

    def test_dxf_exception_retains_error_and_closed_log_tail(self):
        self.rt.native['entget'] = lambda ent: (_ for _ in ()).throw(RuntimeError('DXF read failed'))
        self.run_diagnostic()
        self.assertIn('DXF read failed', str(self.rows()))
        self.assertEqual('RUN_END', self.rows()[-1][0])
        self.assertEqual(set(), self.cad.logs.handles)

    def test_nil_dxf_result_is_logged_without_symbol_name_failure(self):
        self.assertIsNone(self.rt.call('type', [None]))
        with self.assertRaisesRegex(TypeError, 'symbolp nil'):
            self.rt.call('vl-symbol-name', [None])
        self.rt.native['entget'] = lambda ent: None
        self.run_diagnostic()
        rows = self.rows()
        ended = next(row for row in rows if row[0] == 'CALL_END' and row[1][1] == 'entity.DXF')
        self.assertIn('nil', ended[1])
        self.assertIn('NIL', ended[1])
        self.assertFalse(any(row[0] == 'DIAGNOSTIC_ERROR' for row in rows))
        self.assertEqual('RUN_END', rows[-1][0])
        self.assertIn('DXF不可读', rows[-1][1])
        self.assertIn('entgetStatus', str(rows))
        self.assertEqual(set(), self.cad.logs.handles)

    def test_nil_handle_is_logged_without_symbol_name_failure(self):
        self.rt.native['handent'] = lambda handle: None
        self.run_diagnostic()
        self.assertNotIn('symbolp nil', str(self.rows()))
        self.assertFalse(any(row[0] == 'DIAGNOSTIC_ERROR' for row in self.rows()))
        self.assertIn('unavailable', str(self.rows()))

    def test_checkpoint_write_failure_stops_target_access(self):
        write = self.rt.native['write-line']
        def failed_write(line, stream):
            if 'CALL_BEGIN' in line:
                raise OSError('disk full')
            return write(line, stream)
        self.rt.native['write-line'] = failed_write
        self.run_diagnostic()
        self.assertEqual([], self.reads)
        self.assertEqual('disk full', self.rt.get('*yjstd5dxf:logerror*'))
        self.assertIn('已停止进一步探测', ''.join(self.rt.output))
        self.assertEqual(set(), self.cad.logs.handles)

    def test_unwritable_log_stops_before_target_access(self):
        self.rt.native['open'] = lambda *args: None
        self.run_diagnostic()
        self.assertEqual([], self.reads)
        self.assertIsNone(self.rt.get('*yjstd5dxf:logpath*'))
        self.assertIn('未读取 D5', ''.join(self.rt.output))

    def test_legacy_encoding_and_repeated_run_keep_previous_log(self):
        original_open = self.rt.native['open']
        def legacy_open(path, mode, *encoding):
            if encoding:
                raise TypeError('too many arguments')
            return original_open(path, mode)
        self.rt.native['open'] = legacy_open
        self.run_diagnostic()
        first_path = self.rt.get('*yjstd5dxf:logpath*')
        first_log = self.cad.logs.files[first_path]
        self.run_diagnostic()
        self.assertNotEqual(first_path, self.rt.get('*yjstd5dxf:logpath*'))
        self.assertEqual(first_log, self.cad.logs.files[first_path])
        self.assertEqual('CAD-legacy', self.rt.get('*yjstd5dxf:encoding*'))
        self.assertEqual(set(), self.cad.logs.handles)


if __name__ == '__main__':
    unittest.main(verbosity=2)
