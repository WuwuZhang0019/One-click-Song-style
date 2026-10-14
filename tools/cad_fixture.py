"""日期：2026-10-14。最小 CAD 数据替身，仅检验 LISP 调用衔接与数据保持。"""
from copy import deepcopy
import io
import json
import ntpath
from lisp_eval import Pair, Symbol, car, cdr

TRUE, FALSE = Symbol(':vlax-true'), Symbol(':vlax-false')


class LogFixture:
    """日期：2026-10-13。模拟 CAD 文件接口；关闭文件后才提交日志字节。"""

    def __init__(self, runtime):
        self.files = {}
        self.opened = []
        self.handles = set()
        runtime.native.update({
            'open': self.open, 'write-line': self.write_line, 'close': self.close,
            'vl-prin1-to-string': lambda value: json.dumps(value, ensure_ascii=False, default=str),
            'getenv': lambda name: 'fixture/' if name == 'TEMP' else 'C:/Windows',
        })

    def open(self, path, mode, encoding=None):
        stream = io.StringIO(self.files.get(path, '') if mode == 'a' else '')
        stream.seek(0, io.SEEK_END)
        stream.log_path = path
        self.opened.append((path, mode, encoding))
        self.handles.add(stream)
        return stream

    @staticmethod
    def write_line(line, stream):
        stream.write(line + '\n')
        return line

    def close(self, stream):
        self.files[stream.log_path] = stream.getvalue()
        self.handles.remove(stream)
        stream.close()
        return None


class Variant:
    def __init__(self, value):
        self.value = value


class SafeArray:
    """一维 COM 数组；合法空数组的上下界为 0/-1，转换会报无效索引。"""

    def __init__(self, values, lower=0):
        self.values = list(values)
        self.lower = lower

    def bound(self, dimension, upper=False):
        if dimension != 1:
            raise IndexError('Invalid dimension')
        return self.lower + len(self.values) - 1 if upper else self.lower

    def to_list(self):
        if not self.values:
            raise IndexError('ActiveX server returned an error: Invalid index 8002000B')
        return list(self.values)


class CadFixture:
    def __init__(self, runtime):
        self.rt = runtime
        self.styles = {}
        self.records = {}  # 日期：2026-10-14。字段 DXF 对象仅用于只读 handent/entget 回归。
        self.styles['Standard'] = self.style('Standard', 'txt.shx', 'hztxt.shx')
        self.styles['XREF|Text'] = self.style('XREF|Text', 'txt.shx', '', flags=16)
        self.styles['Shape'] = self.style('Shape', 'shape.shx', '', flags=1)
        self.layer = {'Name': 'LOCKED', 'Lock': TRUE}
        self.text = self.entity('AcDbMText', 'T1', r'{\fArial|b1|i0;标题}\P{\H0.7x;说明}')
        self.dynamic = self.entity('AcDbMText', 'T2', r'{\fSimHei;动态文字}')
        self.xref = self.entity('AcDbMText', 'T3', r'{\fArial;外参文字}')
        self.blocks = [
            dict(Name='*Model_Space', Handle='B1', IsXRef=FALSE, items=[self.text]),
            dict(Name='*U1', Handle='B2', IsXRef=FALSE, items=[self.dynamic]),
            dict(Name='REF', Handle='B3', IsXRef=TRUE, items=[self.xref]),
        ]
        self.doc = dict(Blocks={'items': self.blocks}, Layers={'items': [self.layer]}, ReadOnly=FALSE)
        self.events = []
        self.snapshot = None
        self.enumeration = iter(())
        rt = runtime
        self.logs = LogFixture(rt)
        original_type = rt.native['type']
        rt.native.update({
            'vl-filename-base': lambda name: ntpath.splitext(ntpath.basename(name))[0],
            'vl-filename-extension': lambda name: ntpath.splitext(name)[1] or None,
            'type': lambda value: Symbol('variant') if isinstance(value, Variant) else Symbol('safearray') if isinstance(value, SafeArray) else original_type(value),
            'getvar': lambda name: {'DWGPREFIX': 'fixture/', 'DWGNAME': '原图.dwg', 'TEMPPREFIX': 'fixture/', 'CDATE': 20261013.110000, 'MILLISECS': 1234, 'ACADVER': 'test', 'PRODUCT': 'fixture', 'LISPSYS': 0, 'PLATFORM': 'test', 'UNDOCTL': 1}.get(name),
            'findfile': lambda name: name if name in self.logs.files or name.lower().endswith(('simsun.ttc', 'txt.shx')) else None,
            'vlax-get-acad-object': lambda: 'application',
            'vla-get-activedocument': lambda app: self.doc,
            'vlax-property-available-p': lambda obj, prop: str(prop).lower() in {k.lower() for k in obj},
            'vla-fieldcode': lambda obj: obj['TextString'],
            'exit': self.exit,
            'tblobjname': lambda table, name: name if name in self.styles else None,
            'tblnext': self.tblnext, 'entget': self.entget, 'handent': self.handent, 'vlax-vla-object->ename': lambda obj: obj, 'dictsearch': lambda obj, key: obj.get(key),
            'entmake': self.entmake, 'entmod': self.entmod,
            'vlax-ename->vla-object': lambda name: name if isinstance(name, dict) else self.styles[name],
            'vla-delete': lambda obj: self.styles.pop(obj['Name']),
            'vla-item': self.item,
            'vla-get-count': lambda obj: len(obj['items']),
            'vla-setfont': self.setfont, 'vla-getfont': self.getfont,
            'vla-put-fontfile': lambda obj, value: self.put_dxf(obj, 3, value),
            'vla-get-fontfile': lambda obj: self.dxf(obj, 3),
            'vla-get-bigfontfile': lambda obj: self.dxf(obj, 4),
            'vla-startundomark': self.start,
            'vla-endundomark': lambda doc: self.events.append('end'),
            'vla-regen': lambda doc, mode: self.events.append('regen'),
            'vla-recomputetableblock': lambda table: self.events.append('table-recompute'),
            'vla-put-textstring': self.put_text,
            'vla-put-lock': self.put_lock,
            'command-s': self.command,
        })
        for prop in ('Blocks', 'Layers', 'ReadOnly', 'Name', 'Handle', 'IsXRef', 'ObjectName', 'TextString', 'Height', 'Width', 'Rotation', 'Layer', 'Color', 'StyleName', 'Lock', 'Rows', 'Columns', 'RegenerateTableSuppressed', 'MTextAttribute', 'MTextAttributeContent', 'TextOverride', 'ContentType', 'HasAttributes', 'Annotation', 'ColorMethod', 'ColorIndex', 'Red', 'Green', 'Blue', 'BookName', 'ColorName'):
            rt.native['vla-get-' + prop.lower()] = lambda obj, prop=prop: obj[prop]

        rt.native.update({
            'vla-ismergedcell': self.merged,
            'vla-getrowheight': lambda e, r: e['heights'][r],
            'vla-getcolumnwidth': lambda e, c: e['widths'][c],
            'vla-getcellstate': lambda e, r, c: e['cells'][r][c].get('state', 0),
            'vla-getcontenttype': lambda e, r, c: e['cells'][r][c].get('type', 1),
            'vla-isempty': lambda e, r, c: FALSE if e['cells'][r][c]['contents'] else TRUE,
            'vla-gettextstring': lambda e, r, c, n: self.content(e, r, c, n)['text'],
            'vla-gettextstyle2': lambda e, r, c, n: self.content(e, r, c, n).get('style', 'Standard'),
            'vla-gettextheight2': lambda e, r, c, n: self.content(e, r, c, n).get('height', 3.5),
            'vla-getfieldid2': lambda e, r, c, n: self.content(e, r, c, n).get('field', 0),
            'vla-gethasformula': lambda e, r, c, n: self.content(e, r, c, n).get('formula', FALSE),
            'vla-getcellalignment': lambda e, r, c: 5,
            'vla-getcellcontentcolor': lambda e, r, c: dict(ColorMethod=195, ColorIndex=3, Red=0, Green=255, Blue=0, BookName='', ColorName=''),
            'vla-settextstring': self.table_put,
            'vla-put-regeneratetablesuppressed': lambda e, value: e.update(RegenerateTableSuppressed=value),
            'vla-put-mtextattributecontent': lambda e, value: e.update(MTextAttributeContent=value),
            'vla-updatemtextattribute': lambda e: None,
            'vla-put-textoverride': lambda e, value: e.update(TextOverride=value),
            'vla-getattributes': lambda e: Variant(SafeArray(e.get('attributes', []))),
            'vla-getconstantattributes': lambda e: Variant(SafeArray(e.get('constants', []))),
            'vlax-variant-value': lambda v: v.value,
            'vlax-safearray-get-dim': lambda v: 1,
            'vlax-safearray-get-l-bound': lambda v, dim: v.bound(dim),
            'vlax-safearray-get-u-bound': lambda v, dim: v.bound(dim, upper=True),
            'vlax-safearray->list': lambda v: v.to_list(),
        })

    def entget(self, name, apps=None):
        if isinstance(name, dict):
            if 'dxf' in name:
                return deepcopy(name['dxf'])
            return [Pair(360, name['fields'])] if name.get('fields') else []
        return deepcopy(self.styles[name]['dxf'])

    def tracked(self):
        objects = [self.styles, self.layer, self.records]
        for block in self.blocks:
            for obj in block['items']:
                for candidate in [obj] + obj.get('attributes', []) + obj.get('constants', []):
                    if not any(candidate is old for old in objects):
                        objects.append(candidate)
        return objects

    def add(self, obj):
        self.blocks[0]['items'].append(obj)
        return obj

    def handent(self, handle):
        if handle in self.records:
            return self.records[handle]
        for block in self.blocks:
            if block.get('Handle') == handle:
                return block
            for obj in block['items']:
                for candidate in [obj] + obj.get('attributes', []) + obj.get('constants', []):
                    if candidate.get('Handle') == handle:
                        return candidate
        return None

    def block_ref(self, attributes=(), constants=()):
        self.blocks.append(dict(Name='ATTR_BLOCK', Handle='B4', IsXRef=FALSE, items=[]))
        obj = self.entity('AcDbBlockReference', 'REF1', '')
        obj.update(Name='ATTR_BLOCK', HasAttributes=TRUE,
                   attributes=list(attributes), constants=list(constants))
        obj['dxf'] = [Pair(0, 'INSERT'), Pair(5, obj['Handle']), Pair(2, obj['Name']), Pair(8, obj['Layer'])]
        return self.add(obj)

    def attribute(self, handle, text):
        obj = self.entity('AcDbAttributeReference', handle, text)
        obj.update(MTextAttribute=TRUE, MTextAttributeContent=text)
        return obj

    def table(self, contents=None):
        obj = self.entity('AcDbTable', 'TABLE1', '')
        obj.update(Rows=1, Columns=1, RegenerateTableSuppressed=FALSE,
                   heights=[10.0], widths=[50.0],
                   cells=[[dict(contents=contents or [dict(text=r'{\fArial;表格}')])]])
        obj['dxf'] = [Pair(0, 'ACAD_TABLE'), Pair(100, 'AcDbTable'), Pair(280, 0),
                      Pair(91, 1), Pair(92, 1), Pair(171, 1)]
        obj['dxf'] += [Pair(301, 'CELL_VALUE') for _ in obj['cells'][0][0]['contents']]
        return self.add(obj)

    def merged(self, obj, row, col, *names):
        bounds = obj['cells'][row][col].get('merge')
        if bounds:
            for name, value in zip(names, bounds):
                self.rt.set(name, value)
            return TRUE
        return FALSE

    @staticmethod
    def content(e, r, c, n):
        try:
            return e['cells'][r][c]['contents'][n]
        except IndexError:
            raise IndexError('Invalid index 8002000B') from None

    def table_put(self, e, r, c, n, text):
        self.content(e, r, c, n)['text'] = text

    def exit(self):
        raise RuntimeError(self.rt.get('*ocs:failuremessage*') or 'quit / exit abort')

    @staticmethod
    def item(collection, index):
        if isinstance(index, str):
            return next(obj for obj in collection['items'] if obj.get('Name') == index)
        return collection['items'][index]

    @staticmethod
    def style(name, font, big, flags=0):
        return {'Name': name, 'font': ['Arial', TRUE, FALSE, 0, 34],
                'dxf': [Pair(-1, name), Pair(0, 'STYLE'), Pair(2, name), Pair(3, font), Pair(4, big), Pair(5, name), Pair(70, flags), Pair(40, 0.0), Pair(41, 0.8), Pair(50, 0.1), Pair(71, 0)]}

    @staticmethod
    def entity(kind, handle, text):
        return dict(ObjectName=kind, Handle=handle, TextString=text, Height=3.5, Width=200.0,
                    Rotation=0.2, Layer='LOCKED', Color=3, StyleName='Standard')

    @staticmethod
    def dxf(obj, code):
        return next(cdr(p) for p in obj['dxf'] if car(p) == code)

    def put_dxf(self, obj, code, value):
        obj['dxf'] = [Pair(code, value) if car(p) == code else p for p in obj['dxf']]

    def tblnext(self, table, restart=None):
        if restart:
            self.enumeration = iter(list(self.styles.values()))
        obj = next(self.enumeration, None)
        return deepcopy(obj['dxf']) if obj else None

    def entmake(self, data):
        name = next(cdr(p) for p in data if car(p) == 2)
        self.styles[name] = {'Name': name, 'font': ['Arial', FALSE, FALSE, 0, 34], 'dxf': data + [Pair(-1, name), Pair(5, name)]}
        return data

    def entmod(self, data):
        name = next(cdr(p) for p in data if car(p) == -1)
        if isinstance(name, dict):
            name['dxf'] = deepcopy([p for p in data if car(p) != -1])
            return data
        self.styles[name]['dxf'] = deepcopy(data)
        return data

    def setfont(self, obj, family, bold, italic, charset, pitch):
        if bold not in (TRUE, FALSE) or italic not in (TRUE, FALSE) or type(bold) is str or type(italic) is str:
            raise TypeError('SetFont requires COM Boolean constants')
        obj['font'] = [family, bold, italic, charset, pitch]

    def getfont(self, obj, *names):
        for name, value in zip(names, obj['font']):
            self.rt.set(name, value)

    def start(self, doc):
        self.undo_objects = self.tracked()
        self.snapshot = deepcopy(self.undo_objects)
        self.events.append('start')

    def put_text(self, obj, value):
        obj['TextString'] = value

    def put_lock(self, obj, value):
        if type(value) is str or value not in (TRUE, FALSE):
            raise TypeError('Lock requires COM Boolean constants')
        obj['Lock'] = value

    def command(self, cmd):
        if cmd != '_.U' or self.snapshot is None:
            raise ValueError('unexpected undo')
        self.events.append('undo')
        for actual, saved in zip(self.undo_objects, self.snapshot):
            actual.clear()
            actual.update(deepcopy(saved))
        return None  # AutoLISP command 正常完成也返回 nil。
