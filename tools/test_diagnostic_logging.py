"""日期：2026-10-13。排查日志、失败隔离与专业引线分类回归。"""
from copy import deepcopy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from cad_fixture import CadFixture
from lisp_eval import Runtime, truth

SOURCE = Path(__file__).resolve().parent.parent / 'one-click-simsun.lsp'


class DiagnosticLoggingTests(unittest.TestCase):
    def setUp(self):
        self.rt = Runtime(SOURCE.read_text(encoding='utf-8'))
        self.rt.load()
        self.cad = CadFixture(self.rt)

    def call(self, name, *args):
        return self.rt.call(name, list(args))

    def value(self, key):
        return self.call('OCS:assocd', key, self.rt.get('*ocs:lastreport*'), None)

    def log(self):
        return self.cad.logs.files[self.rt.get('*ocs:logpath*')]

    def bad_leader(self):
        self.cad.add(self.cad.entity('AcDbLeader', '1644', ''))
        def unknown_annotation(obj):
            raise RuntimeError('ActiveX 服务器返回错误：未知名称: Annotation')
        self.rt.native['vla-get-annotation'] = unknown_annotation

    def test_specialized_leader_is_preserved_and_logged(self):
        obj = self.cad.add(self.cad.entity('TDbSymbMultiLeader', '1644', '专业引线原文'))
        before = deepcopy(obj)
        def unexpected(obj):
            raise AssertionError('专业对象不得调用普通引线 Annotation')
        self.rt.native['vla-get-annotation'] = unexpected
        self.call('c:YJST')
        self.assertEqual('部分完成', self.value('status'))
        self.assertEqual(1, self.value('uncovered'))
        self.assertEqual(before, obj)
        self.assertIn('TDbSymbMultiLeader', self.log())
        self.assertIn('1644', self.log())
        self.assertIn('UNSUPPORTED_OBJECT', self.log())
        self.assertNotIn('VLA-GET-ANNOTATION', self.log())
        self.assertEqual('leader', self.call('OCS:mapClass', 'AcDbLeader'))
        self.assertEqual('mleader', self.call('OCS:mapClass', 'AcDbMLeader'))

    def test_failed_call_keeps_context_and_complete_run_tail(self):
        self.bad_leader()
        self.call('c:YJST')
        self.assertEqual('预检失败', self.value('status'))
        self.assertEqual([], self.cad.events)
        rows = [json.loads(line) for line in self.log().splitlines()]
        self.assertEqual(list(range(1, len(rows) + 1)), [row[0] for row in rows])
        failed = next(row for row in rows if row[2] == 'CALL_ERROR')
        self.assertIn('AcDbLeader [1644]', failed[3])
        self.assertIn('*Model_Space', failed[3])
        self.assertEqual('VLA-GET-ANNOTATION', failed[4][0])
        self.assertIn('未知名称: Annotation', failed[4][1])
        self.assertIn('原图.dwg', self.log())
        self.assertEqual('RUN_BEGIN', rows[0][2])
        self.assertTrue(any(row[2] == 'RUN_RESULT' for row in rows))
        self.assertEqual('RUN_TIMING', rows[-2][2])
        self.assertEqual('RUN_END', rows[-1][2])
        self.assertEqual('预检失败', rows[-1][4])
        self.assertEqual(set(), self.cad.logs.handles)

    def test_tianzheng_dimension_never_calls_standard_textoverride(self):
        obj = self.cad.add(self.cad.entity('TDbDimension2', '1E76', ''))
        before = deepcopy(obj)
        def unexpected(obj):
            raise RuntimeError('ActiveX 服务器返回错误: 未知名称: TextOverride')
        self.rt.native['vla-get-textoverride'] = unexpected
        self.call('c:YJST')
        self.assertEqual('部分完成', self.value('status'))
        self.assertEqual(0, self.value('errors'))
        self.assertIsNone(self.value('tchChecked'))
        self.assertEqual(1, self.value('uncovered'))
        self.assertEqual(before, obj)
        self.assertNotIn('VLA-GET-TEXTOVERRIDE', self.log())
        self.assertIn('1E76', str(self.value('uncoveredDetail')))

    def test_standard_classes_are_explicit_and_substring_lookalikes_rejected(self):
        for name, expected in [('AcDbAlignedDimension', 'dim'), ('AcDbRotatedDimension', 'dim'),
                ('AcDb2LineAngularDimension', 'dim'), ('AcDb3PointAngularDimension', 'dim'),
                ('AcDbDiametricDimension', 'dim'), ('AcDbRadialDimension', 'dim'),
                ('AcDbRadialDimensionLarge', 'dim'), ('AcDbArcDimension', 'dim'),
                ('AcDbOrdinateDimension', 'dim'), ('AcDbTable', 'table'),
                ('AcDbTolerance', 'tolerance'), ('AcDbBlockReference', 'blockref')]:
            self.assertEqual(expected, self.call('OCS:mapClass', name), name)
        for name in ('TDbDimension2', 'TDbTable', 'TDbTolerance', 'TDbWBlock',
                     'VendorDimension', 'AcDbCustomDimension'):
            self.assertEqual('other', self.call('OCS:mapClass', name), name)

    def test_new_run_does_not_overwrite_previous_log(self):
        self.call('c:YJST')
        first_path, first_log = self.rt.get('*ocs:logpath*'), self.log()
        self.rt.steps = 0
        self.call('c:YJST')
        self.assertEqual('无需修改', self.value('status'))
        self.assertNotEqual(first_path, self.rt.get('*ocs:logpath*'))
        self.assertEqual(first_log, self.cad.logs.files[first_path])
        self.assertEqual(self.rt.get('*ocs:logpath*'), self.value('logPath'))
        self.assertFalse(truth(self.rt.get('*ocs:traceactive*')))

    def test_unwritable_log_does_not_hide_original_failure(self):
        self.bad_leader()
        self.rt.native['open'] = lambda *args: None
        self.call('c:YJST')
        self.assertEqual('预检失败', self.value('status'))
        self.assertIn('未知名称: Annotation', str(self.value('errorDetail')))
        self.assertIsNone(self.rt.get('*ocs:logpath*'))
        self.assertIn('日志目录不可写', self.rt.get('*ocs:logerror*'))
        self.assertLessEqual(len(self.rt.get('*ocs:logtail*')), 40)
        self.rt.output.clear()
        self.call('c:YJSTLOG')
        self.assertIn('未知名称: Annotation', ''.join(map(str, self.rt.output)))
        self.assertEqual([], self.cad.events)

    def test_midrun_write_failure_closes_file_and_retains_business_error(self):
        self.bad_leader()
        write = self.rt.native['write-line']
        def full_disk(line, stream):
            if 'CALL_ERROR' in line:
                raise OSError('disk full')
            return write(line, stream)
        self.rt.native['write-line'] = full_disk
        self.call('c:YJST')
        self.assertEqual('预检失败', self.value('status'))
        self.assertIn('未知名称: Annotation', str(self.value('errorDetail')))
        self.assertEqual('disk full', self.rt.get('*ocs:logerror*'))
        self.assertIn('VLA-GET-ANNOTATION', self.log())  # 失败前的 CALL_BEGIN 已关闭落盘。
        self.assertIn('RUN_END', self.rt.get('*ocs:logtail*')[-1])
        self.assertEqual(set(), self.cad.logs.handles)

    def test_legacy_open_and_directory_fallback(self):
        original_open = self.rt.native['open']
        getenv = self.rt.native['getenv']
        self.rt.native['getenv'] = lambda name: 'fallback/' if name == 'TEMP' else getenv(name)
        def legacy_open(path, mode, *encoding):
            if encoding:
                raise TypeError('too many arguments')
            if path.startswith('fixture/'):
                return None
            return original_open(path, mode)
        self.rt.native['open'] = legacy_open
        self.call('c:YJST')
        self.assertEqual('已完成', self.value('status'))
        self.assertTrue(self.rt.get('*ocs:logpath*').startswith('fallback/'))
        self.assertIn('CAD-legacy', self.log())
        self.assertIsNone(self.rt.get('*ocs:logerror*'))

    def test_log_written_to_real_utf8_file(self):
        with TemporaryDirectory(prefix='yjst-log-') as temp:
            getvar = self.rt.native['getvar']
            self.rt.native['getvar'] = lambda name: temp if name == 'TEMPPREFIX' else getvar(name)
            self.rt.native['open'] = lambda path, mode, encoding=None: open(path, mode, encoding=encoding or 'utf-8')
            self.rt.native['write-line'] = lambda line, stream: stream.write(line + '\n')
            self.rt.native['close'] = lambda stream: stream.close()
            self.bad_leader()
            self.call('c:YJST')
            content = Path(self.rt.get('*ocs:logpath*')).read_bytes().decode('utf-8')
            self.assertIn('未知名称: Annotation', content)
            self.assertIn('UTF-8', content)
            self.assertIn('RUN_END', content.splitlines()[-1])
            self.assertEqual('预检失败', self.value('status'))

    def test_rollback_result_is_logged(self):
        self.rt.native['vla-put-textstring'] = lambda *args: (_ for _ in ()).throw(RuntimeError('write failed'))
        self.call('c:YJST')
        self.assertEqual('失败已回滚', self.value('status'))
        for event in ('ROLLBACK_BEGIN', 'ROLLBACK_END', 'RECOVERY_RESULT', 'RUN_END'):
            self.assertIn(event, self.log())
        self.assertEqual(1, self.cad.events.count('undo'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
