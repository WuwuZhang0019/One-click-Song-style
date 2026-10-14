"""日期：2026-10-14。执行项目 LISP 源码的有限测试解释器，不能替代原生 CAD。

采用 AutoLISP 动态作用域和真值语义（0 与空串为真）。CAD 接口由测试注入；
未实现的函数直接失败，禁止默认为成功。
"""
from __future__ import annotations

import math
import operator
import re
from functools import reduce
from check_lisp import lex


class Symbol(str):
    pass


class Pair:
    def __init__(self, car, cdr):
        self.car, self.cdr = car, cdr

    def __eq__(self, other):
        return isinstance(other, Pair) and self.car == other.car and self.cdr == other.cdr


def truth(x):
    return x is not None and x is not False and x != []


def car(x):
    return x.car if isinstance(x, Pair) else (x[0] if x else None)


def cdr(x):
    return x.cdr if isinstance(x, Pair) else (x[1:] or None if x else None)


def read(text):
    tokens = iter(lex(text))

    def node(t):
        if t[0] == '(':
            out = []
            for t in tokens:
                if t[0] == ')':
                    return out
                out.append(node(t))
            raise ValueError('unclosed list')
        if t[0] == 'str':
            return re.sub(r'\\(.)', lambda m: {'n': '\n', 'r': '\r', 't': '\t'}.get(m[1], m[1]), t[1])
        value = t[1]
        if value == "'":
            return [Symbol('quote'), node(next(tokens))]
        if value.startswith("'"):
            return [Symbol('quote'), Symbol(value[1:].lower())]
        try:
            return float(value) if '.' in value or 'e' in value.lower() else int(value)
        except ValueError:
            return Symbol(value.lower())

    return [node(t) for t in tokens]


class Runtime:
    def __init__(self, text):
        self.forms = read(text)
        self.defs = {str(f[1]): f for f in self.forms if isinstance(f, list) and f and f[0] == 'defun'}
        self.scopes = [{'nil': None, 't': True, ':vlax-true': Symbol(':vlax-true'), ':vlax-false': Symbol(':vlax-false')}]
        self.output = []
        self.steps = 0
        self.native = {
            '+': lambda *a: sum(a), '-': lambda a, *b: a - sum(b) if b else -a,
            '*': lambda *a: math.prod(a), '/': lambda a, b: a // b if isinstance(a, int) and isinstance(b, int) else a / b,
            '1+': lambda a: a + 1, '1-': lambda a: a - 1,
            'not': lambda a: not truth(a), 'null': lambda a: not truth(a),
            'list': lambda *a: list(a) or None, 'car': car, 'cdr': cdr,
            'cadr': lambda a: car(cdr(a)), 'caddr': lambda a: car(cdr(cdr(a))),
            'cons': lambda a, b: [a] + (b or []) if b is None or isinstance(b, list) else Pair(a, b),
            'append': lambda *a: sum((x or [] for x in a), []) or None,
            'length': lambda a: len(a or []), 'nth': lambda i, a: a[i] if a and i < len(a) else None,
            'reverse': lambda a: list(reversed(a or [])),
            'assoc': lambda k, a: next((x for x in a or [] if car(x) == k), None),
            'member': lambda x, a: a[a.index(x):] if a and x in a else None,
            'atom': lambda a: not isinstance(a, (list, Pair)) or a == [],
            'listp': lambda a: a is None or isinstance(a, (list, Pair)),
            'numberp': lambda a: type(a) in (int, float),
            'type': lambda a: None if a is None else Symbol('str' if type(a) is str else 'list' if isinstance(a, (list, Pair)) else 'sym' if isinstance(a, Symbol) else 'int'),
            'strlen': len, 'strcat': lambda *a: ''.join(a),
            'substr': lambda s, i, n=None: s[i-1:] if n is None else s[i-1:i-1+n],
            'strcase': lambda s, lower=None: s.lower() if truth(lower) else s.upper(),
            'itoa': str, 'rtos': lambda n, *a: str(n), 'fix': int,
            'vl-position': lambda x, a: a.index(x) if a and x in a else None,
            'vl-symbol-name': self.symbol_name, 'read': lambda s: read(s)[0],
            'vl-load-com': lambda: None,
            'vl-catch-all-error-p': lambda a: isinstance(a, Exception),
            'vl-catch-all-error-message': self.error_message,
            'vl-catch-all-apply': self.catch,
            'princ': lambda *a: self.output.extend(a) or None,
            'logand': lambda *a: reduce(operator.and_, a), 'logior': lambda *a: reduce(operator.or_, a),
            'lsh': lambda n, b: n << b if b >= 0 else n >> -b,
            'equal': lambda a, b, fuzz=None: abs(a-b) <= fuzz if fuzz is not None and type(a) in (int, float) and type(b) in (int, float) else a == b,
            'boundp': lambda s: any(s in frame for frame in self.scopes),
        }
        for name, op in [('=', operator.eq), ('/=', operator.ne), ('<', operator.lt), ('>', operator.gt), ('<=', operator.le), ('>=', operator.ge)]:
            self.native[name] = lambda *a, op=op: all(op(x, y) for x, y in zip(a, a[1:]))

    @staticmethod
    def symbol_name(value):
        if not isinstance(value, Symbol):
            raise TypeError('bad argument type: symbolp ' + ('nil' if value is None else repr(value)))
        return str(value).upper()

    @staticmethod
    def error_message(value):
        if not isinstance(value, Exception):
            raise TypeError('expected catch-all error')
        return str(value)

    def catch(self, name, args):
        try:
            return self.call(str(name), args or [])
        except Exception as error:
            return error

    def get(self, key):
        return next((s[key] for s in reversed(self.scopes) if key in s), None)

    def set(self, key, value):
        for scope in reversed(self.scopes):
            if key in scope:
                scope[key] = value
                return value
        self.scopes[0][key] = value
        return value

    def seq(self, forms):
        result = None
        for form in forms:
            result = self.eval(form)
        return result

    def load(self):
        self.seq([f for f in self.forms if not (isinstance(f, list) and f and f[0] == 'defun')])

    def call(self, name, args):
        name = name.lower()
        if name in self.native:
            return self.native[name](*args)
        if name not in self.defs:
            raise ValueError(f'no function definition: {name}')
        f = self.defs[name]
        params = f[2]
        slash = params.index('/') if '/' in params else len(params)
        if len(args) != slash:
            raise TypeError(f'{name}: expected {slash} arguments, got {len(args)}')
        self.scopes.append(dict(zip(params[:slash], args)) | {p: None for p in params[slash+1:]})
        try:
            return self.seq(f[3:])
        finally:
            self.scopes.pop()

    def eval(self, form):
        self.steps += 1
        if self.steps > 2000000:
            raise RuntimeError('LISP evaluation step limit')
        if isinstance(form, Symbol):
            return self.get(form)
        if not isinstance(form, list):
            return form
        if not form:
            return None
        head, *args = form
        if head == 'quote':
            return args[0]
        if head == 'setq':
            for key, value in zip(args[::2], args[1::2]):
                result = self.set(key, self.eval(value))
            return result
        if head == 'progn':
            return self.seq(args)
        if head == 'if':
            if len(args) not in (2, 3):
                raise TypeError(f'if: expected 2 or 3 arguments, got {len(args)}')
            return self.eval(args[1]) if truth(self.eval(args[0])) else self.eval(args[2]) if len(args) == 3 else None
        if head == 'cond':
            for clause in args:
                test = self.eval(clause[0])
                if truth(test):
                    return self.seq(clause[1:]) if len(clause) > 1 else test
            return None
        if head == 'and':
            return all(truth(self.eval(a)) for a in args)
        if head == 'or':
            return any(truth(self.eval(a)) for a in args)
        if head == 'while':
            result = None
            while truth(self.eval(args[0])):
                result = self.seq(args[1:])
            return result
        if head == 'foreach':
            result = None
            for item in self.eval(args[1]) or []:
                self.set(args[0], item)
                result = self.seq(args[2:])
            return result
        return self.call(str(head), [self.eval(a) for a in args])


def arity_errors(text):
    rt = Runtime(text)
    errors = []

    def walk(f, owner):
        if not isinstance(f, list) or not f:
            return
        head = f[0]
        if head == 'quote':
            return
        if head == 'defun':
            for body in f[3:]:
                walk(body, str(f[1]))
            return
        if isinstance(head, Symbol) and head in rt.defs:
            params = rt.defs[head][2]
            n = params.index('/') if '/' in params else len(params)
            if len(f)-1 != n:
                errors.append(f'{owner}: {head} expects {n}, got {len(f)-1}')
        if head == 'if' and len(f) not in (3, 4):
            errors.append(f'{owner}: if expects 2 or 3, got {len(f)-1}')
        if head == 'setq' and (len(f) < 3 or len(f) % 2 == 0):
            errors.append(f'{owner}: invalid setq')
        for item in f:
            walk(item, owner)

    for f in rt.forms:
        walk(f, 'top-level')
    return errors
