"""日期：2026-10-14。手动独立命令入口、版本证据及撤销上下文回归。"""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from build_gb2312 import command_parts, convert_one
from cad_fixture import CadFixture
from lisp_eval import Runtime, arity_errors

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'one-click-simsun.lsp'


class CommandEntryTests(unittest.TestCase):
    def setUp(self):
        self.source = SOURCE.read_bytes().decode('utf-8-sig')
        self.version, self.prefix, self.suffix = command_parts(self.source)
        self.bundle = self.prefix + self.source + self.suffix
        self.rt = Runtime(self.bundle)
        self.cad = CadFixture(self.rt)

    def report(self, key):
        return self.rt.call('OCS:assocd', [key, self.rt.get('*ocs:lastreport*'), None])

    def test_load_only_registers_then_manual_command_runs_current_version_once(self):
        self.assertEqual([], arity_errors(self.bundle))
        table = self.cad.table()
        getter = self.rt.native['vla-gettextstring']
        indices = []
        def nonthrowing(obj, row, col, content):
            indices.append(content)
            return getter(obj, row, col, 0)
        self.rt.native['vla-gettextstring'] = nonthrowing
        self.rt.set('*ocs:version*', '0.2.10')
        self.rt.load()
        self.assertEqual([], self.cad.events)
        self.assertEqual({}, self.cad.logs.files)
        self.assertIsNone(self.rt.get('*ocs:lastreport*'))
        self.assertNotIn('(c:YJSTFIX)', self.prefix + self.suffix)
        self.rt.call('c:YJSTFIX', [])
        self.assertEqual('0.2.14', self.version)
        self.assertEqual('已完成', self.report('status'))
        self.assertEqual({0}, set(indices))
        self.assertIn('SimSun', table['cells'][0][0]['contents'][0]['text'])
        log = self.cad.logs.files[self.rt.get('*ocs:logpath*')]
        rows = [json.loads(row) for row in log.splitlines()]
        begins = [row for row in rows if row[2] == 'RUN_BEGIN']
        self.assertEqual(1, len(begins))
        self.assertIn('0.2.14', str(begins[0]))
        self.assertIn('2026-10-14-table-display-v6', str(begins[0]))
        self.assertEqual('RUN_END', rows[-1][2])
        self.assertNotIn('(command', self.suffix)
        self.assertNotIn('(load', self.prefix + self.suffix)
        self.assertEqual(1, self.cad.events.count('start'))

    def test_external_undo_group_still_prevents_writes(self):
        getvar = self.rt.native['getvar']
        self.rt.native['getvar'] = lambda name: 9 if name == 'UNDOCTL' else getvar(name)
        self.rt.load()
        self.rt.call('c:YJSTFIX', [])
        self.assertEqual('预检失败', self.report('status'))
        self.assertIn('已有外部撤销分组', str(self.report('errorDetail')))
        self.assertEqual([], self.cad.events)

    def test_existing_running_or_unclosed_undo_mark_is_preserved_before_initialization(self):
        for flag in ('*ocs:running*', '*ocs:undomark*'):
            with self.subTest(flag=flag):
                rt = Runtime(self.bundle)
                cad = CadFixture(rt)
                rt.set(flag, True)
                rt.set('*ocs:version*', 'old-version')
                with self.assertRaisesRegex(RuntimeError, 'quit / exit abort'):
                    rt.load()
                self.assertTrue(rt.get(flag))
                self.assertEqual('old-version', rt.get('*ocs:version*'))
                self.assertEqual([], cad.events)
                self.assertEqual({}, cad.logs.files)

    def test_unreadable_d5_is_skipped_before_name_access(self):
        block = self.cad.block_ref()
        block['Handle'] = 'D5'
        entget = self.rt.native['entget']
        self.rt.native['entget'] = lambda entity, *args: None if entity is block else entget(entity, *args)
        name = self.rt.native['vla-get-name']
        reads = []
        def block_name(obj):
            if obj is block:
                reads.append('D5')
                raise RuntimeError('Automation 错误。 空对象 ID')
            return name(obj)
        self.rt.native['vla-get-name'] = block_name
        self.rt.load()
        self.rt.call('c:YJSTFIX', [])
        self.assertEqual([], reads)
        self.assertEqual('部分完成', self.report('status'))
        self.assertEqual(0, self.report('errors'))

    def test_gb2312_bundle_matches_source_and_wrapper_exactly(self):
        with TemporaryDirectory(dir=ROOT / 'output/test-tmp', prefix='command-') as temp:
            target = Path(temp) / 'YJSTFIX.lsp'
            self.assertEqual(0, convert_one(SOURCE, target, self.prefix, self.suffix))
            data = target.read_bytes()
            self.assertEqual(self.bundle, data.decode('gb2312'))
            self.assertEqual(self.bundle.encode('gb2312'), data)
            self.assertFalse(data.startswith(b'\xef\xbb\xbf'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
