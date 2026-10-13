"""日期：2026-10-13。复现字体绑定被 SetFont 清空及本地化字体名差异。"""
import ntpath
from pathlib import Path
import unittest

from cad_fixture import CadFixture, TRUE, FALSE
from lisp_eval import Runtime

SOURCE = Path(__file__).resolve().parent.parent / 'one-click-simsun.lsp'


class FontBindingTests(unittest.TestCase):
    def setUp(self):
        self.rt = Runtime(SOURCE.read_text(encoding='utf-8'))
        self.rt.load()
        self.cad = CadFixture(self.rt)
        self.set_calls = []

    def call(self, name, *args):
        return self.rt.call(name, list(args))

    def value(self, key):
        return self.call('OCS:assocd', key, self.rt.get('*ocs:lastreport*'), None)

    def bind_engine(self, chinese_only=False):
        original_find = self.rt.native['findfile']
        self.rt.native['findfile'] = lambda name: None if name.lower() in ('simsun.ttc', 'simsun.ttf') else original_find(name)
        def put_file(obj, path):
            if not ntpath.isabs(path):
                raise RuntimeError('Automation 错误。 文件处理器错误')
            self.cad.put_dxf(obj, 3, path)
            # 现场 7112/7126 行：写文件后，字体描述符被重置。
            obj['font'] = ['', FALSE, FALSE, 1, 0]
        def set_font(obj, family, *args):
            self.set_calls.append((obj['Name'], family))
            resolved = 'NSimSun' if chinese_only and family == 'SimSun' else '宋体'
            self.cad.setfont(obj, resolved, *args)
            self.cad.put_dxf(obj, 3, '')
        self.rt.native['vla-put-fontfile'] = put_file
        self.rt.native['vla-setfont'] = set_font

    def test_mutually_exclusive_file_and_descriptor_matches_field_log(self):
        self.bind_engine()
        self.call('c:YJST')
        self.assertEqual('已完成', self.value('status'))
        self.assertEqual(1, self.value('stylesModified'))
        self.assertEqual('', self.cad.dxf(self.cad.styles['Standard'], 3))
        self.assertEqual('宋体', self.cad.styles['Standard']['font'][0])
        self.assertEqual(TRUE, self.cad.styles['Standard']['font'][1])
        content = self.cad.logs.files[self.rt.get('*ocs:logpath*')]
        self.assertIn('after-SetFont', content)
        self.assertNotIn('after-rebind', content)
        self.assertIn('typeface', content)
        self.assertIn('probe-after-regen', content)
        self.assertEqual({'Standard', 'XREF|Text', 'Shape'}, set(self.cad.styles))
        self.assertNotIn('undo', self.cad.events)
        self.rt.steps = 0
        before = len(self.set_calls)
        self.call('c:YJST')
        self.assertEqual('无需修改', self.value('status'))
        self.assertEqual(before, len(self.set_calls))

    def test_verified_chinese_name_is_used_in_business_write(self):
        self.bind_engine(chinese_only=True)
        self.call('c:YJST')
        self.assertEqual('已完成', self.value('status'))
        self.assertIn(('OCS_TMP_VERIFY_STYLE_0', 'SimSun'), self.set_calls)
        self.assertIn(('OCS_TMP_VERIFY_STYLE_0', '宋体'), self.set_calls)
        self.assertEqual([('Standard', '宋体')], [item for item in self.set_calls if item[0] == 'Standard'])
        self.assertEqual('宋体', self.cad.styles['Standard']['font'][0])

    def test_empty_descriptor_or_substitute_font_is_not_accepted(self):
        for mode in ('empty', 'substitute'):
            with self.subTest(mode=mode):
                self.setUp()
                before = self.cad.text['TextString']
                def broken_font(obj, family, *args):
                    self.cad.setfont(obj, 'NSimSun' if mode == 'substitute' else '', *args)
                self.rt.native['vla-setfont'] = broken_font
                if mode == 'empty':
                    self.rt.native['vla-put-fontfile'] = lambda obj, path: self.cad.put_dxf(obj, 3, '')
                self.call('c:YJST')
                self.assertEqual('失败已回滚', self.value('status'))
                self.assertEqual(0, self.value('recoverFailed'))
                self.assertEqual(1, self.value('stylesScanned'))
                self.assertEqual('txt.shx', self.cad.dxf(self.cad.styles['Standard'], 3))
                self.assertEqual(before, self.cad.text['TextString'])
                self.assertEqual(1, self.cad.events.count('undo'))

    def test_descriptor_must_preserve_original_bold(self):
        self.bind_engine()
        original = self.rt.native['vla-setfont']
        def reset_bold(obj, *args):
            original(obj, *args)
            obj['font'][1] = FALSE
        self.rt.native['vla-setfont'] = reset_bold
        self.call('c:YJST')
        self.assertEqual('失败已回滚', self.value('status'))
        self.assertEqual(TRUE, self.cad.styles['Standard']['font'][1])
        self.assertEqual('txt.shx', self.cad.dxf(self.cad.styles['Standard'], 3))
        self.assertEqual(1, self.cad.events.count('undo'))

    def test_fontfile_read_error_is_logged_as_error_not_empty(self):
        original = self.rt.native['vla-get-fontfile']
        def read_file(obj):
            if obj['Name'].startswith('OCS_TMP_'):
                raise RuntimeError('FontFile getter disconnected')
            return original(obj)
        self.rt.native['vla-get-fontfile'] = read_file
        self.call('c:YJST')
        self.assertEqual('失败已回滚', self.value('status'))
        self.assertIn('FontFile getter disconnected', str(self.value('errorDetail')))
        self.assertNotIn('FontFile 读回为空', str(self.value('errorDetail')))

    def test_font_binding_lost_after_regen_rolls_back(self):
        def lose_binding(*args):
            obj = self.cad.styles['Standard']
            if obj['font'][0] == 'SimSun':
                self.cad.put_dxf(obj, 3, '')
        self.rt.native['vla-regen'] = lose_binding
        self.call('c:YJST')
        self.assertEqual('失败已回滚', self.value('status'))
        self.assertEqual('txt.shx', self.cad.dxf(self.cad.styles['Standard'], 3))
        self.assertEqual(1, self.cad.events.count('undo'))

    def test_descriptor_lost_during_probe_regen_stops_before_business_write(self):
        self.bind_engine()
        def lose_descriptor(*args):
            for name, obj in self.cad.styles.items():
                if name.startswith('OCS_TMP_'):
                    obj['font'] = ['', FALSE, FALSE, 1, 0]
        self.rt.native['vla-regen'] = lose_descriptor
        self.call('c:YJST')
        self.assertEqual('失败已回滚', self.value('status'))
        self.assertFalse(any(name == 'Standard' for name, _ in self.set_calls))
        self.assertEqual('txt.shx', self.cad.dxf(self.cad.styles['Standard'], 3))

    def test_descriptor_change_during_final_regen_rolls_back(self):
        for field, bad in ((0, 'NSimSun'), (1, FALSE), (2, TRUE), (3, 1), (4, 0)):
            with self.subTest(field=field):
                self.setUp()
                self.bind_engine()
                def corrupt(*args):
                    obj = self.cad.styles['Standard']
                    if obj['font'][0] == '宋体':
                        obj['font'][field] = bad
                self.rt.native['vla-regen'] = corrupt
                self.call('c:YJST')
                self.assertEqual('失败已回滚', self.value('status'))
                self.assertEqual('txt.shx', self.cad.dxf(self.cad.styles['Standard'], 3))

    def test_nonempty_wrong_file_is_not_descriptor_mode(self):
        for bad in ('arial.ttf', 'txt.shx'):
            with self.subTest(file=bad):
                self.setUp()
                self.bind_engine()
                original = self.rt.native['vla-setfont']
                def wrong_file(obj, *args):
                    original(obj, *args)
                    self.cad.put_dxf(obj, 3, bad)
                self.rt.native['vla-setfont'] = wrong_file
                self.call('c:YJST')
                self.assertEqual('失败已回滚', self.value('status'))

    def test_file_and_dxf_disagreement_is_rejected(self):
        self.bind_engine()
        self.rt.native['vla-get-fontfile'] = lambda obj: 'simsun.ttc'
        self.call('c:YJST')
        self.assertEqual('失败已回滚', self.value('status'))

    def entmod_resets_descriptor(self):
        """日期：2026-10-13。复现 11053500 日志：即使 DXF 4 原本为空也重置字体。"""
        self.bind_engine()
        self.mutations = []
        original_entmod = self.rt.native['entmod']
        original_setfont = self.rt.native['vla-setfont']
        def reset(data):
            name = next(pair.cdr for pair in data if pair.car == 2)
            result = original_entmod(data)
            self.cad.styles[name]['font'] = ['', FALSE, FALSE, 1, 0]
            self.mutations.append((name, 'entmod'))
            return result
        def record_set(obj, *args):
            self.mutations.append((obj['Name'], 'SetFont'))
            return original_setfont(obj, *args)
        self.rt.native['entmod'] = reset
        self.rt.native['vla-setfont'] = record_set

    def test_entmod_reset_clears_bigfont_before_font_and_skips_empty_probe(self):
        self.entmod_resets_descriptor()
        self.cad.styles['Standard']['font'][2] = TRUE
        self.call('c:YJST')
        self.assertEqual('已完成', self.value('status'))
        self.assertEqual([('Standard', 'entmod'), ('Standard', 'SetFont')],
                         [item for item in self.mutations if item[0] == 'Standard'])
        self.assertFalse(any(name.startswith('OCS_TMP_') and op == 'entmod'
                             for name, op in self.mutations))
        self.assertEqual(['宋体', TRUE, TRUE, 134, 22], self.cad.styles['Standard']['font'])
        self.assertEqual('', self.cad.dxf(self.cad.styles['Standard'], 4))
        self.assertNotIn('undo', self.cad.events)
        before = list(self.mutations)
        self.rt.steps = 0
        self.call('c:YJST')
        self.assertEqual('无需修改', self.value('status'))
        self.assertEqual(before, self.mutations)

    def test_clear_failure_never_sets_business_font_and_rolls_back(self):
        for kind in ('nil', 'error', 'ineffective'):
            with self.subTest(kind=kind):
                self.setUp()
                self.entmod_resets_descriptor()
                def reject(data):
                    if kind == 'error':
                        raise RuntimeError('STYLE write denied')
                    return None if kind == 'nil' else data
                self.rt.native['entmod'] = reject
                self.call('c:YJST')
                self.assertEqual('失败已回滚', self.value('status'))
                self.assertEqual(0, self.value('recoverFailed'))
                self.assertFalse(any(name == 'Standard' for name, _ in self.set_calls))
                self.assertEqual('hztxt.shx', self.cad.dxf(self.cad.styles['Standard'], 4))
                message = {'nil': 'entmod 返回 nil', 'error': 'STYLE write denied',
                           'ineffective': '大字体读回非空或不一致'}[kind]
                self.assertIn(message, str(self.value('errorDetail')))

    def test_empty_or_missing_dxf_bigfont_still_checks_com(self):
        for missing in (False, True):
            with self.subTest(missing=missing):
                self.setUp()
                obj = self.cad.styles['Standard']
                self.cad.put_dxf(obj, 4, '')
                if missing:
                    obj['dxf'] = [p for p in obj['dxf'] if p.car != 4]
                self.rt.native['vla-get-bigfontfile'] = lambda obj: 'stale-bigfont.shx'
                self.call('c:YJST')
                self.assertEqual('失败已回滚', self.value('status'))
                self.assertEqual(0, self.value('recoverFailed'))
                self.assertIn('stale-bigfont.shx', str(self.value('errorDetail')))

    def test_setfont_reintroducing_bigfont_is_rejected_without_post_write_entmod(self):
        self.entmod_resets_descriptor()
        original = self.rt.native['vla-setfont']
        def reintroduce(obj, *args):
            original(obj, *args)
            self.cad.put_dxf(obj, 4, 'bad-bigfont.shx')
        self.rt.native['vla-setfont'] = reintroduce
        self.call('c:YJST')
        self.assertEqual('失败已回滚', self.value('status'))
        self.assertFalse(any(op == 'entmod' for _, op in self.mutations))


if __name__ == '__main__':
    unittest.main(verbosity=2)
