"""日期：2026-10-14。排查日志、块引用异常证据与专业引线分类回归。"""
from copy import deepcopy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from cad_fixture import CadFixture
from lisp_eval import Pair, Runtime, truth

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

    def bad_block_ref(self):
        obj = self.cad.block_ref()
        obj['Handle'] = 'D5'
        self.name_reads = 0
        original_name = self.rt.native['vla-get-name']
        def name(value):
            if value is obj:
                self.name_reads += 1
                raise RuntimeError('Automation 错误。 空对象 ID')
            return original_name(value)
        self.rt.native['vla-get-name'] = name
        return obj

    def test_block_name_failure_logs_only_dxf_without_reprobing_object(self):
        obj = self.bad_block_ref()
        before = deepcopy(self.cad.tracked())
        entity_data = [Pair(0, 'INSERT'), Pair(5, 'D5'), Pair(2, 'ATTR_BLOCK'),
                       Pair(8, 'A-综合-建筑综合三'), Pair(330, 'owner-B1'),
                       Pair(100, 'AcDbBlockReference'), Pair(10, [1, 2, 3])]
        native_entget = self.rt.native['entget']
        def entget(entity, apps=None):
            records = {'entity-D5': entity_data,
                       'owner-B1': [Pair(0, 'BLOCK_RECORD'), Pair(5, 'B1'), Pair(2, '*Model_Space')],
                       'definition': [Pair(0, 'BLOCK'), Pair(2, 'ATTR_BLOCK'), Pair(70, 0)]}
            return records[entity] if isinstance(entity, str) and entity in records else native_entget(entity, apps)
        native_ename = self.rt.native['vlax-vla-object->ename']
        native_lookup = self.rt.native['tblobjname']
        self.rt.native.update({
            'vlax-vla-object->ename': lambda value: 'entity-D5' if value is obj else native_ename(value),
            'handent': lambda handle: 'entity-D5' if handle == 'D5' else None,
            'entget': entget,
            'vlax-object-released-p': lambda value: None,
            'vlax-erased-p': lambda value: None,
            'tblobjname': lambda table, name: 'definition' if table == 'BLOCK' and name == 'ATTR_BLOCK' else native_lookup(table, name),
            'tblsearch': lambda table, name: [Pair(2, name), Pair(70, 0)],
        })
        native_object = self.rt.native['vlax-ename->vla-object']
        self.rt.native['vlax-ename->vla-object'] = lambda entity: dict(Name='ATTR_BLOCK') if entity == 'entity-D5' else native_object(entity)
        self.call('c:YJST')
        self.assertEqual('预检失败', self.value('status'))
        self.assertIn('vla-get-Name：Automation 错误。 空对象 ID', str(self.value('errorDetail')))
        self.assertEqual(before, self.cad.tracked())
        self.assertEqual([], self.cad.events)
        rows = [json.loads(line) for line in self.log().splitlines()]
        begin = next(row for row in rows if row[2] == 'BLOCKREF_DIAG_BEGIN')
        self.assertIn('D5', str(begin[4]))
        self.assertIn('index', str(begin[4]))
        self.assertIn('2026-10-14-field-font-v7', str(rows[0]))
        dxf = [row for row in rows if row[2] == 'BLOCKREF_DIAG_DXF']
        self.assertEqual(1, len(dxf))
        self.assertIn('ATTR_BLOCK', str(dxf))
        self.assertIn('AcDbBlockReference', str(dxf))
        self.assertNotIn('[1, 2, 3]', str(dxf))  # 排除几何数据。
        self.assertEqual(1, self.name_reads)
        self.assertNotIn('object.reacquired', self.log())
        self.assertNotIn('object.released', self.log())
        self.assertIn('activeXProbes', str(begin[4]))
        self.assertIn('disabled', str(begin[4]))
        dxf_begin = next(row for row in rows if row[2] == 'BLOCKREF_DIAG_DXF_BEGIN')
        self.assertLess(rows.index(dxf_begin), rows.index(dxf[0]))
        self.assertTrue(any(row[2] == 'BLOCKREF_DIAG_END' for row in rows))
        self.assertEqual('RUN_END', rows[-1][2])
        self.assertEqual(set(), self.cad.logs.handles)

    def test_diagnostic_probe_errors_do_not_replace_original_error(self):
        self.bad_block_ref()
        handent = self.rt.native['handent']
        lookups = []
        def lookup(handle):
            lookups.append(handle)
            if len(lookups) > 1:
                raise RuntimeError('handle lookup failed')
            return handent(handle)
        self.rt.native['handent'] = lookup
        self.call('c:YJST')
        self.assertEqual('预检失败', self.value('status'))
        self.assertIn('空对象 ID', str(self.value('errorDetail')))
        self.assertNotIn('handle lookup failed', str(self.value('errorDetail')))
        self.assertIn('handle lookup failed', self.log())
        self.assertIn('unavailable', self.log())
        self.assertIn('BLOCKREF_DIAG_END', self.log())
        self.assertEqual([], self.cad.events)

    def test_whole_diagnostic_failure_keeps_original_error_and_run_end(self):
        self.bad_block_ref()
        self.rt.native['ocs:blockrefdiagnostic'] = lambda *args: (_ for _ in ()).throw(RuntimeError('diagnostic failed'))
        self.call('c:YJST')
        self.assertIn('空对象 ID', str(self.value('errorDetail')))
        self.assertIn('BLOCKREF_DIAG_ERROR', self.log())
        self.assertIn('diagnostic failed', self.log())
        self.assertIn('RUN_END', self.log())
        self.assertEqual([], self.cad.events)

    def test_healthy_block_does_not_trigger_failure_diagnostics(self):
        self.cad.block_ref()
        self.call('c:YJST')
        self.assertEqual('已完成', self.value('status'))
        self.assertNotIn('BLOCKREF_DIAG_BEGIN', self.log())


if __name__ == '__main__':
    unittest.main(verbosity=2)
