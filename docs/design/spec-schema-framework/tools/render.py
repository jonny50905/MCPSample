# -*- coding: utf-8 -*-
"""渲染器原型：canonical JSON → 00-index.md 與每種文件一份 Markdown（含重新產生的 Mermaid 圖與反查欄）。"""
import json, os, re, glob, collections
import schema_gen as g

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'examples', 'walkthrough')
CAN = ROOT + '/canonical'
OUT = ROOT + '/rendered'

DOCS = {}
for doc in g.DOC_IDS:
    DOCS[doc] = json.load(open(f'{CAN}/{doc}.json', encoding='utf-8'))
EVID = {e['id']: e for e in json.load(open(f'{CAN}/evidence.json', encoding='utf-8'))['items']}
BYID = {}
for doc, d in DOCS.items():
    for it in d['items']:
        BYID[it['id']] = (doc, it)
REFRX = re.compile(r'^(' + '|'.join(g.PREFIX_INFO) + r')-\d{3,}$')
FILE = {doc: f'{doc}.md' for doc in g.DOC_IDS}

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
for doc, d in DOCS.items():
    for pd in d.get('programDispositions', []):
        for x in pd['items']:
            REVERSE[x].add(pd['program'])

def label(iid):
    if iid not in BYID:
        return iid
    p = iid.split('-')[0]
    it = BYID[iid][1]
    if p == 'OBJ':
        return it['objectName']
    if p in ('ENT', 'FLD', 'XF', 'PERM', 'DOD', 'Q'):
        return it['key']
    if p == 'TRN':
        k = it['key'].split(':', 1)[1]
        return k.replace('*', '新建').replace('>', '→')
    if p == 'FLOW':
        return it['scenarioType']
    if p == 'UI':
        return it.get('title') or (it['label'] if isinstance(it.get('label'), str) else it['key'].split('.')[-1])
    if p == 'MSG':
        return it['key']
    if p == 'RESP':
        return it['area']
    if p == 'AI':
        return it['category']
    if p == 'DEC':
        return it['title']
    for k in ('name', 'title'):
        if k in it and isinstance(it[k], str):
            return it[k]
    return it['key']

def link(iid):
    if iid in ('INITIAL',):
        return '（新建）'
    if iid not in BYID:
        return iid
    return f'{iid}（{label(iid)}）'

CTX_TEXT = {'CURRENT_USER_OPRID': '目前使用者帳號', 'CURRENT_USER_EMPLID': '目前使用者員工編號', 'CURRENT_DATE': '系統日期',
            'CURRENT_DATETIME': '系統時間', 'CURRENT_MODE': '目前模式', 'CURRENT_ACTION': '目前動作'}
OP_TEXT = {'EQ': '＝', 'NE': '≠', 'GT': '＞', 'GE': '≥', 'LT': '＜', 'LE': '≤', 'IN': '屬於', 'NOT_IN': '不屬於',
           'BETWEEN': '介於', 'HAS_ROLE': '具有角色'}
UNARY_TEXT = {'IS_BLANK': '為空白（字元欄為 NULL 或單一空白）', 'IS_NOT_BLANK': '不為空白', 'EXISTS': '查得到',
              'NOT_EXISTS': '查不到（結果為空）', 'CHANGED': '本次有變更'}

def operand_text(o):
    if 'fld' in o:
        return link(o['fld'])
    if 'drv' in o:
        return '〈' + label(o['drv']) + '〉' + f'（{o["drv"]}）'
    if 'state' in o:
        it = BYID[o['state']][1]
        return f"'{it['code']}'（{o['state']} {it['name'].split(' ', 1)[1]}）"
    if 'role' in o:
        return link(o['role'])
    if 'const' in o:
        return o['const'] if o['type'] == 'NUMBER' else f"'{o['const']}'"
    if 'ctx' in o:
        return CTX_TEXT[o['ctx']]
    if 'param' in o:
        return f'參數 {o["param"]}'
    if 'expr' in o:
        return o['expr']
    return json.dumps(o, ensure_ascii=False)

def cond_text(c):
    if c == 'ALWAYS':
        return '無條件'
    if 'all' in c:
        return '且'.join('（' + cond_text(x) + '）' for x in c['all'])
    if 'any' in c:
        return '或'.join('（' + cond_text(x) + '）' for x in c['any'])
    if 'not' in c:
        return '非（' + cond_text(c['not']) + '）'
    left = operand_text(c['left'])
    if c['op'] in UNARY_TEXT:
        return f'{left} {UNARY_TEXT[c["op"]]}'
    r = c['right']
    if isinstance(r, list):
        rt = '、'.join(operand_text(x) for x in r)
        if c['op'] == 'BETWEEN':
            rt = ' 與 '.join(operand_text(x) for x in r)
        return f'{left} {OP_TEXT[c["op"]]} {{{rt}}}' if c['op'] != 'BETWEEN' else f'{left} 介於 {rt}'
    return f'{left} {OP_TEXT[c["op"]]} {operand_text(r)}'

def is_cond(v):
    return v == 'ALWAYS' or (isinstance(v, dict) and (set(v) & {'all', 'any', 'not'} or {'left', 'op'} <= set(v)))

def is_operand(v):
    return isinstance(v, dict) and len(set(v) & {'fld', 'drv', 'state', 'role', 'const', 'ctx', 'param', 'expr'}) == 1 and \
        set(v) <= {'fld', 'drv', 'state', 'role', 'const', 'ctx', 'param', 'expr', 'type'}

NL = {'kind': '種類', 'object': '物件', 'action': '動作', 'event': '事件', 'transitions': '轉移', 'modes': '模式',
      'control': '元件', 'message': '訊息', 'assignments': '指派', 'interface': '介面', 'sources': '來源實體',
      'joins': '串接', 'filter': '篩選', 'effectiveDating': '有效日規則', 'pick': '取值欄位', 'tieBreak': '同值處理',
      'result': '結果', 'fallback': '替代', 'note': '說明', 'rule': '規則', 'orderBy': '排序', 'entity': '實體',
      'keyField': '鍵欄位', 'asOf': '基準日', 'effStatusActiveOnly': '只取有效狀態', 'currentRow': '目前有效列',
      'boundary': '交易邊界', 'writeOrder': '寫入順序', 'onFailure': '失敗時', 'concurrency': '併發',
      'idempotency': '重複執行', 'strategy': '策略', 'legacyBehavior': '原系統行為', 'repeatable': '可重複',
      'behavior': '行為', 'writes': '寫入', 'interfaces': '介面', 'events': '事件鏈', 'name': '名稱', 'field': '欄位',
      'drv': '衍生概念', 'required': '必填', 'seq': '序', 'transition': '轉移', 'description': '說明', 'state': '狀態',
      'actor': '操作者', 'data': '資料', 'synthetic': '合成資料', 'rules': '規則', 'flows': '情境', 'controls': '元件',
      'operations': '操作', 'resultState': '結果狀態', 'noDataChange': '資料不變', 'value': '值', 'visible': '顯示',
      'editable': '可編輯', 'label': '文字', 'stored': '儲存值', 'key': '代號', 'scrollLevel': '層級',
      'repeating': '可重複列', 'parentRegion': '上層區塊', 'excluded': '排除', 'count': '欄數',
      'noneExcludable': '無可排除', 'checkedOn': '查詢日', 'undetermined': '判不了', 'code': '代碼', 'a': '查法 a',
      'b': '查法 b', 'c': '查法 c', 'xlat': '值清單', 'prompt': '查找來源', 'range': '範圍', 'free': '自由輸入',
      'derived': '衍生', 'active': '有效', 'dataPresence': '資料', 'target': '目標', 'layout': '版面',
      'encoding': '編碼', 'fields': '欄位', 'length': '長度', 'format': '格式', 'source': '來源', 'from': '起',
      'to': '迄', 'location': '位置', 'entityKey': '狀態實體', 'option': '選項', 'consequence': '結果',
      'statement': '敘述', 'refs': '參照', 'evidenceRequired': '需要的證據', 'entities': '實體',
      'derivations': '衍生概念', 'roles': '角色', 'tests': '測試', 'effect': '效果', 'inputs': '輸入', 'left': '左',
      'right': '右', 'operation': '操作', 'definitionOnlyCount': '只計數的定義值', 'definitionOnlyCodes': '定義值'}

def val_text(v):
    """single-line rendering when possible, else None"""
    if isinstance(v, bool):
        return '是' if v else '否'
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        if REFRX.match(v):
            return link(v)
        if v == 'INITIAL':
            return '（新建）'
        if v == 'ALWAYS':
            return '一律（無條件）'
        if v == 'NEVER':
            return '永不'
        return v
    if isinstance(v, dict) and set(v) <= {'na', 'evidence'} and 'na' in v:
        return '不適用：' + v['na']
    if isinstance(v, dict) and set(v) == {'unresolved'}:
        return '未解：' + link(v['unresolved'])
    if is_cond(v):
        return cond_text(v)
    if is_operand(v):
        return operand_text(v)
    if isinstance(v, dict) and set(v) <= {'field', 'value', 'when', 'note'} and 'field' in v and 'value' in v:
        if isinstance(v['value'], dict):
            t = f'{link(v["field"])} ← {operand_text(v["value"])}'
        else:
            t = f"{link(v['field'])} ＝ '{v['value']}'"
        if 'when' in v:
            t += f'（當 {cond_text(v["when"])}）'
        if 'note' in v:
            t += f'（{v["note"]}）'
        return t
    if isinstance(v, list):
        parts = [val_text(x) for x in v]
        if all(p is not None for p in parts):
            joined = '、'.join(parts) if parts else '（無）'
            return joined if len(joined) <= 160 or len(parts) == 1 else None
        return None
    return None

def bullets(v, indent=0):
    pad = '  ' * indent
    lines = []
    if isinstance(v, dict):
        for k, x in v.items():
            t = val_text(x)
            if t is not None:
                lines.append(f'{pad}- {NL.get(k, k)}：{t}')
            else:
                lines.append(f'{pad}- {NL.get(k, k)}：')
                lines += bullets(x, indent + 1)
    elif isinstance(v, list):
        for i, x in enumerate(v):
            t = val_text(x)
            if t is not None:
                lines.append(f'{pad}- {t}')
            elif isinstance(x, dict) and all(val_text(y) is not None for y in x.values()):
                lines.append(f'{pad}- ' + '；'.join(f'{NL.get(k, k)}：{val_text(y)}' for k, y in x.items()))
            else:
                lines.append(f'{pad}- 第 {i + 1} 筆')
                lines += bullets(x, indent + 1)
    return lines

FIELD_DESC = {p: {f.name: f.desc for f in g.ITEM_TYPES[p]['fields']} for p in g.ITEM_TYPES}
SKIP = {'id', 'key', 'lifecycle', 'basis', 'certainty', 'evidence', 'derivedFrom', 'component', 'inference'}
BASIS_TEXT = {'AUTHORITATIVE_DOC': '狀態權威文件', 'CODE': '程式', 'DATA': '資料', 'METADATA': 'metadata', 'KNOWLEDGE': '既有研究',
              'PROJECT_INPUT': '專案輸入', 'HUMAN_DECISION': '人工決策', 'DERIVED': '推導', 'COMPUTED': '外環計算',
              'TEMPLATE': '框架模板'}

def item_md(it):
    p = it['id'].split('-')[0]
    out = [f'### {it["id"]}　{label(it["id"])}', '']
    out.append(f'- 自然鍵：`{it["key"]}`')
    for k, x in it.items():
        if k in SKIP:
            continue
        desc = FIELD_DESC[p].get(k, k)
        t = val_text(x)
        if t is not None:
            out.append(f'- {desc}：{t}')
        else:
            out.append(f'- {desc}：')
            out += bullets(x, 1)
    src = BASIS_TEXT[it['basis']]
    if it['certainty'] == 'INFERRED':
        src += '（推論：' + it['inference'] + '）'
    if it.get('derivedFrom'):
        src += '；推導自 ' + '、'.join(it['derivedFrom'])
    if it['evidence']:
        src += '；證據 ' + '、'.join(it['evidence'])
    out.append(f'- 來源：{src}')
    rev = sorted(REVERSE.get(it['id'], []), key=lambda x: (g.PREFIX_INFO[x.split('-')[0]][1], x))
    if rev:
        groups = collections.OrderedDict()
        for x in rev:
            groups.setdefault(x.split('-')[0], []).append(x)
        out.append('- 被引用（外環反查）：' + '；'.join('、'.join(v) for v in groups.values()))
    out.append('')
    return out

def header(doc):
    d = DOCS[doc]
    gate = ' · '.join(f'{k} {v}' for k, v in d['gate'].items())
    deps = '、'.join(x.split('-')[0] for x in d['dependsOn']) or '無'
    oq = '、'.join(link(q) for q in d['openQuestions']) or '無'
    return [f'# {d["title"]}', '',
            f'> `{d["docId"]}`｜版本 {d["revision"]}｜狀態 **{d["status"]}**｜{gate}',
            f'> 依賴文件：{deps}｜未解問題：{oq}',
            f'> {d["summary"]}',
            '> 本檔由 canonical JSON 以程式產生，請勿手改；修改走研究重跑或 19 的決策。', '']

def mermaid_state(d):
    states = [i for i in d['items'] if i['id'].startswith('STATE-')]
    trns = [i for i in d['items'] if i['id'].startswith('TRN-')]
    sid = {s['id']: 'S' + s['code'] for s in states}
    out = ['```mermaid', 'stateDiagram-v2']
    for s in states:
        out.append(f'    state "{s["name"]}" as {sid[s["id"]]}')
    vias = sorted({v for t in trns for v in t.get('via', [])})
    for v in vias:
        out.append(f'    state {v} <<choice>>')
    seen = set()
    for t in trns:
        a = '[*]' if t['from'] == 'INITIAL' else sid[t['from']]
        b = sid[t['to']]
        if t.get('via'):
            v = t['via'][0]
            if (a, v) not in seen:
                out.append(f'    {a} --> {v}')
                seen.add((a, v))
            g_ = cond_text(t['guard']) if isinstance(t['guard'], dict) and 'na' not in t['guard'] else ''
            g_ = re.sub(r'（FLD-\d+）', '', g_).replace('TW_DEMO_REQHDR.', '')
            out.append(f'    {v} --> {b} : {t["id"]} {g_}'.rstrip())
        else:
            out.append(f'    {a} --> {b} : {t["id"]}')
    for s in states:
        if s['isFinal']:
            out.append(f'    {sid[s["id"]]} --> [*]')
    out.append('```')
    return out

def mermaid_flow(d):
    states = {i['id']: i for i in d['items'] if i['id'].startswith('STATE-')}
    out = ['```mermaid', 'flowchart TD', '    START((新建))']
    for s in states.values():
        out.append(f'    N{s["code"]}["{s["name"]}"]')
    for f in [i for i in d['items'] if i['id'].startswith('FLOW-')]:
        for st in f['steps']:
            t = BYID[st['transition']][1]
            a = 'START' if t['from'] == 'INITIAL' else 'N' + states[t['from']]['code']
            b = 'N' + states[t['to']]['code']
            out.append(f'    {a} -->|{f["scenarioType"]}｜{t["id"]}| {b}')
    out.append('```')
    return out

def section(doc, prefix):
    title = {'GOAL': '專案目標', 'RESP': '決策責任', 'OBJ': '範圍（舊系統物件）', 'AI': '條款', 'ENT': '資料實體',
             'FLD': '資料欄位', 'DRV': '衍生概念（查找規則）', 'XF': '不建置的原生欄位', 'ROLE': '角色', 'PERM': '權限',
             'STATE': '狀態', 'TRN': '狀態轉移', 'FLOW': '情境流程', 'IF': '介面與批次', 'FR': '功能需求', 'UI': '畫面與元件',
             'MSG': '訊息', 'BR': '業務規則', 'OP': '操作契約', 'TC': '測試案例', 'TASK': '工作項', 'DOD': '完成條件',
             'Q': '問題', 'DEC': '決策'}[prefix]
    items = [i for i in DOCS[doc]['items'] if i['id'].startswith(prefix + '-')]
    out = [f'## {title}（{prefix}）', '']
    if not items:
        out += ['（無）', '']
        return out
    for it in items:
        out += item_md(it)
    return out

def render_doc(doc):
    d = DOCS[doc]
    out = header(doc)
    if doc == '01-overview':
        out += ['## 範圍摘要', '', '| 分類 | 物件 |', '|---|---|']
        for inc in ['CORE', 'DEPENDENCY', 'EXCLUDED']:
            objs = [i for i in d['items'] if i['id'].startswith('OBJ-') and i['inclusion'] == inc]
            out.append(f'| {inc} | ' + '、'.join(f'{o["id"]} {o["objectName"]}' for o in objs) + ' |')
        out += ['', f'專案輸入檔：{d["projectInputStatus"]}。不建置的原生欄位見 07。', '']
    if doc == '04-workflow':
        out += ['## 狀態圖（由 STATE／TRN 重新產生）', ''] + mermaid_state(d) + ['']
        out += ['## 情境流程圖（由 FLOW 重新產生）', ''] + mermaid_flow(d) + ['']
        out += ['來源圖：' + '、'.join(f'{x["entityKey"]}：{x["flowchart"]}、{x["stateDiagram"]}' for x in d['diagramSources']), '']
    if doc == '07-database':
        out += ['## 不建置的原生欄位（摘要）', '', '| ID | Record | 欄位 | 資料剖析 |', '|---|---|---|---|']
        for x in [i for i in d['items'] if i['id'].startswith('XF-')]:
            out.append(f'| {x["id"]} | {x["key"]} | {"、".join(x["fields"])} | {x["dataCheck"]} |')
        out += ['', '重建時這些欄位不建資料欄、不上畫面、不寫規則。', '']
    if doc == '09-business-logic':
        out += ['## PeopleCode 程式處置（覆蓋率分母）', '', '| 程式 | 處置 | 對應項目 |', '|---|---|---|']
        for pd in d['programDispositions']:
            items = '、'.join(pd['items']) or '—'
            note = ('；' + pd['note']) if pd.get('note') else ''
            out.append(f'| {link(pd["program"])} | {"、".join(pd["kinds"])} | {items}{note} |')
        out.append('')
    if doc == '17-tasks':
        out += ['## 建議順序', '', '| 順序 | 工作 | 依賴 |', '|---|---|---|']
        for t in sorted(d['items'], key=lambda x: x['order']):
            out.append(f'| {t["order"]} | {t["id"]} {t["name"]} | {"、".join(t["dependsOn"]) or "—"} |')
        out.append('')
    if doc == '90-questions':
        s = d['suppressed']
        out += [f'只存在於值域定義、沒有資料也沒有核心程式使用的狀態碼：{s["definitionOnlyCount"]} 個（'
                + '、'.join(f'{x["entityKey"]}={x["code"]}' for x in s['definitionOnlyCodes']) + '），只計數、不列題。', '']
    for p in g.DOC_ITEMS[doc]:
        out += section(doc, p)
    return '\n'.join(out).rstrip() + '\n'

def render_index():
    j = DOCS['01-overview']
    job_status = 'REVIEW_READY' if all(DOCS[d]['status'] in ('in_review', 'approved') for d in g.DOC_IDS) else 'DRAFT'
    out = ['# 00 索引', '',
           f'> `{j["jobId"]}`｜版本 {j["revision"]}｜整體狀態 **{job_status}**｜Component：{"、".join(j["components"])}',
           '> 本檔由外環產生，是閱讀入口；規格內容以各文件為準。', '',
           '## 閱讀順序', '',
           '1. 16 AI 實作指引（怎麼讀、什麼不能做）',
           '2. 01 專案概覽 → 04 流程與狀態機 → 02 功能需求',
           '3. 07 資料設計 → 03 角色與權限 → 05 畫面與互動 → 09 業務邏輯 → 06 系統架構 → 08 操作契約',
           '4. 14 測試與驗收 → 17 工作拆解 → 18 完成定義',
           '5. 19 決策紀錄、90 問題清單（實作前確認沒有影響自己工作的未解問題）', '',
           '## 文件與檢核', '', '| 文件 | 狀態 | L1 | L2 | L3 | L4 | L5 | 摘要 |', '|---|---|---|---|---|---|---|---|']
    for doc in g.DOC_IDS:
        d = DOCS[doc]
        gt = d['gate']
        out.append(f'| [{d["title"]}]({FILE[doc]}) | {d["status"]} | {gt["L1"]} | {gt["L2"]} | {gt["L3"]} | {gt["L4"]} | {gt["L5"]} | {d["summary"]} |')
    rep = json.load(open(ROOT + '/gate-report.json', encoding='utf-8'))
    out += ['', '## 未通過的檢核', '']
    if rep['violations']:
        for k, msgs in rep['violations'].items():
            out.append(f'- {k}：' + '；'.join(msgs))
    else:
        out.append('- 無')
    out += ['', '## ID 前綴對照', '', '| 前綴 | 項目 | 定義所在 |', '|---|---|---|']
    for p, (doc, rank, name) in g.PREFIX_INFO.items():
        out.append(f'| `{p}` | {name} | [{dict(g.DOC_TYPES)[doc]}]({FILE[doc]}) |')
    out += ['', '## 追溯矩陣（以功能為列，外環反查產生）', '',
            '| 功能 | 轉移 | 情境 | 元件 | 規則 | 操作 | 測試 | 工作 |', '|---|---|---|---|---|---|---|---|']
    flows = [i for i in DOCS['04-workflow']['items'] if i['id'].startswith('FLOW-')]
    for fr in DOCS['02-functional-requirements']['items']:
        frid = fr['id']
        trn = sorted(fr['realizes'])
        fl = sorted({f['id'] for f in flows for s in f['steps'] if s['transition'] in trn})
        ui = sorted(x for x in REVERSE[frid] if x.startswith('UI-') and BYID[x][1]['uiKind'] == 'CONTROL')
        br = sorted(x for x in REVERSE[frid] if x.startswith('BR-'))
        op = sorted(x for x in REVERSE[frid] if x.startswith('OP-'))
        tc = sorted(x for x in REVERSE[frid] if x.startswith('TC-'))
        tk = sorted(x for x in REVERSE[frid] if x.startswith('TASK-'))
        cells = ['、'.join(x) or '—' for x in (trn, fl, ui, br, op, tc, tk)]
        out.append(f'| {frid} {fr["name"]} | ' + ' | '.join(cells) + ' |')
    qs = DOCS['90-questions']['items']
    out += ['', '## 問題摘要', '',
            f'- BLOCKING 未解：{sum(1 for q in qs if q["severity"] == "BLOCKING" and q["status"] == "OPEN")}',
            f'- 資訊類未解：{sum(1 for q in qs if q["severity"] == "INFO" and q["status"] == "OPEN")}'
            f'（圖外 HIGH {sum(1 for q in qs if q.get("grade") == "HIGH" and q["status"] == "OPEN")}、'
            f'LOW {sum(1 for q in qs if q.get("grade") == "LOW" and q["status"] == "OPEN")}）',
            f'- 已回答：{sum(1 for q in qs if q["status"] == "ANSWERED")}；已撤回：{sum(1 for q in qs if q["status"] == "WITHDRAWN")}',
            f'- 只計數的定義值：{DOCS["90-questions"]["suppressed"]["definitionOnlyCount"]}', '']
    xf = [i for i in DOCS['07-database']['items'] if i['id'].startswith('XF-')]
    objs = [i for i in j['items'] if i['id'].startswith('OBJ-') and i['objectType'] == 'RECORD' and i['inclusion'] != 'EXCLUDED']
    und = collections.Counter(o['fieldUsage']['undetermined']['code'] for o in objs if 'undetermined' in o['fieldUsage'])
    out += [f'欄位統計：範圍內 Record {len(objs)}；已判定 {len(objs) - sum(und.values())}；判不了 {sum(und.values())}'
            + ('（' + '、'.join(f'{k} {v}' for k, v in sorted(und.items())) + '）' if und else '')
            + f'；不建置欄位 {sum(len(x["fields"]) for x in xf)}（{len(xf)} 個 Record）', '']
    return '\n'.join(out)

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    with open(f'{OUT}/00-index.md', 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(render_index())
    for doc in g.DOC_IDS:
        with open(f'{OUT}/{FILE[doc]}', 'w', encoding='utf-8', newline='\n') as fh:
            fh.write(render_doc(doc))
    print('rendered', len(g.DOC_IDS) + 1, 'files')
