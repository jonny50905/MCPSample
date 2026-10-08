# -*- coding: utf-8 -*-
"""壞範例：對貫穿範例做刻意破壞，確認每一種都被對應的檢核擋下（缺欄位、模糊條件、填充字、未標示推論、
推測用語、缺引用、往下游參照、不建置欄位出現在正文、圖外轉移寫進 04）。"""
import copy, glob, json, os, re, sys
from jsonschema import Draft202012Validator
from jsonschema.exceptions import best_match
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012
import schema_gen as g

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXW = os.path.join(BASE, 'examples', 'walkthrough')
SCHEMAS = {}
for f in glob.glob(os.path.join(BASE, 'schemas', '*.json')):
    s = json.load(open(f, encoding='utf-8'))
    SCHEMAS[s['$id']] = s
REG = Registry().with_resources([(k, Resource.from_contents(v, default_specification=DRAFT202012)) for k, v in SCHEMAS.items()])
DOCS0 = {d: json.load(open(os.path.join(EXW, 'canonical', f'{d}.json'), encoding='utf-8')) for d in g.DOC_IDS}
PARSE = json.load(open(os.path.join(EXW, 'gate-report.json'), encoding='utf-8'))['parse']
REFRX = re.compile(r'^(' + '|'.join(g.PREFIX_INFO) + r')-\d{3,}$')
HEDGE = re.compile(r'推測|猜測|應該是|大概|似乎|或許|假設|估計')

def refs_of(o, top=True):
    out = []
    if isinstance(o, dict):
        for k, v in o.items():
            if top and k == 'id':
                continue
            out += refs_of(v, False)
    elif isinstance(o, list):
        for v in o:
            out += refs_of(v, False)
    elif isinstance(o, str) and REFRX.match(o):
        out.append(o)
    return out

def strings(o):
    if isinstance(o, dict):
        for v in o.values():
            yield from strings(v)
    elif isinstance(o, list):
        for v in o:
            yield from strings(v)
    elif isinstance(o, str):
        yield o

def check(docs):
    """回傳 [(層, 代碼, 訊息)]。L1＝schema＋推測用語警告；L2＝R01／R03／R04；L3＝C01。"""
    out = []
    for doc, d in docs.items():
        env = dict(d, items=[])
        for e in Draft202012Validator(SCHEMAS[g.URN + doc], registry=REG).iter_errors(env):
            out.append(('L1', 'S01', f'{doc} 外殼：{e.message[:100]}'))
        for it in d['items']:
            p = it['id'].split('-')[0]
            v = Draft202012Validator({'$ref': f'{g.URN}{doc}#/$defs/{p}'}, registry=REG)
            errs = list(v.iter_errors(it))
            if errs:
                # 子 schema 失敗時 unevaluatedProperties 會連帶報錯；有其他錯誤時以其他錯誤為準
                real = [x for x in errs if x.validator != 'unevaluatedProperties'] or errs
                e = best_match(real)
                where = '.'.join(str(x) for x in e.absolute_path) or '（項目）'
                msg = '命中禁用的填充字' if e.validator == 'not' else e.message[:100]
                out.append(('L1', 'S01', f'{it["id"]} {where}：{msg}'))
    byid = {it['id']: (doc, it) for doc, d in docs.items() for it in d['items']}
    xf = set()
    for it in docs['07-database']['items']:
        if it['id'].startswith('XF-'):
            xf |= set(it['fields'])
    for iid, (doc, it) in byid.items():
        p = iid.split('-')[0]
        rank = g.PREFIX_INFO[p][1]
        for r in refs_of(it):
            if r not in byid:
                out.append(('L2', 'R01', f'{iid} 參照不存在的 {r}'))
                continue
            if byid[r][0] != doc and not g.PREFIX_INFO[r.split('-')[0]][1] < rank:
                out.append(('L2', 'R03', f'{iid} 往下游參照 {r}'))
        if rank <= 9 and doc != '07-database':
            for s in strings(it):
                for f in xf:
                    if re.search(r'(?<![A-Z0-9_])' + f + r'(?![A-Z0-9_])', s):
                        out.append(('L2', 'R04', f'{iid} 正文寫到不建置欄位 {f}'))
        if rank <= 9 and it.get('certainty') == 'CONFIRMED':
            for s in strings(it):
                m = HEDGE.search(s)
                if m:
                    out.append(('L1', 'S07', f'{iid} CONFIRMED 項目出現推測用語「{m.group(0)}」（警告，交覆核）'))
    states = {it['id']: it for it in docs['04-workflow']['items'] if it['id'].startswith('STATE-')}
    pairs = set()
    for it in docs['04-workflow']['items']:
        if it['id'].startswith('TRN-'):
            a = '*' if it['from'] == 'INITIAL' else states[it['from']]['code'] if it['from'] in states else '?'
            b = states[it['to']]['code'] if it['to'] in states else '?'
            pairs.add(f'{a}>{b}')
    extra = sorted(pairs - set(PARSE['normalizedTransitions']))
    if extra:
        out.append(('L3', 'C01', f'04 有狀態圖沒有的轉移 {extra}'))
    return out

def item(docs, iid):
    for d in docs.values():
        for it in d['items']:
            if it['id'] == iid:
                return it
    raise KeyError(iid)

CASES = []
def case(name, expect, mutate):
    CASES.append((name, expect, mutate))

case('缺欄位：TRN-008 刪掉 guard', ('L1', 'S01'), lambda D: item(D, 'TRN-008').pop('guard'))
case('模糊條件：BR-006 的條件寫成「需要長官審核」', ('L1', 'S01'),
     lambda D: item(D, 'BR-006').__setitem__('condition', '需要長官審核'))
case('填充字：FR-004 的說明寫「待確認」', ('L1', 'S01'),
     lambda D: item(D, 'FR-004').__setitem__('description', '待確認'))
case('未標示推論：DRV-002 改成 INFERRED 卻沒寫推論鏈', ('L1', 'S01'),
     lambda D: item(D, 'DRV-002').__setitem__('certainty', 'INFERRED'))
case('推測寫成事實：OP-001 的併發行為寫「應該是後存檔者覆蓋」', ('L1', 'S07'),
     lambda D: item(D, 'OP-001')['transaction']['concurrency'].__setitem__('legacyBehavior', '應該是後存檔者覆蓋先存檔者'))
case('缺引用：OP-004 的檢核清單指向不存在的 BR-099', ('L2', 'R01'),
     lambda D: item(D, 'OP-004')['validations'].append('BR-099'))
case('往下游參照：FLD-010 宣稱推導自 TC-001', ('L2', 'R03'),
     lambda D: (item(D, 'FLD-010').__setitem__('basis', 'DERIVED'), item(D, 'FLD-010').__setitem__('derivedFrom', ['TC-001'])))
case('不建置欄位寫進正文：BR-003 的邊界提到 OLD_REF_NO', ('L2', 'R04'),
     lambda D: item(D, 'BR-003').__setitem__('boundaries', '0 拒絕；OLD_REF_NO 為空白時略過。'))

def add_offdiagram(D):
    src = copy.deepcopy(item(D, 'TRN-010'))
    src['id'] = 'TRN-011'
    src['key'] = 'REQ_STATUS:030>010'
    src['from'] = 'STATE-005'
    src['to'] = 'STATE-001'
    src['writes'] = [{'field': 'FLD-017', 'value': {'const': '010', 'type': 'CHAR'}}]
    D['04-workflow']['items'].append(src)
case('圖外轉移寫進 04：新增 030→010', ('L3', 'C01'), add_offdiagram)

def main():
    base = check(DOCS0)
    base_codes = {(l, c) for l, c, _ in base}
    results, failed = [], []
    for name, expect, mutate in CASES:
        docs = copy.deepcopy(DOCS0)
        mutate(docs)
        found = [x for x in check(docs) if (x[0], x[1]) == expect and x not in base]
        ok = bool(found)
        results.append({'case': name, 'expected': f'{expect[0]} {expect[1]}', 'caught': ok,
                        'message': found[0][2] if found else ''})
        if not ok:
            failed.append(name)
    report = {'baselineFindings': [f'{l} {c} {m}' for l, c, m in base], 'cases': results}
    with open(os.path.join(BASE, 'examples', 'negative-report.json'), 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    for r in results:
        print('OK ' if r['caught'] else 'MISS', r['expected'], r['case'], '→', r['message'])
    if base:
        print('baseline:', report['baselineFindings'])
    if failed or base:
        sys.exit(1)

if __name__ == '__main__':
    main()
