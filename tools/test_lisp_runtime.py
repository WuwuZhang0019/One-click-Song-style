"""日期：2026-10-13。实际 LISP 源码回归；CAD 边界使用可控替身。"""
import json
from copy import deepcopy
from itertools import product
from pathlib import Path
import unittest

from lisp_eval import Pair, Runtime, Symbol, arity_errors, truth
from cad_fixture import CadFixture, SafeArray, Variant, TRUE

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'one-click-simsun.lsp'


class LispRegression(unittest.TestCase):
    def setUp(self):
        self.rt = Runtime(SOURCE.read_text(encoding='utf-8'))
        self.rt.load()
        self.rt.steps = 0
        self.rt.native['getvar'] = lambda name: {'DWGPREFIX': 'fixture/', 'ACADVER': 'test'}.get(name, 1)

    def call(self, name, *args):
        return self.rt.call(name, list(args))

    def value(self, data, key, default=None):
        return self.call('OCS:assocd', key, data, default)

    def test_all_call_arities(self):
        self.assertEqual([], arity_errors(SOURCE.read_text(encoding='utf-8')))

    def test_autolisp_truth(self):
        self.assertTrue(truth(0))
        self.assertTrue(truth(''))
        self.assertFalse(truth(None))

    def test_plist_keys_do_not_match_values(self):
        data = ['name', 'status', 'status', 'ok', ['problem', 'error', 'detail']]
        self.assertEqual('ok', self.value(data, 'status'))
        changed = self.call('OCS:putPair', data, 'status', 'new')
        self.assertEqual('status', self.value(changed, 'name'))
        self.assertEqual('new', self.value(changed, 'status'))

    def test_dxf_read(self):
        data = [Pair(2, 'Standard'), Pair(70, 16), Pair(4, 'hztxt.shx')]
        self.assertEqual(16, self.value(data, 70, 0))
        self.assertEqual('hztxt.shx', self.value(data, 4, ''))
        self.assertEqual('missing', self.value(data, 3, 'missing'))

    def test_scanner_vectors_and_idempotence(self):
        cases = json.loads((ROOT / 'tests/font-format-cases.json').read_text(encoding='utf-8'))['cases']
        target = ['family', 'SimSun', 'charSet', 134, 'pitchFamily', 22, 'appendParams', True]
        for case in cases:
            with self.subTest(case=case['id']):
                self.rt.steps = 0
                raw = case['input']
                expected = case['expected']
                if 'synthetic' in case:
                    raw = expected = case['synthetic']['pattern'] * case['synthetic']['count']
                result = self.call('OCS:NormalizeFontRuns', raw, target)
                self.assertEqual(raw if expected is None else expected, self.value(result, 'text'))
                self.assertEqual(case['expectChanges'], self.value(result, 'changes'))
                self.assertEqual(case['expectErrors'], len(self.value(result, 'issues') or []))
                if expected is not None:
                    again = self.call('OCS:NormalizeFontRuns', expected, target)
                    self.assertEqual(expected, self.value(again, 'text'))
                    self.assertEqual(0, self.value(again, 'changes'))

    def test_native_selftest(self):
        self.assertEqual(0, self.call('OCS:SelfTest'))

    def test_field_end_does_not_duplicate_following_character(self):
        raw = r'A%<\AcVar X \f "%pr2">%B{\fArial;C}'
        result = self.call('OCS:NormalizeFontRuns', raw, None)
        self.assertEqual(r'A%<\AcVar X \f "%pr2">%B{\fSimSun|c134|pf22;C}', self.value(result, 'text'))
        self.assertFalse(truth(self.value(result, 'issues')))

    def test_mainflow_preflight_success(self):
        self.rt.native.update({
            'ocs:preflight': lambda: ['ok', True, 'font', ['family', 'SimSun']],
            'ocs:buildplan': lambda: ['styles', None, 'hosts', None],
            'ocs:beginundogroup': lambda: True,
            'ocs:executewrites': lambda: self.call('OCS:makeReport', '已完成'),
        })
        self.call('c:YJST')
        self.assertEqual('已完成', self.value(self.rt.get('*ocs:lastreport*'), 'status'))
        self.assertFalse(truth(self.rt.get('*ocs:running*')))

    def test_write_exception_preserves_original_error(self):
        cad = CadFixture(self.rt)
        def fail():
            raise RuntimeError('injected write failure')
        self.rt.native['ocs:executewrites'] = fail
        self.call('c:YJST')
        report = self.rt.get('*ocs:lastreport*')
        self.assertEqual('失败已回滚', self.value(report, 'status'), str(report))
        self.assertIn('injected write failure', str(self.value(report, 'errorDetail')))
        self.assertFalse(truth(self.rt.get('*ocs:running*')))
        self.assertNotIn('undo', cad.events)

    def test_zero_errors_does_not_rollback(self):
        rollback = []
        self.rt.set('*ocs:plan*', ['styles', None, 'hosts', None, 'stats', None])
        self.rt.native.update({
            'ocs:locklayersneeded': lambda: None, 'ocs:unlocktemplayers': lambda: None,
            'ocs:applyallstyles': lambda: ['modified', 0, 'error', None],
            'ocs:applyallhosts': lambda: ['changes', 0, 'error', None],
            'ocs:restoretempstate': lambda: True, 'ocs:verifydrawing': lambda: ['ok', True],
            'ocs:endundogroup': lambda: True,
            'ocs:rollback': lambda: rollback.append(True) or True,
        })
        report = self.call('OCS:executeWrites')
        self.assertEqual([], rollback)
        self.assertEqual('无需修改', self.value(report, 'status'))

    def test_command_with_cad_fixture(self):
        cad = CadFixture(self.rt)
        self.call('c:YJST')
        report = self.rt.get('*ocs:lastreport*')
        self.assertEqual('已完成', self.value(report, 'status'), str(report))
        self.assertEqual(1, self.value(report, 'stylesModified'))
        self.assertEqual(2, self.value(report, 'fontRunsChanged'))
        self.assertEqual(1, self.value(report, 'stylesXref'))
        self.assertEqual(1, self.value(report, 'xrefBlocks'))
        self.assertIn(r'\fSimSun|b1|i0|c134|pf22;', cad.text['TextString'])
        self.assertIn(r'\fSimSun|c134|pf22;', cad.dynamic['TextString'])
        self.assertIn(r'\fArial;', cad.xref['TextString'])
        self.assertEqual(TRUE, cad.layer['Lock'])
        self.assertEqual(TRUE, cad.styles['Standard']['font'][1])
        self.assertEqual(0.8, cad.dxf(cad.styles['Standard'], 41))
        self.assertEqual({'Standard', 'XREF|Text', 'Shape'}, set(cad.styles))
        self.assertNotIn('undo', cad.events)
        self.rt.steps = 0
        self.call('c:YJST')
        report = self.rt.get('*ocs:lastreport*')
        self.assertEqual('无需修改', self.value(report, 'status'), str(report))
        self.assertEqual(0, self.value(report, 'stylesModified'))
        self.assertEqual(0, self.value(report, 'fontRunsChanged'))

    def test_command_write_failure_rolls_back_fixture(self):
        cad = CadFixture(self.rt)
        original = cad.text['TextString']
        def fail(obj, text):
            raise RuntimeError('fixture write failed')
        self.rt.native['vla-put-textstring'] = fail
        self.call('c:YJST')
        report = self.rt.get('*ocs:lastreport*')
        self.assertEqual('失败已回滚', self.value(report, 'status'), str(report))
        self.assertEqual(0, self.value(report, 'recoverFailed'))
        self.assertEqual(1, cad.events.count('undo'))
        self.assertEqual('txt.shx', cad.dxf(cad.styles['Standard'], 3))
        self.assertEqual('hztxt.shx', cad.dxf(cad.styles['Standard'], 4))
        self.assertEqual(original, cad.text['TextString'])
        self.assertEqual(TRUE, cad.layer['Lock'])

    def test_command_attribute_safearrays(self):
        for ordinary_count, constant_count in ((1, 0), (0, 1), (1, 1), (0, 0)):
            with self.subTest(ordinary=ordinary_count, constant=constant_count):
                self.setUp()
                cad = CadFixture(self.rt)
                ordinary = [cad.attribute('A1', r'{\fArial;普通属性}')] * ordinary_count
                constants = [cad.attribute('A2', r'{\fSimHei;常量属性}')] * constant_count
                block = cad.block_ref(ordinary, constants)
                for method in ('vla-getattributes', 'vla-getconstantattributes'):
                    returned = self.call(method, block)
                    self.assertIsInstance(returned, Variant)
                    self.assertIsInstance(returned.value, SafeArray)
                self.call('c:YJST')
                report = self.rt.get('*ocs:lastreport*')
                self.assertEqual('已完成', self.value(report, 'status'), str(report))
                self.assertEqual(ordinary_count + constant_count, self.value(report, 'attribs'))
                self.assertEqual(2 + ordinary_count + constant_count, self.value(report, 'fontRunsChanged'))
                for attr in ordinary + constants:
                    self.assertIn(r'\fSimSun|c134|pf22;', attr['MTextAttributeContent'])
                self.assertNotIn('undo', cad.events)

    def test_variant_and_safearray_unpacking(self):
        CadFixture(self.rt)
        for wrapped in (SafeArray([]), Variant(SafeArray([]))):
            with self.subTest(wrapped=type(wrapped).__name__):
                self.assertFalse(truth(self.call('OCS:variantToList', wrapped)))
        sentinel = {'Handle': 'A1'}
        self.assertIs(sentinel, self.call('OCS:variantToList', Variant(SafeArray([sentinel], lower=3)))[0])
        self.assertEqual([sentinel], self.call('OCS:variantToList', [sentinel]))
        self.assertFalse(truth(self.call('OCS:variantToList', None)))

    def test_safearray_errors_stop_command_before_writes(self):
        interfaces = ('vlax-safearray->list', 'vlax-safearray-get-dim',
                      'vlax-safearray-get-l-bound', 'vlax-safearray-get-u-bound')
        for native, attribute_method in product(interfaces, ('VLA-GETATTRIBUTES', 'VLA-GETCONSTANTATTRIBUTES')):
            with self.subTest(native=native, method=attribute_method):
                self.setUp()
                cad = CadFixture(self.rt)
                attr = cad.attribute('A1', r'{\fArial;属性}')
                constant = cad.attribute('A2', r'{\fArial;常量属性}')
                cad.block_ref([attr], [constant])
                before = deepcopy(cad.tracked())
                message = 'injected nonempty SAFEARRAY failure: ' + native
                failing_attr = attr if attribute_method == 'VLA-GETATTRIBUTES' else constant
                original = self.rt.native[native]
                def fail(array, *args):
                    if any(item is failing_attr for item in array.values):
                        raise RuntimeError(message)
                    return original(array, *args)
                self.rt.native[native] = fail
                self.call('c:YJST')
                report = self.rt.get('*ocs:lastreport*')
                self.assertEqual('预检失败', self.value(report, 'status'), str(report))
                details = str(self.value(report, 'errorDetail'))
                self.assertIn(message, details)
                self.assertIn('ATTR_BLOCK [REF1] / ' + attribute_method, details)
                self.assertIn(native.upper(), details)
                self.assertEqual([], cad.events)
                self.assertEqual(before, cad.tracked())

    def test_empty_undo_group_does_not_undo_previous_action(self):
        cad = CadFixture(self.rt)
        self.call('OCS:beginUndoGroup')
        self.assertTrue(self.call('OCS:Rollback'))
        self.assertNotIn('undo', cad.events)

    def test_readback_rejects_silent_text_write_failure(self):
        cad = CadFixture(self.rt)
        self.rt.native['vla-put-textstring'] = lambda obj, text: None
        self.call('c:YJST')
        report = self.rt.get('*ocs:lastreport*')
        self.assertEqual('失败已回滚', self.value(report, 'status'))
        self.assertEqual(1, cad.events.count('undo'))

    def test_geometry_is_not_reported_as_uncovered_text(self):
        self.assertFalse(truth(self.call('OCS:isUnknownClass', 'AcDbLine')))
        self.assertTrue(truth(self.call('OCS:isUnknownClass', 'TCH_TEXT')))

    def test_nested_field_and_unclosed_field(self):
        raw = r'%<outer %<inner \fArial;>% tail>%X{\fArial;Y}'
        result = self.call('OCS:NormalizeFontRuns', raw, None)
        self.assertEqual(r'%<outer %<inner \fArial;>% tail>%X{\fSimSun|c134|pf22;Y}', self.value(result, 'text'))
        self.assertFalse(truth(self.value(result, 'issues')))
        raw = r'%<outer \fArial;'
        result = self.call('OCS:NormalizeFontRuns', raw, None)
        self.assertEqual(raw, self.value(result, 'text'))
        self.assertEqual(1, len(self.value(result, 'issues')))

    def test_table_multiple_contents_and_repeat(self):
        cad = CadFixture(self.rt)
        table = cad.table([dict(text=r'{\fArial;甲}'), dict(text=r'{\fSimHei;乙}')])
        self.call('c:YJST')
        report = self.rt.get('*ocs:lastreport*')
        self.assertEqual('已完成', self.value(report, 'status'), str(report))
        self.assertEqual(2, self.value(report, 'tableContents'))
        for part in table['cells'][0][0]['contents']:
            self.assertIn('SimSun', part['text'])
        self.assertEqual(Symbol(':vlax-false'), table['RegenerateTableSuppressed'])
        self.rt.steps = 0
        self.call('c:YJST')
        self.assertEqual('无需修改', self.value(self.rt.get('*ocs:lastreport*'), 'status'))

    def test_block_mleader_skips_missing_text(self):
        CadFixture(self.rt)
        result = self.call('OCS:readMLeader', None, dict(ContentType=1))
        self.assertTrue(truth(self.value(result, 'skip')))

    def test_protected_fields_and_literal_text(self):
        cad = CadFixture(self.rt)
        literal = cad.add(cad.entity('AcDbText', 'LIT', r'文件\fArial;'))
        cad.text['TextString'] = r'%<field>%{\fArial;单位}'
        before = cad.text['TextString']
        table = cad.table([dict(text=r'{\fArial;公式}', formula=TRUE)])
        self.call('c:YJST')
        report = self.rt.get('*ocs:lastreport*')
        self.assertEqual('部分完成', self.value(report, 'status'), str(report))
        self.assertEqual(before, cad.text['TextString'])
        self.assertEqual(r'文件\fArial;', literal['TextString'])
        self.assertIn('Arial', table['cells'][0][0]['contents'][0]['text'])

    def test_read_error_stops_before_writes(self):
        cad = CadFixture(self.rt)
        cad.table()
        self.rt.native['vla-gettextstring'] = lambda *args: (_ for _ in ()).throw(RuntimeError('connection lost'))
        self.call('c:YJST')
        report = self.rt.get('*ocs:lastreport*')
        self.assertEqual('预检失败', self.value(report, 'status'), str(report))
        self.assertEqual([], cad.events)
        self.assertEqual('txt.shx', cad.dxf(cad.styles['Standard'], 3))

    def test_silent_undo_failure_is_reported(self):
        cad = CadFixture(self.rt)
        self.rt.native['vla-put-textstring'] = lambda *args: (_ for _ in ()).throw(RuntimeError('write failed'))
        self.rt.native['command-s'] = lambda cmd: None
        self.call('c:YJST')
        report = self.rt.get('*ocs:lastreport*')
        self.assertEqual('恢复失败', self.value(report, 'status'), str(report))
        self.assertEqual(1, self.value(report, 'recoverFailed'))

    def test_regen_change_is_detected(self):
        cad = CadFixture(self.rt)
        self.rt.native['vla-regen'] = lambda *args: cad.text.update(TextString='unexpected change')
        self.call('c:YJST')
        report = self.rt.get('*ocs:lastreport*')
        self.assertEqual('失败已回滚', self.value(report, 'status'), str(report))
        self.assertEqual(1, cad.events.count('undo'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
