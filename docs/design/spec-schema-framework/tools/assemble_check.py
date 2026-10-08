# -*- coding: utf-8 -*-
"""組成 15 份 canonical 文件，計算 17／18，執行 schema 驗證、L2 參照與 L3 覆蓋檢核、兩張圖比對，並產生最小合法文件。"""
import json, os, re, hashlib, copy, collections, glob
from jsonschema import Draft202012Validator
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012
import schema_gen as g
import example_gen as E
import example_inputs as X

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXW = ROOT + '/examples/walkthrough'
EXM = ROOT + '/examples/minimal'
COMPONENTS = ['TW_DEMO_APV', 'TW_DEMO_REQ']

def sha(s):
    return hashlib.sha256(s.encode('utf-8')).hexdigest()

def dump(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(json.dumps(obj, ensure_ascii=False, indent=2) + '\n')

def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text)

# ---------------- build items ----------------
E.build()
DEC_MD = E.add_dec()
ITEMS = E.ITEMS
BYID = {}
for p, lst in ITEMS.items():
    for it in lst:
        BYID[it['id']] = (p, it)
KEY2ID = {(p, it['key']): it['id'] for p, lst in ITEMS.items() for it in lst}
def I(p, key):
    return KEY2ID[(p, key)]

REFRX = re.compile(r'^(' + '|'.join(g.PREFIX_INFO) + r')-\d{3,}$')
def refs_of(it):
    out = []
    def walk(o, top=False):
        if isinstance(o, dict):
            for k, v in o.items():
                if top and k == 'id':
                    continue
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
        elif isinstance(o, str) and REFRX.match(o):
            out.append(o)
    walk(it, top=True)
    return out

def strings_of(o):
    if isinstance(o, dict):
        for v in o.values():
            yield from strings_of(v)
    elif isinstance(o, list):
        for v in o:
            yield from strings_of(v)
    elif isinstance(o, str):
        yield o

# ---------------- 17 / 18 (computed) ----------------
TRNS = {it['id']: it for it in ITEMS['TRN']}
FRS = ITEMS['FR']
def trn_from(t):
    return t['from']
# BFS over states from INITIAL
level = {'INITIAL': 0}
first_reach = {}
frontier = ['INITIAL']
trn_sorted = sorted(TRNS.values(), key=lambda t: t['key'])
while frontier:
    nxt = []
    for s in frontier:
        for t in trn_sorted:
            if t['from'] == s and t['to'] not in level:
                level[t['to']] = level[s] + 1
                first_reach[t['to']] = t['id']
                nxt.append(t['to'])
    frontier = nxt
def trn_level(tid):
    return level[TRNS[tid]['from']]
fr_of_trn = collections.defaultdict(list)
for fr in FRS:
    for t in fr['realizes']:
        fr_of_trn[t].append(fr['id'])

def members_for(fr_id):
    fr = BYID[fr_id][1]
    m = {'transitions': list(fr['realizes']),
         'controls': [u['id'] for u in ITEMS['UI'] if fr_id in u['usedBy'] and u['uiKind'] == 'CONTROL'],
         'rules': [b['id'] for b in ITEMS['BR'] if fr_id in b['appliesTo']],
         'operations': [o['id'] for o in ITEMS['OP'] if o['fr'] == fr_id],
         'tests': [t['id'] for t in ITEMS['TC'] if t['fr'] == fr_id]}
    touched = set()
    for k in ['transitions', 'controls', 'rules', 'operations']:
        for iid in m[k]:
            touched |= set(refs_of(BYID[iid][1]))
    m['fields'] = sorted(x for x in touched if x.startswith('FLD-'))
    m['derivations'] = sorted(x for x in touched if x.startswith('DRV-'))
    m['roles'] = sorted(x for x in touched if x.startswith('ROLE-'))
    return {k: m[k] for k in ['fields', 'derivations', 'roles', 'transitions', 'controls', 'rules', 'operations', 'tests']}

tasks = []
found = {'key': 'FOUNDATION:DATA_AND_SECURITY', 'taskKind': 'FOUNDATION',
         'fr': {'na': '基礎工作，不對應單一功能'}, 'name': '資料結構、衍生概念與角色權限',
         'order': 1, 'dependsOn': [],
         'members': {'entities': [x['id'] for x in ITEMS['ENT']], 'fields': [x['id'] for x in ITEMS['FLD']],
                     'derivations': [x['id'] for x in ITEMS['DRV']], 'roles': [x['id'] for x in ITEMS['ROLE']]},
         'deliverables': ['DATA_STRUCTURE', 'SECURITY']}
tasks.append(found)
slices = []
for fr in FRS:
    lv = min(trn_level(t) for t in fr['realizes'])
    slices.append((lv, fr['key'], fr))
slices.sort(key=lambda x: (x[0], x[1]))
for n, (lv, _, fr) in enumerate(slices):
    tasks.append({'key': 'SLICE:' + fr['key'], 'taskKind': 'SLICE', 'fr': fr['id'], 'name': fr['name'],
                  'order': n + 2, 'dependsOn': ['@FOUNDATION'], 'members': members_for(fr['id']),
                  'deliverables': ['OPERATIONS', 'SCREENS', 'RULES', 'TESTS'], '_fr': fr})
# ids sorted by key
tasks_sorted = sorted(tasks, key=lambda x: x['key'])
for i, t in enumerate(tasks_sorted):
    t['id'] = f'TASK-{i + 1:03d}'
task_by_fr = {t['_fr']['id']: t['id'] for t in tasks if t['taskKind'] == 'SLICE'}
found_id = found['id']
for t in tasks:
    if t['taskKind'] != 'SLICE':
        continue
    fr = t.pop('_fr')
    deps = [found_id]
    first = sorted(fr['realizes'], key=lambda x: (trn_level(x), TRNS[x]['key']))[0]
    src = TRNS[first]['from']
    if src != 'INITIAL':
        pred = first_reach[src]
        for fid in fr_of_trn[pred]:
            if fid != fr['id']:
                deps.append(task_by_fr[fid])
    t['dependsOn'] = deps
TASK_ITEMS = []
for t in tasks_sorted:
    it = {'id': t['id'], 'key': t['key'], 'lifecycle': 'ACTIVE', 'basis': 'COMPUTED', 'certainty': 'CONFIRMED',
          'evidence': []}
    for k in ['taskKind', 'fr', 'name', 'order', 'dependsOn', 'members', 'deliverables']:
        it[k] = t[k]
    TASK_ITEMS.append(it)
ITEMS['TASK'] = TASK_ITEMS
for it in TASK_ITEMS:
    BYID[it['id']] = ('TASK', it)

def msgs_for(member_ids):
    out = set()
    for iid in member_ids:
        for x in refs_of(BYID[iid][1]):
            if x.startswith('MSG-'):
                out.add(x)
    return sorted(out)

DOD_ITEMS = [{
    'key': 'GLOBAL:BASELINE', 'scope': 'GLOBAL', 'basis': 'TEMPLATE',
    'criteria': [
        {'kind': 'STORED_VALUES_PRESERVED', 'statement': '狀態碼與選項儲存值與 07 的值域完全相同。',
         'refs': [I('FLD', 'TW_DEMO_REQHDR.REQ_STATUS')], 'evidenceRequired': 'TEST_REPORT'},
        {'kind': 'NO_EXCLUDED_FIELDS', 'statement': '07「不建置的原生欄位」沒有出現在資料結構、畫面與規則。',
         'refs': [I('XF', 'TW_DEMO_REQHDR')], 'evidenceRequired': 'CODE_REFERENCE'},
        {'kind': 'BLANK_SEMANTICS_PRESERVED', 'statement': '空白、0 與 NULL 的比較照共同定義實作。', 'refs': [],
         'evidenceRequired': 'TEST_REPORT'},
        {'kind': 'TRACE_IDS_RECORDED', 'statement': '程式與測試都標註實作的 ID。', 'refs': [],
         'evidenceRequired': 'CODE_REFERENCE'},
        {'kind': 'OPEN_QUESTIONS_CLOSED', 'statement': '影響本工作項目的 BLOCKING 問題都已在 19 有決策。', 'refs': [],
         'evidenceRequired': 'REVIEW_RECORD'},
    ]}]
for t in TASK_ITEMS:
    m = t['members']
    crit = []
    if t['taskKind'] == 'FOUNDATION':
        crit.append({'kind': 'STORED_VALUES_PRESERVED', 'statement': '實體、欄位、值域與衍生概念照 07 建立。',
                     'refs': m['entities'] + m['derivations'], 'evidenceRequired': 'CODE_REFERENCE'})
        crit.append({'kind': 'RULES_IMPLEMENTED', 'statement': '角色與資料範圍照 03 建立。',
                     'refs': [x['id'] for x in ITEMS['PERM']], 'evidenceRequired': 'TEST_REPORT'})
    else:
        if m['tests']:
            crit.append({'kind': 'TESTS_PASS', 'statement': '本工作的測試案例全數通過。', 'refs': m['tests'],
                         'evidenceRequired': 'TEST_REPORT'})
        crit.append({'kind': 'RULES_IMPLEMENTED', 'statement': '本工作的轉移、規則與操作都已實作。',
                     'refs': m['transitions'] + m['rules'] + m['operations'], 'evidenceRequired': 'CODE_REFERENCE'})
        ms = msgs_for(m['rules'] + m['operations'])
        if ms:
            crit.append({'kind': 'MESSAGES_PRESERVED', 'statement': '訊息原文與觸發條件與 09 一致。', 'refs': ms,
                         'evidenceRequired': 'TEST_REPORT'})
    DOD_ITEMS.append({'key': 'TASK:' + t['key'], 'scope': 'TASK', 'task': t['id'], 'basis': 'COMPUTED', 'criteria': crit})
DOD_ITEMS.sort(key=lambda x: x['key'])
final_dod = []
for i, d in enumerate(DOD_ITEMS):
    it = {'id': f'DOD-{i + 1:03d}', 'key': d['key'], 'lifecycle': 'ACTIVE', 'basis': d['basis'], 'certainty': 'CONFIRMED',
          'evidence': [], 'scope': d['scope']}
    if 'task' in d:
        it['task'] = d['task']
    it['criteria'] = d['criteria']
    final_dod.append(it)
ITEMS['DOD'] = final_dod
for it in final_dod:
    BYID[it['id']] = ('DOD', it)

# ---------------- synthetic metadata inventories (denominators) ----------------
PAGE_FIELDS = {
    'TW_DEMO_REQ.TW_DEMO_REQPG': ['TW_DEMO_REQHDR.AMOUNT', 'TW_DEMO_REQHDR.REASON', 'TW_DEMO_REQHDR.REQ_STATUS',
                                  'TW_DEMO_REQWRK.SUBMIT_PB', 'TW_DEMO_REQWRK.WITHDRAW_PB'],
    'TW_DEMO_APV.TW_DEMO_APVPG': ['TW_DEMO_REQHDR.AMOUNT', 'TW_DEMO_REQHDR.REASON', 'TW_DEMO_REQHDR.COMMENTS',
                                  'TW_DEMO_REQWRK.APPROVE_PB', 'TW_DEMO_REQWRK.RETURN_PB'],
}
RECORD_FIELDS = {  # CORE SQL_TABLE records: full field list from metadata
    'TW_DEMO_REQHDR': ['REQ_ID', 'REQUESTER_EMPLID', 'REQ_STATUS', 'AMOUNT', 'REASON', 'COMMENTS', 'SUBMIT_DT',
                       'APPROVER_EMPLID', 'APPROVE_DT', 'OLD_REF_NO', 'PRIORITY_CD'],
}

# ---------------- Mermaid parsing (prototype for C01) ----------------
CODE_RX = re.compile(r'(?<![0-9A-Za-z])(\d{3})(?![0-9A-Za-z])')

def mermaid_blocks(md):
    blocks, cur, inb = [], [], False
    for line in md.split('\n'):
        if line.strip().startswith('```mermaid'):
            inb, cur = True, []
            continue
        if inb and line.strip().startswith('```'):
            blocks.append('\n'.join(cur))
            inb = False
            continue
        if inb:
            cur.append(line)
    return blocks

NODE_RX = re.compile(r'([A-Za-z0-9_]+)\s*(\(\((.*?)\)\)|\[\"(.*?)\"\]|\[(.*?)\]|\{(.*?)\}|\((.*?)\))?')
def parse_flowchart(src):
    nodes, edges = {}, []
    for raw in src.split('\n')[1:]:
        line = raw.strip()
        if not line or line.startswith('%%'):
            continue
        m = re.match(r'^(.*?)\s*-->\|(.*?)\|\s*(.*)$', line)
        if not m:
            raise ValueError('unsupported flowchart line: ' + line)
        a, label, b = m.group(1), m.group(2), m.group(3)
        def node(tok):
            nm = NODE_RX.fullmatch(tok.strip())
            if not nm:
                raise ValueError('bad node ' + tok)
            nid = nm.group(1)
            shape = None
            text = None
            if nm.group(3) is not None:
                shape, text = 'circle', nm.group(3)
            elif nm.group(4) is not None:
                shape, text = 'box', nm.group(4)
            elif nm.group(5) is not None:
                shape, text = 'box', nm.group(5)
            elif nm.group(6) is not None:
                shape, text = 'rhombus', nm.group(6)
            elif nm.group(7) is not None:
                shape, text = 'round', nm.group(7)
            if text is not None:
                nodes[nid] = (shape, text)
            nodes.setdefault(nid, ('box', nid))
            return nid
        edges.append((node(a), node(b), label.strip()))
    kinds = {}
    indeg = collections.Counter(b for _, b, _ in edges)
    for nid, (shape, text) in nodes.items():
        cm = CODE_RX.search(text)
        if cm:
            kinds[nid] = ('STATE', cm.group(1))
        elif shape == 'rhombus':
            kinds[nid] = ('PSEUDO', text)
        elif indeg[nid] == 0:
            kinds[nid] = ('INITIAL', None)
        else:
            raise ValueError('flowchart node without status code: ' + nid)
    return kinds, edges

def parse_state_diagram(src):
    alias, pseudo, edges = {}, set(), []
    for raw in src.split('\n')[1:]:
        line = raw.strip()
        if not line or line.startswith('%%') or line.startswith('note ') or line.startswith('direction '):
            continue
        m = re.match(r'^state\s+"(.*?)"\s+as\s+([A-Za-z0-9_]+)$', line)
        if m:
            alias[m.group(2)] = m.group(1)
            continue
        m = re.match(r'^state\s+([A-Za-z0-9_]+)\s+<<(choice|fork|join)>>$', line)
        if m:
            pseudo.add(m.group(1))
            continue
        m = re.match(r'^(\[\*\]|[A-Za-z0-9_]+)\s*-->\s*(\[\*\]|[A-Za-z0-9_]+)(\s*:.*)?$', line)
        if m:
            edges.append((m.group(1), m.group(2)))
            continue
        raise ValueError('unsupported stateDiagram line: ' + line)
    kinds = {}
    for a, b in edges:
        for n in (a, b):
            if n in kinds:
                continue
            if n == '[*]':
                kinds[n] = ('STAR', None)
            elif n in pseudo:
                kinds[n] = ('PSEUDO', n)
            else:
                cm = CODE_RX.search(alias.get(n, n))
                if not cm:
                    raise ValueError('state without status code: ' + n)
                kinds[n] = ('STATE', cm.group(1))
    return kinds, edges

def collapse(kinds, edges, labeled):
    """Return set of (from, to, scenario) at state level. from may be '*'; edges into [*] mark finals."""
    out, finals = set(), set()
    succ = collections.defaultdict(list)
    for e in edges:
        succ[e[0]].append(e)
    def walk(start_code, node, first_label, via):
        for e in succ[node]:
            tgt = e[1]
            lab = e[2] if labeled else None
            k = kinds[tgt]
            if k[0] == 'PSEUDO':
                walk(start_code, tgt, first_label or lab, via + [k[1]])
            elif k[0] == 'STATE':
                out.add((start_code, k[1], lab or first_label, tuple(via)))
            elif k[0] == 'STAR':
                finals.add(start_code)
    for n, k in kinds.items():
        if k[0] == 'STATE':
            walk(k[1], n, None, [])
        elif k[0] in ('INITIAL',):
            walk('*', n, None, [])
        elif k[0] == 'STAR':
            # [*] as source = initial
            for e in succ[n]:
                tk = kinds[e[1]]
                if tk[0] == 'STATE':
                    out.add(('*', tk[1], None, ()))
    return out, finals

blocks = mermaid_blocks(X.STATUS_DOC)
fc_kinds, fc_edges = parse_flowchart(blocks[0])
sd_kinds, sd_edges = parse_state_diagram(blocks[1])
fc_set, _ = collapse(fc_kinds, fc_edges, True)
sd_set, sd_finals = collapse(sd_kinds, sd_edges, False)
FC_PAIRS = {(a, b) for a, b, _, _ in fc_set}
SD_PAIRS = {(a, b) for a, b, _, _ in sd_set}
FC_CODES = {k[1] for k in fc_kinds.values() if k[0] == 'STATE'}
SD_CODES = {k[1] for k in sd_kinds.values() if k[0] == 'STATE'}
SCENARIOS = collections.defaultdict(set)
for a, b, lab, _ in fc_set:
    SCENARIOS[lab].add((a, b))
VIA = {(a, b): via for a, b, _, via in sd_set}
PARSE = {'flowchartEdges': len(fc_edges), 'stateDiagramEdges': len(sd_edges), 'stateCodes': sorted(SD_CODES),
         'normalizedTransitions': sorted(f'{a}>{b}' for a, b in SD_PAIRS), 'finals': sorted(sd_finals),
         'scenarios': {k: sorted(f'{a}>{b}' for a, b in SCENARIOS[k]) for k in sorted(SCENARIOS)},
         'codesEqual': FC_CODES == SD_CODES, 'transitionsEqual': FC_PAIRS == SD_PAIRS,
         'onlyInFlowchart': sorted(f'{a}>{b}' for a, b in FC_PAIRS - SD_PAIRS),
         'onlyInStateDiagram': sorted(f'{a}>{b}' for a, b in SD_PAIRS - FC_PAIRS)}

# ---------------- checks ----------------
VIOL = collections.defaultdict(list)   # (docType, layer) -> [str]
def v(doc, layer, code, msg):
    VIOL[(doc, layer)].append(f'{code} {msg}')
def doc_of(iid):
    return g.PREFIX_INFO[iid.split('-')[0]][0]
def rank_of(iid):
    return g.PREFIX_INFO[iid.split('-')[0]][1]

ALLIDS = set(BYID)
for iid, (p, it) in BYID.items():
    sdoc = g.PREFIX_INFO[p][0]
    for ref in refs_of(it):
        if ref not in ALLIDS:
            v(sdoc, 'L2', 'R01', f'{iid} 參照不存在的 {ref}')
            continue
        if BYID[ref][1].get('lifecycle') != 'ACTIVE':
            v(sdoc, 'L2', 'R01', f'{iid} 參照非 ACTIVE 的 {ref}')
        tdoc = doc_of(ref)
        if tdoc != sdoc and not rank_of(ref) < g.PREFIX_INFO[p][1]:
            v(sdoc, 'L2', 'R03', f'{iid} 往下游參照 {ref}')
        if tdoc != '01-overview' or sdoc == '01-overview':
            pass
        tp, tit = BYID[ref]
        if tp == 'OBJ' and tit['inclusion'] == 'EXCLUDED' and sdoc not in ('01-overview', '90-questions', '19-decision-log'):
            v(sdoc, 'L2', 'R04', f'{iid} 參照 EXCLUDED 物件 {ref}')
# R04b excluded native field names in body (outside 07 and 90/19)
xf_names = set()
for xf in ITEMS['XF']:
    rec = BYID[xf['entity']][1]['key']
    for f in xf['fields']:
        xf_names.add((rec, f))
for p, lst in ITEMS.items():
    sdoc = g.PREFIX_INFO[p][0]
    if sdoc in ('07-database', '90-questions', '19-decision-log'):
        continue
    for it in lst:
        for s in strings_of(it):
            for rec, f in xf_names:
                if re.search(r'(?<![A-Z0-9_])' + re.escape(f) + r'(?![A-Z0-9_])', s):
                    v(sdoc, 'L2', 'R04', f'{it["id"]} 正文寫到不建置欄位 {rec}.{f}')
# R06 TRN writes status
for t in ITEMS['TRN']:
    to = BYID[t['to']][1]
    w = t['writes']
    ok = isinstance(w, list) and any(a['field'] == to['binding'] and a['value'] == {'const': to['code'], 'type': 'CHAR'} for a in w)
    if not ok:
        v('04-workflow', 'L2', 'R06', f'{t["id"]} 未寫入狀態欄位＝{to["code"]}')
    if t.get('via') and isinstance(t['guard'], dict) and 'na' in t['guard']:
        v('04-workflow', 'L2', 'R06', f'{t["id"]} 經 choice 收合但 guard 為 NA')
# R07 STATE code in xlat
for s in ITEMS['STATE']:
    if s['stateKind'] != 'SIMPLE':
        continue
    f = BYID[s['binding']][1]
    xl = {e['stored']: e['label'] for e in f['valueDomain'].get('xlat', [])}
    if s['code'] not in xl:
        v('04-workflow', 'L2', 'R07', f'{s["id"]} 狀態碼 {s["code"]} 不在 {f["key"]} 值域')
    elif s['domainLabel'] != xl[s['code']]:
        v('04-workflow', 'L2', 'R07', f'{s["id"]} 顯示文字與值域不符')
# status field xlat only diagram codes
for f in ITEMS['FLD']:
    states = [s for s in ITEMS['STATE'] if s.get('binding') == f['id']]
    if states and 'xlat' in f['valueDomain']:
        extra = {e['stored'] for e in f['valueDomain']['xlat']} - {s['code'] for s in states}
        if extra:
            v('07-database', 'L2', 'R07', f'{f["id"]} 狀態欄位值域含圖外代碼 {sorted(extra)}')
# R05 UI options subset
for u in ITEMS['UI']:
    if u.get('options'):
        b = u['binding']
        f = BYID[b['fld']][1]
        xl = {e['stored'] for e in f['valueDomain'].get('xlat', [])}
        bad = [o['stored'] for o in u['options'] if o['stored'] not in xl]
        if bad:
            v('05-ui', 'L2', 'R05', f'{u["id"]} 選項儲存值不在值域 {bad}')
# R08 DRV effective dating coverage
for d in ITEMS['DRV']:
    covered = {e['entity'] for e in d['resolution']['effectiveDating']}
    for src in d['resolution']['sources']:
        if BYID[src][1]['effectiveDating']['kind'] != 'NONE' and src not in covered:
            v('07-database', 'L2', 'R08', f'{d["id"]} 來源 {src} 有有效日但沒有有效日規則')
# R09 FR entry vs TRN trigger component
for fr in ITEMS['FR']:
    for t in fr['realizes']:
        trig = TRNS[t]['trigger']
        if isinstance(trig, dict) and 'object' in trig and trig['object'] != fr['entry']['object']:
            v('02-functional-requirements', 'L2', 'R09', f'{fr["id"]} 入口與 {t} 觸發物件不同')
# R10 BR control usedBy ∩ appliesTo
for b in ITEMS['BR']:
    c = b['trigger'].get('control')
    if c and not set(BYID[c][1]['usedBy']) & set(b['appliesTo']):
        v('09-business-logic', 'L2', 'R10', f'{b["id"]} 觸發元件不屬於適用功能')
# R11 OP transitions realized by its FR
for o in ITEMS['OP']:
    eff = o['effects']
    if isinstance(eff, dict) and 'transitions' in eff:
        missing = set(eff['transitions']) - set(BYID[o['fr']][1]['realizes'])
        if missing:
            v('08-api', 'L2', 'R11', f'{o["id"]} 轉移不屬於其功能 {sorted(missing)}')
# R12 TRN actor roles have PERM on trigger component
perm_pairs = {(pm['principal'], pm['resource']) for pm in ITEMS['PERM']}
for t in ITEMS['TRN']:
    roles = [x for x in refs_of({'a': t['actor']}) if x.startswith('ROLE-')]
    obj_ = t['trigger']['object'] if isinstance(t['trigger'], dict) and 'object' in t['trigger'] else None
    for ro in roles:
        if obj_ and (ro, obj_) not in perm_pairs:
            v('04-workflow', 'L2', 'R12', f'{t["id"]} 操作者角色 {ro} 對 {obj_} 沒有權限設定')

# ---- L3 coverage ----
# C01 diagram vs 04
state_codes = {s['code'] for s in ITEMS['STATE'] if s['stateKind'] == 'SIMPLE'}
if not PARSE['codesEqual'] or not PARSE['transitionsEqual']:
    v('04-workflow', 'L3', 'C01', '兩張圖不一致（研究前就應停止）')
if state_codes != SD_CODES:
    v('04-workflow', 'L3', 'C01', f'STATE 與狀態圖代碼不符 {sorted(state_codes ^ SD_CODES)}')
trn_pairs = set()
for t in ITEMS['TRN']:
    a = '*' if t['from'] == 'INITIAL' else BYID[t['from']][1]['code']
    b = BYID[t['to']][1]['code']
    trn_pairs.add((a, b))
    if tuple(t.get('via', [])) != VIA.get((a, b), ()):
        v('04-workflow', 'L3', 'C01', f'{t["id"]} via 與狀態圖不符')
if trn_pairs != SD_PAIRS:
    v('04-workflow', 'L3', 'C01', f'TRN 與狀態圖轉移不符 多={sorted(trn_pairs - SD_PAIRS)} 少={sorted(SD_PAIRS - trn_pairs)}')
for s in ITEMS['STATE']:
    if s['isFinal'] != (s['code'] in sd_finals):
        v('04-workflow', 'L3', 'C01', f'{s["id"]} 終點標記與狀態圖不符')
flows = {f['scenarioType']: f for f in ITEMS['FLOW']}
if set(flows) != set(SCENARIOS):
    v('04-workflow', 'L3', 'C01', f'FLOW 與情境類型不符 {sorted(set(flows) ^ set(SCENARIOS))}')
for lab, pairs in SCENARIOS.items():
    if lab in flows:
        got = set()
        for st_ in flows[lab]['steps']:
            t = TRNS[st_['transition']]
            got.add(('*' if t['from'] == 'INITIAL' else BYID[t['from']][1]['code'], BYID[t['to']][1]['code']))
        if got != pairs:
            v('04-workflow', 'L3', 'C01', f'FLOW「{lab}」步驟與 flowchart 不符')
# C02 TRN realized by FR
for t in ITEMS['TRN']:
    if not fr_of_trn.get(t['id']):
        v('02-functional-requirements', 'L3', 'C02', f'{t["id"]} 沒有功能實現')
    if isinstance(t['implementedAt'], dict):
        v('04-workflow', 'L3', 'C02', f'{t["id"]} 找不到實作')
# C03 page fields -> UI controls
ctrl_keys = {u['key'] for u in ITEMS['UI'] if u['uiKind'] == 'CONTROL'}
for scr, fields in PAGE_FIELDS.items():
    for f in fields:
        rec, fn = f.split('.')
        if (rec, fn) in xf_names:
            continue
        if f'{scr}.{f}' not in ctrl_keys:
            v('05-ui', 'L3', 'C03', f'頁面欄位 {scr}.{f} 沒有 UI 項目')
# C04 record fields -> FLD
fld_keys = {f['key'] for f in ITEMS['FLD']}
for rec, fields in RECORD_FIELDS.items():
    for fn in fields:
        if (rec, fn) in xf_names:
            continue
        if f'{rec}.{fn}' not in fld_keys:
            v('07-database', 'L3', 'C04', f'{rec}.{fn} 沒有 FLD 項目')
# C05 program dispositions
pcs = [o['id'] for o in ITEMS['OBJ'] if o['objectType'] == 'PEOPLECODE' and o['inclusion'] != 'EXCLUDED']
disp = collections.Counter(d['program'] for d in E.resolve(E.PROGRAM_DISPOSITIONS))
for pid in pcs:
    if disp[pid] != 1:
        v('09-business-logic', 'L3', 'C05', f'{pid} 處置筆數 {disp[pid]}')
# C06 fieldUsage excluded count == XF
for o in ITEMS['OBJ']:
    fu = o.get('fieldUsage')
    if fu and 'excluded' in fu:
        ents = [e for e in ITEMS['ENT'] if e['record'] == o['id']]
        xfs = [x for x in ITEMS['XF'] if ents and x['entity'] == ents[0]['id']]
        n = sum(len(x['fields']) for x in xfs)
        if n != fu['excluded']['count']:
            v('01-overview', 'L3', 'C06', f'{o["id"]} 排除欄數 {fu["excluded"]["count"]} 與 XF {n} 不符')
# C07 test coverage
COMPARE_OPS = {'GT', 'GE', 'LT', 'LE', 'BETWEEN'}
def has_compare(c):
    if isinstance(c, dict):
        if c.get('op') in COMPARE_OPS:
            return True
        return any(has_compare(x) for x in c.values())
    if isinstance(c, list):
        return any(has_compare(x) for x in c)
    return False
tcs = ITEMS['TC']
for fr in ITEMS['FR']:
    if not any(t['fr'] == fr['id'] and t['scenarioType'] == 'POSITIVE' for t in tcs):
        v('14-testing', 'L3', 'C07', f'{fr["id"]} 沒有正例')
for b in ITEMS['BR']:
    if b['action']['kind'] == 'REJECT' and not any(t['scenarioType'] == 'NEGATIVE' and b['id'] in t['covers'].get('rules', []) for t in tcs):
        v('14-testing', 'L3', 'C07', f'{b["id"]} 沒有反例')
    if has_compare(b['condition']):
        if not any(t['scenarioType'] == 'BOUNDARY' and b['id'] in t['covers'].get('rules', []) for t in tcs):
            v('14-testing', 'L3', 'C07', f'{b["id"]} 條件含比較運算但沒有邊界案例')
for t in ITEMS['TRN']:
    if not any(t['id'] in x['covers'].get('transitions', []) for x in tcs):
        v('14-testing', 'L3', 'C07', f'{t["id"]}（{t["key"].split(":")[1]}）沒有測試案例')
    if has_compare(t['guard']) and not any(x['scenarioType'] == 'BOUNDARY' and t['id'] in x['covers'].get('transitions', []) for x in tcs):
        v('14-testing', 'L3', 'C07', f'{t["id"]} 守衛含比較運算但沒有邊界案例')
for f in ITEMS['FLOW']:
    if not any(f['id'] in x['covers'].get('flows', []) for x in tcs):
        v('14-testing', 'L3', 'C07', f'{f["id"]} 沒有端到端案例')
# C08 FR -> OP and OP validations completeness
for fr in ITEMS['FR']:
    if not any(o['fr'] == fr['id'] for o in ITEMS['OP']):
        v('08-api', 'L3', 'C08', f'{fr["id"]} 沒有操作契約')
for o in ITEMS['OP']:
    eff = o['effects']
    trs = set(eff.get('transitions', [])) if isinstance(eff, dict) else set()
    for b in ITEMS['BR']:
        if b['action']['kind'] != 'REJECT':
            continue
        need = bool(trs & set(b['trigger'].get('transitions', [])))
        if b['trigger']['event'] == 'SAVE_EDIT' and o['fr'] in b['appliesTo'] and o['opKind'] in ('CREATE', 'UPDATE', 'TRANSITION'):
            need = True
        if need and b['id'] not in o['validations']:
            v('08-api', 'L3', 'C08', f'{o["id"]} 漏列檢核 {b["id"]}')
# C09 open blocking questions
for q in ITEMS['Q']:
    if q['status'] == 'OPEN' and q['severity'] == 'BLOCKING':
        for a in q['affects']:
            v(doc_of(a), 'L3', 'C09', f'{q["id"]} 未解（BLOCKING）影響 {a}')
# C10 tasks / dod coverage
for fr in ITEMS['FR']:
    if not any(t.get('fr') == fr['id'] for t in ITEMS['TASK']):
        v('17-tasks', 'L3', 'C10', f'{fr["id"]} 沒有工作項')
for t in ITEMS['TASK']:
    if not any(d.get('task') == t['id'] for d in ITEMS['DOD']):
        v('18-definition-of-done', 'L3', 'C10', f'{t["id"]} 沒有完成條件')

# ---------------- envelopes ----------------
SCHEMAS = {}
for f in glob.glob(ROOT + '/schemas/*.json'):
    s = json.load(open(f, encoding='utf-8'))
    SCHEMAS[s['$id']] = s
REG = Registry().with_resources([(k, Resource.from_contents(v, default_specification=DRAFT202012)) for k, v in SCHEMAS.items()])
def validator(doc):
    return Draft202012Validator(SCHEMAS[g.URN + doc], registry=REG)
FRAMEWORK_FP = sha(''.join(json.dumps(SCHEMAS[k], sort_keys=True, ensure_ascii=False) for k in sorted(SCHEMAS)))
EVK = {e['id']: e['kind'] for e in E.EVIDENCE}
L4_NA = {'16-ai-instructions', '17-tasks', '18-definition-of-done', '19-decision-log', '90-questions'}
L3_NA = {'16-ai-instructions', '19-decision-log', '90-questions'}
L5_APPLIES = {'02-functional-requirements', '03-roles-permissions', '04-workflow', '05-ui', '06-architecture',
              '07-database', '08-api', '09-business-logic'}
LABEL = {'GOAL': '目標', 'RESP': '決策責任', 'OBJ': '物件', 'AI': '條款', 'ENT': '實體', 'FLD': '欄位', 'DRV': '衍生概念',
         'XF': '不建置欄位組', 'ROLE': '角色', 'PERM': '權限', 'STATE': '狀態', 'TRN': '轉移', 'FLOW': '情境',
         'IF': '介面', 'FR': '功能', 'UI': '畫面元件', 'MSG': '訊息', 'BR': '規則', 'OP': '操作', 'TC': '測試案例',
         'TASK': '工作項', 'DOD': '完成條件', 'Q': '問題', 'DEC': '決策'}
def fence_ranges(md):
    out, start = [], None
    for i, line in enumerate(md.split('\n')):
        t = line.strip()
        if t.startswith('```mermaid'):
            start = i + 1
        elif t.startswith('```') and start is not None:
            out.append(f'L{start}-L{i + 1}')
            start = None
    return out
FENCES = fence_ranges(X.STATUS_DOC)
EXTRA_VALUES = {
    '01-overview': {'projectInputStatus': 'PROVIDED'},
    '04-workflow': {'diagramSources': [{'entityKey': 'REQ_STATUS', 'flowchart': 'status-REQ_STATUS.md#' + FENCES[0],
                                        'stateDiagram': 'status-REQ_STATUS.md#' + FENCES[1], 'fingerprint': sha(X.STATUS_DOC)}]},
    '09-business-logic': {'programDispositions': E.resolve(E.PROGRAM_DISPOSITIONS)},
    '90-questions': {'suppressed': E.SUPPRESSED},
}

def doc_items(doc):
    out = []
    for p in g.DOC_ITEMS[doc]:
        out += ITEMS.get(p, [])
    return out

def compute_envelope(doc, gate):
    items = doc_items(doc)
    ids = {it['id'] for it in items}
    deps = set()
    for it in items:
        for ref in refs_of(it):
            d = doc_of(ref)
            if d != doc:
                deps.add(d)
    for k, val in EXTRA_VALUES.get(doc, {}).items():
        for s in strings_of(val):
            if REFRX.match(s) and doc_of(s) != doc:
                deps.add(doc_of(s))
    kinds = set()
    for it in items:
        for e in it.get('evidence', []):
            kinds.add(EVK[e])
    sources = [{'kind': 'FRAMEWORK', 'ref': 'schemas/1.0', 'fingerprint': FRAMEWORK_FP}]
    if 'STATUS_DOC' in kinds:
        sources.append({'kind': 'STATUS_DOC', 'ref': 'status-REQ_STATUS.md', 'fingerprint': sha(X.STATUS_DOC)})
    if 'PROJECT_INPUT' in kinds:
        sources.append({'kind': 'PROJECT_INPUT', 'ref': 'project.md', 'fingerprint': sha(X.PROJECT_INPUT)})
    if 'HUMAN_DECISION' in kinds:
        sources.append({'kind': 'HUMAN_DECISION', 'ref': 'decisions.md', 'fingerprint': sha(DEC_MD)})
    research = sorted(e for it in items for e in it.get('evidence', []) if EVK[e] in ('CHUNK', 'SQL', 'METADATA_RECEIPT'))
    if research:
        sources.append({'kind': 'RESEARCH_RECEIPT', 'ref': f'receipts/{doc}', 'fingerprint': sha(','.join(research))})
    openq = sorted(q['id'] for q in ITEMS['Q'] if q['status'] == 'OPEN' and set(q['affects']) & ids)
    counts = collections.Counter(it['id'].split('-')[0] for it in items)
    summary = '、'.join(f'{LABEL[p]} {counts[p]}' for p in g.DOC_ITEMS[doc] if counts[p]) or '無項目'
    if doc == '90-questions':
        st = collections.Counter(q['status'] for q in items)
        blocking_open = sum(1 for q in items if q['status'] == 'OPEN' and q['severity'] == 'BLOCKING')
        summary += '（' + '、'.join(f'{k} {st[k]}' for k in ['OPEN', 'ANSWERED', 'WITHDRAWN', 'ACCEPTED_AS_GAP'] if st[k]) + \
                   f'）；未解 BLOCKING {blocking_open}；只計數的定義值 {E.SUPPRESSED["definitionOnlyCount"]}'
    elif doc not in ('19-decision-log', '16-ai-instructions'):
        summary += f'；未解問題 {len(openq)}'
    applicable = [k for k in ['L1', 'L2', 'L3', 'L4', 'L5'] if gate[k] != 'NOT_APPLICABLE']
    status = 'in_review' if all(gate[k] == 'PASS' for k in applicable) else 'draft'
    env = {'schemaVersion': '1.0', 'docType': doc, 'docId': f'{E.JOB}/{g.DOC_NUM[doc]}', 'jobId': E.JOB,
           'revision': E.REV, 'status': status, 'title': dict(g.DOC_TYPES)[doc], 'summary': summary,
           'components': COMPONENTS, 'dependsOn': sorted(deps, key=g.DOC_IDS.index), 'sources': sources, 'gate': gate,
           'openQuestions': openq}
    env.update(copy.deepcopy(EXTRA_VALUES.get(doc, {})))
    env['items'] = items
    return env

REPORT = {'parse': PARSE, 'docs': {}, 'violations': {}}
DOCS = {}
for doc in g.DOC_IDS:
    placeholder = {k: 'NOT_RUN' for k in ['L1', 'L2', 'L3', 'L4', 'L5']}
    env = compute_envelope(doc, placeholder)
    errs = sorted(validator(doc).iter_errors(env), key=lambda e: list(e.absolute_path))
    l1 = 'PASS' if not errs else 'FAIL'
    for e in errs:
        v(doc, 'L1', 'S01', f'{list(e.absolute_path)}: {e.message[:160]}')
    l2 = 'FAIL' if VIOL.get((doc, 'L2')) else 'PASS'
    l3 = 'NOT_APPLICABLE' if doc in L3_NA else ('FAIL' if VIOL.get((doc, 'L3')) else 'PASS')
    l4 = 'NOT_APPLICABLE' if doc in L4_NA else 'PASS'
    if doc in L5_APPLIES:
        l5 = 'PASS' if all(x in ('PASS', 'NOT_APPLICABLE') for x in (l1, l2, l3, l4)) else 'NOT_RUN'
    else:
        l5 = 'NOT_APPLICABLE'
    gate = {'L1': l1, 'L2': l2, 'L3': l3, 'L4': l4, 'L5': l5}
    env = compute_envelope(doc, gate)
    errs = list(validator(doc).iter_errors(env))
    assert not errs or l1 == 'FAIL', errs[:3]
    DOCS[doc] = env
    REPORT['docs'][doc] = {'gate': gate, 'status': env['status'], 'summary': env['summary'], 'dependsOn': env['dependsOn']}
for (doc, layer), msgs in sorted(VIOL.items()):
    REPORT['violations'][f'{doc}/{layer}'] = msgs

# evidence doc
EVDOC = {'schemaVersion': '1.0', 'jobId': E.JOB, 'revision': E.REV, 'items': E.EVIDENCE}
everrs = list(Draft202012Validator(SCHEMAS[g.URN + 'evidence'], registry=REG).iter_errors(EVDOC))
REPORT['evidenceErrors'] = [e.message[:160] for e in everrs]
used_ev = {e for lst in ITEMS.values() for it in lst for e in it.get('evidence', [])}
REPORT['evidenceUnused'] = sorted(set(EVK) - used_ev)
REPORT['evidenceMissing'] = sorted(used_ev - set(EVK))

# ---------------- write files ----------------
for doc, env in DOCS.items():
    dump(f'{EXW}/canonical/{doc}.json', env)
dump(f'{EXW}/canonical/evidence.json', EVDOC)
write_text(f'{EXW}/input/status-REQ_STATUS.md', X.STATUS_DOC)
write_text(f'{EXW}/input/project.md', X.PROJECT_INPUT)
write_text(f'{EXW}/input/decisions.md', DEC_MD)

# ---------------- minimal valid documents ----------------
def minimize(doc, item):
    val = validator(doc)
    base = {'schemaVersion': '1.0', 'docType': doc, 'docId': f'{E.JOB}/{g.DOC_NUM[doc]}', 'jobId': E.JOB,
            'revision': E.REV, 'status': 'draft', 'title': dict(g.DOC_TYPES)[doc], 'summary': '最小合法文件（只過 L1）',
            'components': ['TW_DEMO_REQ'], 'dependsOn': [], 'sources': [],
            'gate': {k: 'NOT_RUN' for k in ['L1', 'L2', 'L3', 'L4', 'L5']}, 'openQuestions': []}
    extra = copy.deepcopy(EXTRA_VALUES.get(doc, {}))
    # shrink envelope extras to minimal forms
    if doc == '04-workflow':
        extra = {'diagramSources': extra['diagramSources'][:1]}
    if doc == '09-business-logic':
        extra = {'programDispositions': []}
    if doc == '90-questions':
        extra = {'suppressed': {'definitionOnlyCount': 0, 'definitionOnlyCodes': []}}
    base.update(extra)
    it = copy.deepcopy(item)
    base['items'] = [it]
    assert not list(val.iter_errors(base)), list(val.iter_errors(base))[:2]
    changed = True
    while changed:
        changed = False
        for k in list(it.keys()):
            if k in ('id', 'key'):
                continue
            trial = copy.deepcopy(it)
            del trial[k]
            base['items'] = [trial]
            if not list(val.iter_errors(base)):
                it = trial
                changed = True
                break
        base['items'] = [it]
    # also shrink arrays to one element where valid
    for k, val_ in list(it.items()):
        if isinstance(val_, list) and len(val_) > 1:
            trial = copy.deepcopy(it)
            trial[k] = val_[:1]
            base['items'] = [trial]
            if not list(val.iter_errors(base)):
                it = trial
    base['items'] = [it]
    assert not list(val.iter_errors(base))
    return base

MIN_PICK = {'GOAL': 'GOAL:01', 'RESP': 'RESP:SPEC_APPROVAL', 'OBJ': 'RECORD:TW_DEMO_REQHDR', 'AI': 'AI:01',
            'ENT': 'TW_DEMO_REQHDR', 'FLD': 'TW_DEMO_REQHDR.AMOUNT', 'DRV': 'REQUESTER_SUPERVISOR', 'XF': 'TW_DEMO_REQHDR',
            'ROLE': 'ROLE:TW_DEMO_REQUESTER', 'PERM': 'ROLE:TW_DEMO_REQUESTER>COMPONENT:TW_DEMO_REQ',
            'STATE': 'REQ_STATUS:020', 'TRN': 'REQ_STATUS:020>030', 'FLOW': 'REQ_STATUS:高額審核', 'IF': 'AE:TW_DEMO_NTFY',
            'FR': 'TW_DEMO_REQ:SUBMIT', 'UI': 'TW_DEMO_REQ.TW_DEMO_REQPG.TW_DEMO_REQWRK.SUBMIT_PB', 'MSG': '27000,3',
            'BR': 'TW_DEMO_REQWRK.SUBMIT_PB.FieldChange:SUPERVISOR_REQUIRED', 'OP': 'TW_DEMO_REQ:SUBMIT:SUBMIT',
            'TC': 'TW_DEMO_REQ:SUBMIT:NEGATIVE:NO_SUPERVISOR', 'TASK': 'SLICE:TW_DEMO_REQ:SUBMIT',
            'DOD': 'TASK:SLICE:TW_DEMO_REQ:SUBMIT', 'Q': 'OFF_DIAGRAM_STATE:REQ_STATUS:099', 'DEC': 'DEC:0001'}
MINIMAL_ITEMS = {}
for doc in g.DOC_IDS:
    parts = []
    for p in g.DOC_ITEMS[doc]:
        src = next(it for it in ITEMS[p] if it['key'] == MIN_PICK[p])
        m = minimize(doc, src)
        MINIMAL_ITEMS[p] = m['items'][0]
        parts.append(m['items'][0])
    m['items'] = parts
    errs = list(validator(doc).iter_errors(m))
    assert not errs, errs[:2]
    dump(f'{EXM}/{doc}.json', m)
dump(f'{EXW}/gate-report.json', REPORT)

if __name__ == '__main__':
    print(json.dumps(REPORT['parse'], ensure_ascii=False, indent=1))
    for doc, r in REPORT['docs'].items():
        print(doc, r['status'], r['gate'], r['summary'])
    for k, msgs in REPORT['violations'].items():
        print('VIOL', k)
        for m in msgs:
            print('   ', m)
    print('evidence errors', REPORT['evidenceErrors'], 'unused', REPORT['evidenceUnused'], 'missing', REPORT['evidenceMissing'])
