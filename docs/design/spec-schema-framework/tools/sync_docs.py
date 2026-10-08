# -*- coding: utf-8 -*-
"""把 schema 與範例產生的段落寫回設計文件的 GEN 標記區塊（欄位表、參照矩陣、範例結果）。

標記格式：<!-- GEN:<名稱> --> ... <!-- /GEN -->；區塊內容每次重建，區塊外的文字不動。
"""
import json, os, re, collections, sys
import schema_gen as g
import check_rank

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESIGN = os.path.dirname(BASE)
MAIN = os.path.join(DESIGN, 'spec-schema-framework.md')
TYPES = os.path.join(BASE, 'types.md')
WALK = os.path.join(BASE, 'walkthrough.md')
EXW = os.path.join(BASE, 'examples', 'walkthrough')
EXM = os.path.join(BASE, 'examples', 'minimal')

def load(path):
    return json.load(open(path, encoding='utf-8'))

CAN = {doc: load(os.path.join(EXW, 'canonical', f'{doc}.json')) for doc in g.DOC_IDS}
BYID = {it['id']: (doc, it) for doc, d in CAN.items() for it in d['items']}
REPORT = load(os.path.join(EXW, 'gate-report.json'))
REFRX = re.compile(r'^(' + '|'.join(g.PREFIX_INFO) + r')-\d{3,}$')

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

REVERSE = collections.defaultdict(set)
for iid, (doc, it) in BYID.items():
    for r in refs_of(it):
        REVERSE[r].add(iid)

def name(iid):
    it = BYID[iid][1]
    p = iid.split('-')[0]
    if p == 'TRN':
        return it['key'].split(':', 1)[1].replace('*', '新建').replace('>', '→')
    if p == 'FLOW':
        return it['scenarioType']
    if p == 'OBJ':
        return it['objectName']
    if p in ('FLD', 'ENT', 'XF', 'MSG'):
        return it['key']
    if p == 'UI':
        return it.get('title') or it['label']
    for k in ('name', 'title'):
        if isinstance(it.get(k), str):
            return it[k]
    return it['key']

# ---------- generators ----------
def gen_fields(prefix):
    return g.field_table(prefix)

def gen_extra(doc):
    return g.extra_table(doc) or '（本文件沒有額外的外殼欄位。）'

def gen_minimal(prefix):
    doc = g.PREFIX_INFO[prefix][0]
    m = load(os.path.join(EXM, f'{doc}.json'))
    it = next(x for x in m['items'] if x['id'].startswith(prefix + '-'))
    return '```json\n' + json.dumps(it, ensure_ascii=False, indent=2) + '\n```'

def gen_prefix_table():
    rows = ['| 前綴 | 項目 | 定義所在 | 層級 | 自然鍵 |', '|---|---|---|---|---|']
    for p, (doc, rank, nm) in sorted(g.PREFIX_INFO.items(), key=lambda x: (x[1][1], g.DOC_IDS.index(x[1][0]), x[0])):
        rows.append(f'| `{p}` | {nm} | {dict(g.DOC_TYPES)[doc]} | {rank} | `{g.ITEM_TYPES[p]["key_label"]}` |')
    return '\n'.join(rows)

def gen_ref_matrix():
    rows = ['| 項目 | 層級 | 可以參照（跨文件只能指向層級更低者） |', '|---|---|---|']
    extra_refs = {'FLD': [], 'DRV': [], 'STATE': [], 'ROLE': []}
    for p, (doc, rank, nm) in sorted(g.PREFIX_INFO.items(), key=lambda x: (x[1][1], x[0])):
        tg = sorted(g.ref_targets(p), key=lambda t: (g.PREFIX_INFO[t][1], t))
        if p in ('Q', 'DEC'):
            text = '規格本體任一項目' + ('；`Q`' if p == 'DEC' else '')
        elif p == 'DOD':
            text = '規格本體任一項目、`TASK`'
        else:
            text = '、'.join(f'`{t}`' for t in tg) or '（無）'
        rows.append(f'| `{p}` {nm} | {rank} | {text} |')
    return '\n'.join(rows)

def gen_doc_order():
    bad, adj = check_rank.doc_graph()
    order = check_rank.topo(adj)
    lines = ['```mermaid', 'flowchart BT']
    for d in g.DOC_IDS:
        lines.append(f'    D{g.DOC_NUM[d]}["{dict(g.DOC_TYPES)[d]}"]')
    for d in g.DOC_IDS:
        for t in sorted(adj[d], key=g.DOC_IDS.index):
            # 只畫「直接」相依：若 d 經由其他相依可到 t，就省略這條邊
            others = [x for x in adj[d] if x != t]
            def reach(a, b, seen=None):
                seen = seen or set()
                if a == b:
                    return True
                for n in adj[a]:
                    if n not in seen:
                        seen.add(n)
                        if reach(n, b, seen):
                            return True
                return False
            if any(reach(o, t) for o in others):
                continue
            lines.append(f'    D{g.DOC_NUM[d]} --> D{g.DOC_NUM[t]}')
    lines.append('```')
    lines.append('')
    lines.append('箭頭由下游指向它引用的上游（只畫直接相依，可經其他文件到達的邊省略）。腳本驗證：跨文件參照'
                 + ('沒有' if not bad else '有') + '往下游指的情形，文件層級' + ('無循環' if len(order) == len(g.DOC_IDS) else '有循環') + '。')
    lines.append('')
    lines.append('一種合法的產生順序（拓撲排序）：' + ' → '.join(g.DOC_NUM[d] for d in order) + '。彼此沒有相依的文件可以平行產生（§9）。')
    return '\n'.join(lines)

def gen_parse():
    p = REPORT['parse']
    lines = ['| 項目 | 結果 |', '|---|---|',
             f'| flowchart 邊數 | {p["flowchartEdges"]} |',
             f'| stateDiagram-v2 邊數（含 [*] 與 choice） | {p["stateDiagramEdges"]} |',
             f'| 狀態碼 | {"、".join(p["stateCodes"])} |',
             f'| 正規化後的狀態轉移 | {"、".join(p["normalizedTransitions"])}（共 {len(p["normalizedTransitions"])} 條） |',
             f'| 終點狀態 | {"、".join(p["finals"])} |',
             f'| 兩圖狀態碼一致 | {"是" if p["codesEqual"] else "否"} |',
             f'| 兩圖轉移一致 | {"是" if p["transitionsEqual"] else "否"} |']
    for k, v in p['scenarios'].items():
        lines.append(f'| 情境「{k}」 | {"、".join(v)} |')
    return '\n'.join(lines)

def gen_ids():
    lines = ['| ID | 自然鍵 | 名稱 |', '|---|---|---|']
    for p in ['STATE', 'TRN', 'FLOW', 'FR']:
        for it in CAN[g.PREFIX_INFO[p][0]]['items']:
            if it['id'].startswith(p + '-'):
                lines.append(f'| {it["id"]} | `{it["key"]}` | {name(it["id"])} |')
    return '\n'.join(lines)

def gen_gate():
    lines = ['| 文件 | 狀態 | L1 | L2 | L3 | L4 | L5 |', '|---|---|---|---|---|---|---|']
    for doc, r in REPORT['docs'].items():
        gt = r['gate']
        lines.append(f'| {dict(g.DOC_TYPES)[doc]} | {r["status"]} | {gt["L1"]} | {gt["L2"]} | {gt["L3"]} | {gt["L4"]} | {gt["L5"]} |')
    lines.append('')
    if REPORT['violations']:
        lines.append('未通過的檢核：')
        lines.append('')
        for k, msgs in REPORT['violations'].items():
            for m in msgs:
                lines.append(f'- `{k}` {m}')
    else:
        lines.append('沒有未通過的檢核。')
    return '\n'.join(lines)

def gen_fr_tree(frid):
    fr = BYID[frid][1]
    groups = [('ROLE', '角色', [a['role'] for a in fr['actors'] if 'role' in a]),
              ('DRV', '衍生概念', [a['drv'] for a in fr['actors'] if 'drv' in a]),
              ('TRN', '狀態轉移', sorted(fr['realizes'])),
              ('FLOW', '情境', sorted({f['id'] for f in CAN['04-workflow']['items'] if f['id'].startswith('FLOW-')
                                       for s in f['steps'] if s['transition'] in fr['realizes']})),
              ('UI', '畫面元件', sorted(x for x in REVERSE[frid] if x.startswith('UI-'))),
              ('BR', '業務規則', sorted(x for x in REVERSE[frid] if x.startswith('BR-'))),
              ('OP', '操作契約', sorted(x for x in REVERSE[frid] if x.startswith('OP-')))]
    touched = set()
    for _, _, ids in groups:
        for i in ids:
            if i.startswith(('TRN-', 'OP-')):
                touched |= {x for x in refs_of(BYID[i][1]) if x.startswith('FLD-')}
    groups.append(('FLD', '寫入／讀取的欄位（經 TRN、OP）', sorted(touched)))
    groups.append(('TC', '測試案例', sorted(x for x in REVERSE[frid] if x.startswith('TC-'))))
    groups.append(('TASK', '工作項', sorted(x for x in REVERSE[frid] if x.startswith('TASK-'))))
    lines = ['```text', f'{frid} {name(frid)}']
    groups = [x for x in groups if x[2]]
    for i, (p, label, ids) in enumerate(groups):
        branch = '└─' if i == len(groups) - 1 else '├─'
        lines.append(f' {branch} {label}：' + '、'.join(f'{x} {name(x)}' for x in ids))
    lines.append('```')
    return '\n'.join(lines)

def gen_item(iid):
    return '```json\n' + json.dumps(BYID[iid][1], ensure_ascii=False, indent=2) + '\n```'

def gen_rendered(spec):
    doc, iid = spec.split(':', 1)
    text = open(os.path.join(EXW, 'rendered', f'{doc}.md'), encoding='utf-8').read()
    m = re.search(r'^### ' + re.escape(iid) + r'\b.*?(?=^### |^## |\Z)', text, re.S | re.M)
    return '```markdown\n' + m.group(0).rstrip() + '\n```'

def gen_negative():
    rep = load(os.path.join(BASE, 'examples', 'negative-report.json'))
    lines = ['| 破壞方式 | 預期 | 結果 | 檢核訊息 |', '|---|---|---|---|']
    for c in rep['cases']:
        hit = ('標出（警告）' if c['expected'].endswith('S07') else '擋下') if c['caught'] else '漏掉'
        lines.append(f"| {c['case']} | {c['expected']} | {hit} | {c['message'].replace('|', '｜')} |")
    return '\n'.join(lines)

GENERATORS = {
    'prefix-table': gen_prefix_table,
    'ref-matrix': gen_ref_matrix,
    'doc-order': gen_doc_order,
    'parse': gen_parse,
    'ids': gen_ids,
    'gate': gen_gate,
    'negative': gen_negative,
}

BLOCK = re.compile(r'<!-- GEN:([A-Za-z0-9:_-]+) -->\n(?:(?!<!-- GEN:)(?!<!-- /GEN -->).)*?<!-- /GEN -->', re.S)

def fill(text):
    opens = text.count('<!-- GEN:')
    closes = text.count('<!-- /GEN -->')
    if opens != closes or len(BLOCK.findall(text)) != opens:
        raise SystemExit(f'GEN 標記不成對：開 {opens}、關 {closes}')
    def rep(m):
        key = m.group(1)
        if key.startswith('fields:'):
            body = gen_fields(key.split(':', 1)[1])
        elif key.startswith('extra:'):
            body = gen_extra(key.split(':', 1)[1])
        elif key.startswith('minimal:'):
            body = gen_minimal(key.split(':', 1)[1])
        elif key.startswith('fr-tree:'):
            body = gen_fr_tree(key.split(':', 1)[1])
        elif key.startswith('item:'):
            body = gen_item(key.split(':', 1)[1])
        elif key.startswith('rendered:'):
            body = gen_rendered(key.split(':', 1)[1])
        else:
            body = GENERATORS[key]()
        return f'<!-- GEN:{key} -->\n{body}\n<!-- /GEN -->'
    return BLOCK.sub(rep, text)

def main(check_only=False):
    stale = []
    for path in (MAIN, TYPES, WALK):
        if not os.path.exists(path):
            continue
        old = open(path, encoding='utf-8').read()
        new = fill(old)
        if new != old:
            stale.append(os.path.relpath(path, DESIGN))
            if not check_only:
                with open(path, 'w', encoding='utf-8', newline='\n') as fh:
                    fh.write(new)
    return stale

if __name__ == '__main__':
    check = '--check' in sys.argv
    stale = main(check_only=check)
    if check and stale:
        print('generated blocks out of date:', ', '.join(stale))
        sys.exit(1)
    print('synced' if not check else 'up to date', stale)
