"""日期：2026-10-13。批量日志完整性、扫描顺序与命令总耗时回归。"""
from pathlib import Path
import json
import unittest

from cad_fixture import CadFixture
from lisp_eval import Runtime

SOURCE = Path(__file__).resolve().parent.parent / 'one-click-simsun.lsp'


class PerformanceTimingTests(unittest.TestCase):
    def setUp(self):
        self.rt = Runtime(SOURCE.read_text(encoding='utf-8'))
        self.rt.load()
        self.cad = CadFixture(self.rt)

    def call(self, name, *args):
        return self.rt.call(name, list(args))

    def value(self, report, key):
        return self.call('OCS:assocd', key, report, None)

    def test_batch_log_preserves_order_and_flushes_final_partial_batch(self):
        self.call('OCS:logStart')
        for i in range(150):
            self.call('OCS:trace', 'SAMPLE', i)
        self.call('OCS:trace', 'RUN_END', 'test')
        rows = [json.loads(x) for x in self.cad.logs.files[self.rt.get('*ocs:logpath*')].splitlines()]
        self.assertEqual(list(range(150)), [x[4] for x in rows if x[2] == 'SAMPLE'])
        self.assertEqual(list(range(1, len(rows) + 1)), [x[0] for x in rows])
        self.assertLess(len(self.cad.logs.opened), 10)
        self.assertEqual(0, self.rt.get('*ocs:logpendingcount*'))
        self.assertEqual(set(), self.cad.logs.handles)

    def test_scan_retains_order_and_deduplicates_objects(self):
        for i in range(60):
            self.cad.add(self.cad.entity('TDbOther', 'P' + str(i), ''))
        self.cad.blocks[0]['items'].append(self.cad.blocks[0]['items'][-1])
        result = self.call('OCS:CollectHosts')
        self.assertEqual(60, self.value(result, 'unknown'))
        details = self.value(result, 'skipped')
        self.assertEqual(['P' + str(i) for i in range(60)], [x[1] for x in details if x[0] == 'PROXY_OR_PRO'])
        self.assertFalse(self.rt.get('*ocs:collectreverse*'))

    def test_elapsed_seconds_supports_signed_and_unsigned_wrap(self):
        for start, end, expected in [(1000, 2234, 1.234), (2147483640, -2147483640, .016),
                                     (4294967290, 4, .010), (0, 0, 0.0)]:
            self.assertAlmostEqual(expected, self.call('OCS:elapsedSeconds', start, end))
        self.assertIsNone(self.call('OCS:elapsedSeconds', None, 0))

    def test_success_failure_and_check_all_report_timing(self):
        getvar = self.rt.native['getvar']
        ticks = [10000]
        def clock(name):
            if name == 'MILLISECS':
                ticks[0] += 10
                return ticks[0]
            return getvar(name)
        self.rt.native['getvar'] = clock
        for command, key in [('c:YJST', '*ocs:lastreport*'), ('c:YJSTCHECK', '*ocs:lastcheckreport*')]:
            self.rt.steps = 0
            self.call(command)
            report = self.rt.get(key)
            self.assertGreater(self.value(report, 'elapsedSeconds'), 0)
            self.assertTrue(self.value(report, 'phaseTimes'))
            self.assertIn('总耗时：', ''.join(map(str, self.rt.output)))
        self.cad.add(self.cad.entity('AcDbLeader', 'BAD', ''))
        def fail(obj):
            raise RuntimeError('read failed')
        self.rt.native['vla-get-annotation'] = fail
        self.rt.steps = 0
        self.call('c:YJST')
        report = self.rt.get('*ocs:lastreport*')
        self.assertEqual('预检失败', self.value(report, 'status'))
        self.assertGreater(self.value(report, 'elapsedSeconds'), 0)
        rows = [json.loads(x) for x in self.cad.logs.files[self.rt.get('*ocs:logpath*')].splitlines()]
        self.assertEqual('RUN_END', rows[-1][2])
        self.assertEqual(self.value(report, 'elapsedSeconds'), self.value(rows[-2][4], 'elapsedSeconds'))


if __name__ == '__main__':
    unittest.main()
