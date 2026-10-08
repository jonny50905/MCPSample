# -*- coding: utf-8 -*-
"""產生設計提案的 JSON Schema 草案（2020-12）：共同定義、15 種文件型別、證據登錄。

同一份定義也是 types.md 欄位表的來源（sync_docs.py）。
"""
import json, os, copy

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(BASE, 'schemas')
URN = 'urn:ps-spec:schema:'
C = URN + 'common'

# prefix: (docType, rank, 中文名)
PREFIX_INFO = {
    'GOAL': ('01-overview', 0, '專案目標'),
    'RESP': ('01-overview', 0, '決策責任'),
    'OBJ':  ('01-overview', 0, '舊系統物件'),
    'AI':   ('16-ai-instructions', 0, 'AI 指引條款'),
    'ENT':  ('07-database', 1, '資料實體'),
    'FLD':  ('07-database', 1, '資料欄位'),
    'DRV':  ('07-database', 1, '衍生概念'),
    'XF':   ('07-database', 1, '不建置原生欄位'),
    'ROLE': ('03-roles-permissions', 2, '角色'),
    'PERM': ('03-roles-permissions', 2, '權限'),
    'STATE': ('04-workflow', 3, '狀態'),
    'TRN':  ('04-workflow', 3, '狀態轉移'),
    'FLOW': ('04-workflow', 3, '情境流程'),
    'IF':   ('06-architecture', 4, '介面／批次'),
    'FR':   ('02-functional-requirements', 5, '功能需求'),
    'UI':   ('05-ui', 6, '畫面／元件'),
    'MSG':  ('09-business-logic', 7, '訊息'),
    'BR':   ('09-business-logic', 7, '業務規則'),
    'OP':   ('08-api', 8, '操作契約'),
    'TC':   ('14-testing', 9, '測試案例'),
    'TASK': ('17-tasks', 10, '工作項'),
    'DOD':  ('18-definition-of-done', 11, '完成條件'),
    'Q':    ('90-questions', 12, '問題'),
    'DEC':  ('19-decision-log', 13, '決策'),
}
SPEC_PREFIXES = [p for p, v in PREFIX_INFO.items() if v[1] <= 9 and p != 'AI']

DOC_TYPES = [
    ('01-overview', '01 專案概覽'),
    ('02-functional-requirements', '02 功能需求'),
    ('03-roles-permissions', '03 角色與權限'),
    ('04-workflow', '04 流程與狀態機'),
    ('05-ui', '05 畫面與互動'),
    ('06-architecture', '06 系統架構（技術中立）'),
    ('07-database', '07 資料設計'),
    ('08-api', '08 操作契約（API）'),
    ('09-business-logic', '09 業務邏輯'),
    ('14-testing', '14 測試與驗收'),
    ('16-ai-instructions', '16 AI 實作指引'),
    ('17-tasks', '17 工作拆解與相依'),
    ('18-definition-of-done', '18 完成定義'),
    ('19-decision-log', '19 決策紀錄'),
    ('90-questions', '90 問題清單'),
]
DOC_IDS = [d for d, _ in DOC_TYPES]
DOC_NUM = {d: d.split('-')[0] for d in DOC_IDS}

# ---------- helpers ----------
def R(p):
    return {'$ref': f'{C}#/$defs/ref{p}'}

def D(name):
    return {'$ref': f'{C}#/$defs/{name}'}

def ENUM(vals):
    return {'type': 'string', 'enum': list(vals)}

def ARR(item, mn=None, uniq=False, mx=None):
    s = {'type': 'array', 'items': item}
    if mn is not None:
        s['minItems'] = mn
    if mx is not None:
        s['maxItems'] = mx
    if uniq:
        s['uniqueItems'] = True
    return s

def OBJ(props, req=None, addl=False):
    s = {'type': 'object', 'properties': props,
         'required': list(props) if req is None else req}
    if not addl:
        s['additionalProperties'] = False
    return s

def VS(schema, na=False, unres=False):
    alts = [schema]
    if na:
        alts.append(D('notApplicable'))
    if unres:
        alts.append(D('unresolved'))
    return schema if len(alts) == 1 else {'anyOf': alts}

INT = {'type': 'integer'}
BOOL = {'type': 'boolean'}
TEXT = D('text')
RAW = D('rawText')
SLUG = D('slug')
DATE = D('date')
COND = D('condition')
DCOND = D('dataCondition')
OPERAND = D('operand')
DOPERAND = D('dataOperand')
ASSIGN = D('assignment')
PSNAME = D('psName')

class F:
    def __init__(self, name, schema, req, tlabel, clabel, desc, refs=()):
        self.name, self.schema, self.req = name, schema, req
        self.tlabel, self.clabel, self.desc, self.refs = tlabel, clabel, desc, list(refs)

    def prop(self):
        s = copy.deepcopy(self.schema)
        if isinstance(s, dict):
            s = dict(s)
            s['description'] = self.desc
            if self.refs:
                s['x-ref'] = self.refs
        return s

def NA_U(na, unres):
    t = ''
    if na:
        t += '｜NA'
    if unres:
        t += '｜UNRESOLVED'
    return t

PC_EVENTS = ['FIELD_DEFAULT', 'FIELD_FORMULA', 'ROW_INIT', 'ROW_INSERT', 'ROW_DELETE', 'ROW_SELECT',
             'FIELD_EDIT', 'FIELD_CHANGE', 'PREPOPUP', 'SAVE_EDIT', 'SAVE_PRE_CHANGE', 'WORKFLOW',
             'SAVE_POST_CHANGE', 'SEARCH_INIT', 'SEARCH_SAVE', 'PRE_BUILD', 'POST_BUILD', 'ACTIVATE',
             'BATCH_STEP']
MODES = ['ADD', 'UPDATE_DISPLAY', 'UPDATE_DISPLAY_ALL', 'CORRECTION', 'DISPLAY_ONLY', 'BATCH']
OBJ_TYPES = ['COMPONENT', 'PAGE', 'SUBPAGE', 'SECONDARY_PAGE', 'RECORD', 'PEOPLECODE', 'APP_PACKAGE',
             'AE', 'SQR', 'SQC', 'SQL_OBJECT', 'MESSAGE_SET', 'PERMISSION_LIST', 'ROLE', 'QUERY',
             'IB_SERVICE', 'FILE_LAYOUT', 'COMPONENT_INTERFACE', 'OTHER']
BASIS = ['AUTHORITATIVE_DOC', 'CODE', 'DATA', 'METADATA', 'KNOWLEDGE', 'PROJECT_INPUT',
         'HUMAN_DECISION', 'DERIVED', 'COMPUTED', 'TEMPLATE']
BASIS_NEEDS_EVIDENCE = ['AUTHORITATIVE_DOC', 'CODE', 'DATA', 'METADATA', 'KNOWLEDGE',
                        'PROJECT_INPUT', 'HUMAN_DECISION']
CTX = ['CURRENT_USER_OPRID', 'CURRENT_USER_EMPLID', 'CURRENT_DATE', 'CURRENT_DATETIME',
       'CURRENT_MODE', 'CURRENT_ACTION']
UNARY = ['IS_BLANK', 'IS_NOT_BLANK', 'EXISTS', 'NOT_EXISTS', 'CHANGED']
BINARY = ['EQ', 'NE', 'GT', 'GE', 'LT', 'LE', 'IN', 'NOT_IN', 'BETWEEN', 'HAS_ROLE']
EV_KINDS = ['CHUNK', 'SQL', 'NN', 'WIKI', 'STATUS_DOC', 'PROJECT_INPUT', 'METADATA_RECEIPT',
            'HUMAN_DECISION']
GATE_VALUES = ['PASS', 'FAIL', 'NOT_RUN', 'NOT_APPLICABLE']

PLACEHOLDER_WHOLE = ('^\\s*(UNKNOWN|Unknown|unknown|TODO|TBD|N/A|n/a|NA|NULL|null|NONE|None|none|-+|—+|'
                     '待確認|待補|待查|不明|未知|同上|略|無資料)\\s*$')
PLACEHOLDER_PART = '(TODO|TBD|待確認|待補|同上|依\\s*PeopleSoft\\s*標準|見\\s*NN)'

# ---------- common.schema.json ----------
def operand_def(full):
    alts = [OBJ({'fld': R('FLD')}), OBJ({'drv': R('DRV')})]
    if full:
        alts += [OBJ({'state': R('STATE')}), OBJ({'role': R('ROLE')})]
    alts += [
        OBJ({'const': {'type': 'string'},
             'type': ENUM(['CHAR', 'NUMBER', 'DATE', 'DATETIME', 'BOOLEAN'])}),
        OBJ({'ctx': ENUM(CTX)}),
        OBJ({'param': SLUG}),
    ]
    return {'oneOf': alts}

def predicate_def(opname):
    op = {'$ref': f'#/$defs/{opname}'}
    return {
        'type': 'object',
        'required': ['left', 'op'],
        'properties': {
            'left': op,
            'op': ENUM(UNARY + BINARY),
            'right': {'anyOf': [op, ARR(op, mn=1)]},
        },
        'additionalProperties': False,
        'allOf': [
            {'if': {'properties': {'op': {'enum': UNARY}}}, 'then': {'not': {'required': ['right']}}},
            {'if': {'properties': {'op': {'enum': BINARY}}}, 'then': {'required': ['right']}},
            {'if': {'properties': {'op': {'enum': ['IN', 'NOT_IN']}}},
             'then': {'properties': {'right': {'type': 'array'}}}},
            {'if': {'properties': {'op': {'const': 'BETWEEN'}}},
             'then': {'properties': {'right': {'type': 'array', 'minItems': 2, 'maxItems': 2}}}},
            {'if': {'properties': {'op': {'enum': ['EQ', 'NE', 'GT', 'GE', 'LT', 'LE', 'HAS_ROLE']}}},
             'then': {'properties': {'right': {'type': 'object'}}}},
        ],
    }

def condition_def(selfname, predname):
    me = {'$ref': f'#/$defs/{selfname}'}
    return {'oneOf': [
        {'const': 'ALWAYS'},
        OBJ({'all': ARR(me, mn=2)}),
        OBJ({'any': ARR(me, mn=2)}),
        OBJ({'not': me}),
        {'$ref': f'#/$defs/{predname}'},
    ]}

def build_common():
    defs = {}
    defs['text'] = {
        'type': 'string', 'minLength': 1, 'maxLength': 4000,
        'not': {'anyOf': [{'pattern': PLACEHOLDER_WHOLE}, {'pattern': PLACEHOLDER_PART}]},
        'description': '敘述性文字（繁體中文為主）。不得是空白或填充字（UNKNOWN、TODO、N/A、待確認、同上、見 NN…）。',
    }
    defs['rawText'] = {'type': 'string', 'minLength': 1, 'maxLength': 4000, 'pattern': '\\S',
                       'description': '原文字串（技術名稱、原始訊息、畫面文字、狀態圖標籤），不檢查填充字。'}
    defs['slug'] = {'type': 'string', 'pattern': '^[A-Z][A-Z0-9_]{1,59}$',
                    'description': '大寫 ASCII 代號。'}
    defs['date'] = {'type': 'string', 'pattern': '^\\d{4}-\\d{2}-\\d{2}$'}
    defs['sha256'] = {'type': 'string', 'pattern': '^[0-9a-f]{64}$'}
    defs['componentName'] = {'type': 'string', 'pattern': '^[A-Za-z0-9_][A-Za-z0-9_.$#-]{0,59}$',
                             'description': 'Component 原名（與 ps-spec-author 的輸入規則相同）。'}
    defs['psName'] = {'type': 'string', 'pattern': '^[A-Za-z0-9_$#@][A-Za-z0-9_$#@.:-]*$',
                      'description': 'PeopleSoft 物件原名；PeopleCode 程式用 <物件>.<欄位>.<事件> 形式。'}
    for p in PREFIX_INFO:
        defs[f'ref{p}'] = {'type': 'string', 'pattern': f'^{p}-\\d{{3,}}$',
                           'description': f'參照 {PREFIX_INFO[p][2]}（{p}）。'}
    defs['refSpec'] = {'type': 'string',
                       'pattern': '^(' + '|'.join(SPEC_PREFIXES) + ')-\\d{3,}$',
                       'description': '參照任一規格本體項目（不含 TASK／DOD／Q／DEC／AI）。'}
    defs['evRef'] = {'type': 'string', 'pattern': '^EV-\\d{4,}$', 'description': '證據 ID（evidence.json）。'}
    defs['itemId'] = {'type': 'string',
                      'pattern': '^(' + '|'.join(PREFIX_INFO) + ')-\\d{3,}$'}
    defs['notApplicable'] = {
        'type': 'object', 'required': ['na'],
        'properties': {'na': D('text'), 'evidence': ARR(D('evRef'), mn=1, uniq=True)},
        'additionalProperties': False,
        'description': '經查證的「不適用」：必附理由；主張某行為不存在時須附證據。',
    }
    defs['unresolved'] = {
        'type': 'object', 'required': ['unresolved'],
        'properties': {'unresolved': R('Q')},
        'additionalProperties': False,
        'description': '查不清的事實：指向 90 問題清單的 Q 項目（研究包內為缺口說明，外環轉成 Q）。',
    }
    defs['operand'] = operand_def(True)
    defs['dataOperand'] = operand_def(False)
    defs['predicate'] = predicate_def('operand')
    defs['dataPredicate'] = predicate_def('dataOperand')
    defs['condition'] = condition_def('condition', 'predicate')
    defs['dataCondition'] = condition_def('dataCondition', 'dataPredicate')
    defs['assignment'] = OBJ({
        'field': R('FLD'),
        'value': {'anyOf': [D('operand'), OBJ({'expr': D('text')})]},
        'when': D('condition'),
    }, req=['field', 'value'])
    defs['evidenceItem'] = {
        'type': 'object', 'required': ['id', 'kind', 'locator', 'excerpt'],
        'properties': {
            'id': D('evRef'), 'kind': ENUM(EV_KINDS), 'locator': D('rawText'),
            'excerpt': {'type': 'string', 'minLength': 1, 'pattern': '^[^\\n]*(\\n[^\\n]*){0,4}$',
                        'description': '關鍵摘錄，最多 5 行。'},
            'capturedOn': D('date'),
        },
        'additionalProperties': False,
        'allOf': [
            {'if': {'properties': {'kind': {'const': 'CHUNK'}}},
             'then': {'properties': {'locator': {'pattern': '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'}}}},
            {'if': {'properties': {'kind': {'const': 'SQL'}}},
             'then': {'properties': {'locator': {'pattern': '^\\s*(SELECT|WITH)\\b(?![\\s\\S]*;\\s*\\S)'}}}},
            {'if': {'properties': {'kind': {'enum': ['NN', 'WIKI', 'STATUS_DOC', 'PROJECT_INPUT', 'HUMAN_DECISION']}}},
             'then': {'properties': {'locator': {'pattern': '#L\\d+(-L?\\d+)?$'}}}},
        ],
    }
    defs['itemBase'] = {
        'type': 'object',
        'required': ['id', 'key', 'lifecycle', 'basis', 'certainty', 'evidence'],
        'properties': {
            'id': D('itemId'),
            'key': {'type': 'string', 'minLength': 1, 'maxLength': 200, 'pattern': '^\\S(.*\\S)?$'},
            'lifecycle': ENUM(['ACTIVE', 'RETIRED', 'PENDING']),
            'component': D('componentName'),
            'basis': ENUM(BASIS),
            'certainty': ENUM(['CONFIRMED', 'INFERRED']),
            'inference': D('text'),
            'evidence': ARR(D('evRef'), uniq=True),
            'derivedFrom': ARR(D('refSpec'), mn=1, uniq=True),
        },
        'allOf': [
            {'if': {'required': ['certainty'], 'properties': {'certainty': {'const': 'INFERRED'}}},
             'then': {'required': ['inference']}},
            {'if': {'required': ['basis'], 'properties': {'basis': {'enum': BASIS_NEEDS_EVIDENCE}}},
             'then': {'properties': {'evidence': {'minItems': 1}}}},
            {'if': {'required': ['basis'], 'properties': {'basis': {'const': 'DERIVED'}}},
             'then': {'required': ['derivedFrom']}},
        ],
    }
    defs['envelope'] = {
        'type': 'object',
        'required': ['schemaVersion', 'docType', 'docId', 'jobId', 'revision', 'status', 'title',
                     'summary', 'components', 'dependsOn', 'sources', 'gate', 'openQuestions', 'items'],
        'properties': {
            'schemaVersion': {'const': '1.0'},
            'docType': ENUM(DOC_IDS),
            'docId': {'type': 'string',
                      'pattern': '^clone-[0-9a-f]{16}/(' + '|'.join(DOC_NUM[d] for d in DOC_IDS) + ')$'},
            'jobId': {'type': 'string', 'pattern': '^clone-[0-9a-f]{16}$'},
            'revision': {'type': 'string', 'pattern': '^r\\d{4}$'},
            'status': ENUM(['draft', 'in_review', 'approved', 'superseded']),
            'title': D('rawText'),
            'summary': D('rawText'),
            'components': ARR(D('componentName'), mn=1, uniq=True),
            'dependsOn': ARR(ENUM(DOC_IDS), uniq=True),
            'sources': ARR(OBJ({
                'kind': ENUM(['STATUS_DOC', 'PROJECT_INPUT', 'HUMAN_DECISION', 'KNOWLEDGE',
                              'RESEARCH_RECEIPT', 'FRAMEWORK']),
                'ref': D('rawText'),
                'fingerprint': D('sha256'),
            })),
            'gate': OBJ({k: ENUM(GATE_VALUES) for k in ['L1', 'L2', 'L3', 'L4', 'L5']}),
            'openQuestions': ARR(R('Q'), uniq=True),
            'approval': OBJ({'approvedBy': D('text'), 'approvedOn': D('date'), 'docHash': D('sha256')}),
            'items': {'type': 'array'},
        },
        'allOf': [
            {'if': {'required': ['status'], 'properties': {'status': {'const': 'approved'}}},
             'then': {'required': ['approval']}},
        ],
    }
    return {
        '$schema': 'https://json-schema.org/draft/2020-12/schema',
        '$id': C,
        'title': '共同定義（Layer A）',
        'description': '所有 canonical 文件共用：文件外殼、項目共同欄位、值三態、條件式、證據與 ID 參照。',
        '$defs': defs,
    }

# ---------- item types ----------
ITEM_TYPES = {}   # prefix -> dict(key_pattern, fields, extra_allOf, basis)

def item(prefix, key_pattern, key_label, fields, extra=None, basis=None, evidence_min=None):
    ITEM_TYPES[prefix] = dict(key_pattern=key_pattern, key_label=key_label, fields=fields,
                              extra=extra or [], basis=basis, evidence_min=evidence_min)

FIELD_USAGE = {'oneOf': [
    OBJ({'excluded': OBJ({'count': {'type': 'integer', 'minimum': 1}})}),
    OBJ({'noneExcludable': OBJ({'checkedOn': DATE})}),
    OBJ({'undetermined': OBJ({'code': ENUM(['NO_TABLE', 'EMPTY_TABLE', 'NOT_PROD', 'TIMEOUT',
                                              'QUERY_FAILED', 'CHECK_INCOMPLETE']),
                               'note': TEXT}, req=['code'])}),
]}

item('GOAL', '^GOAL:\\d{2,}$', 'GOAL:<序號>', [
    F('name', TEXT, True, '文字', '', '目標名稱'),
    F('statement', TEXT, True, '文字', '', '目標敘述'),
    F('successCriteria', ARR(TEXT, mn=1), True, '陣列〈文字〉', '≥1', '成功標準（可判定的敘述）'),
], basis=['PROJECT_INPUT'])

item('RESP', '^RESP:[A-Z_]+$', 'RESP:<範圍>', [
    F('area', ENUM(['SPEC_APPROVAL', 'QUESTION_RESOLUTION', 'BUSINESS_RULE_OWNER', 'DATA_OWNER', 'OTHER']),
      True, '列舉', 'SPEC_APPROVAL／QUESTION_RESOLUTION／BUSINESS_RULE_OWNER／DATA_OWNER／OTHER', '負責範圍'),
    F('holder', TEXT, True, '文字', '只寫職稱或單位類別', '負責者（不寫人名）'),
], basis=['PROJECT_INPUT'])

item('OBJ', '^[A-Z_]+:[A-Za-z0-9_$#@.:-]+$', '<物件型別>:<原名>', [
    F('objectType', ENUM(OBJ_TYPES), True, '列舉', '／'.join(OBJ_TYPES), '物件型別'),
    F('objectName', PSNAME, True, '原名', '', 'PeopleSoft 物件原名'),
    F('inclusion', ENUM(['CORE', 'DEPENDENCY', 'EXCLUDED']), True, '列舉', 'CORE／DEPENDENCY／EXCLUDED',
      '範圍分類：入口與功能路徑＝CORE；被核心實際呼叫、讀寫、查值或授權所需＝DEPENDENCY；其餘＝EXCLUDED'),
    F('parent', R('OBJ'), False, 'ID 參照', '', '上層物件（Page 的 Component 等）', ['OBJ']),
    F('usedBy', TEXT, True, '文字', '', '使用鏈：呼叫者、方向與中間鏈（CORE 根寫「使用者指定的根」）'),
    F('usedByRefs', ARR(R('OBJ'), uniq=True), False, '陣列〈ID〉', '', '使用鏈上的物件', ['OBJ']),
    F('condition', VS(TEXT, na=True), True, '文字' + NA_U(True, False), '', '何時使用'),
    F('reason', TEXT, True, '文字', '', '納入／排除理由'),
    F('pcEvent', ENUM(PC_EVENTS), False, '列舉', 'PeopleCode 事件', 'PEOPLECODE 物件的事件'),
    F('fieldUsage', FIELD_USAGE, False, '三擇一物件',
      'excluded{count}／noneExcludable{checkedOn}／undetermined{code}',
      '原生欄位判定結論；type RECORD 且 CORE／DEPENDENCY 時必填'),
], extra=[{'if': {'required': ['objectType', 'inclusion'],
                  'properties': {'objectType': {'const': 'RECORD'},
                                 'inclusion': {'enum': ['CORE', 'DEPENDENCY']}}},
           'then': {'required': ['fieldUsage']},
           'else': {'not': {'required': ['fieldUsage']}}}])

item('AI', '^AI:\\d{2,}$', 'AI:<序號>', [
    F('category', ENUM(['READING', 'SCOPE', 'DATA', 'LOGIC', 'UNKNOWN_HANDLING', 'CHANGE_DISCIPLINE',
                        'TRACEABILITY', 'LANGUAGE']), True, '列舉',
      'READING／SCOPE／DATA／LOGIC／UNKNOWN_HANDLING／CHANGE_DISCIPLINE／TRACEABILITY／LANGUAGE', '條款類別'),
    F('clause', TEXT, True, '文字', '', '條款內容'),
], basis=['TEMPLATE'])

item('ENT', '^[A-Z0-9_$#@]+$', '<Record 原名>', [
    F('record', R('OBJ'), True, 'ID 參照', 'OBJ 的 RECORD', '對應的 Record', ['OBJ']),
    F('name', TEXT, True, '文字', '', '業務名稱'),
    F('businessMeaning', TEXT, True, '文字', '', '這份資料代表什麼'),
    F('storageKind', ENUM(['SQL_TABLE', 'SQL_VIEW', 'DYNAMIC_VIEW', 'DERIVED_WORK', 'SUBRECORD',
                           'TEMP_TABLE', 'QUERY_VIEW', 'OTHER_LOGICAL']), True, '列舉',
      'SQL_TABLE／SQL_VIEW／DYNAMIC_VIEW／DERIVED_WORK／SUBRECORD／TEMP_TABLE／QUERY_VIEW／OTHER_LOGICAL', '儲存型態'),
    F('physicalName', VS(RAW, na=True), True, '原名' + NA_U(True, False), '', '實體表名（DERIVED_WORK 等寫 NA）'),
    F('keys', VS(ARR(R('FLD'), mn=1), na=True), True, '陣列〈ID〉' + NA_U(True, False), '有序', '邏輯鍵欄位（依序）', ['FLD']),
    F('effectiveDating', {
        'type': 'object', 'required': ['kind'],
        'properties': {'kind': ENUM(['NONE', 'EFFDT', 'EFFDT_EFFSEQ']),
                       'currentRow': OBJ({'asOf': DOPERAND, 'effStatusActiveOnly': BOOL})},
        'additionalProperties': False,
        'allOf': [{'if': {'properties': {'kind': {'enum': ['EFFDT', 'EFFDT_EFFSEQ']}}},
                   'then': {'required': ['currentRow']}}]},
      True, '物件', 'kind＝NONE／EFFDT／EFFDT_EFFSEQ；有效日時必附 currentRow',
      '有效日規則：目前有效列＝基準日當天或之前最大 EFFDT（再取最大 EFFSEQ），可限定有效狀態', ['FLD', 'DRV']),
    F('parent', OBJ({'entity': R('ENT'), 'keyMap': ARR(OBJ({'child': R('FLD'), 'parent': R('FLD')}), mn=1)}),
      False, '物件', '', '父子關係與鍵對應', ['ENT', 'FLD']),
])

XLAT_ENTRY = OBJ({'stored': RAW, 'label': RAW, 'active': BOOL,
                  'dataPresence': ENUM(['HAS_DATA', 'NO_DATA', 'NOT_CHECKED'])})
item('FLD', '^[A-Z0-9_$#@]+\\.[A-Z0-9_$#@]+$', '<Record>.<欄位>', [
    F('entity', R('ENT'), True, 'ID 參照', '', '所屬實體', ['ENT']),
    F('fieldName', {'type': 'string', 'pattern': '^[A-Z0-9_$#@]+$'}, True, '原名', '', '欄位原名'),
    F('label', TEXT, True, '文字', '', '業務標籤'),
    F('dataType', ENUM(['CHAR', 'LONG_CHAR', 'NUMBER', 'SIGNED_NUMBER', 'DATE', 'DATETIME', 'TIME',
                        'IMAGE', 'ATTACHMENT']), True, '列舉',
      'CHAR／LONG_CHAR／NUMBER／SIGNED_NUMBER／DATE／DATETIME／TIME／IMAGE／ATTACHMENT', '型別'),
    F('length', VS({'type': 'integer', 'minimum': 1}, na=True), True, '整數' + NA_U(True, False), '', '長度'),
    F('decimals', {'type': 'integer', 'minimum': 0}, False, '整數', 'NUMBER／SIGNED_NUMBER', '小數位數'),
    F('required', ENUM(['ALWAYS', 'CONDITIONAL', 'NO']), True, '列舉', 'ALWAYS／CONDITIONAL／NO',
      'Record 層必填；CONDITIONAL 的條件寫在 09 的業務規則'),
    F('default', VS(DOPERAND, na=True), True, '運算元' + NA_U(True, False), '', 'Record 層預設值', ['FLD', 'DRV']),
    F('valueDomain', {'oneOf': [
        OBJ({'xlat': ARR(XLAT_ENTRY, mn=1)}),
        OBJ({'prompt': OBJ({'entity': R('ENT'), 'keyField': R('FLD'), 'filter': DCOND}, req=['entity', 'keyField'])}),
        OBJ({'range': OBJ({'min': RAW, 'max': RAW}, req=[])}),
        OBJ({'free': {'const': True}}),
        OBJ({'derived': R('DRV')}),
    ]}, True, '五擇一物件', 'xlat[]／prompt{}／range{}／free／derived',
      '值域；狀態欄位的 xlat 只列狀態圖上的代碼', ['ENT', 'FLD', 'DRV']),
    F('keyRoles', ARR(ENUM(['KEY', 'DUP_ORDER_KEY', 'SEARCH_KEY', 'ALT_SEARCH_KEY', 'LIST_BOX_ITEM']), uniq=True),
      True, '陣列〈列舉〉', 'KEY／DUP_ORDER_KEY／SEARCH_KEY／ALT_SEARCH_KEY／LIST_BOX_ITEM；可空', '鍵屬性'),
    F('relations', ARR(OBJ({'target': R('FLD'), 'kind': ENUM(['LOGICAL_FK', 'PARENT_KEY', 'PROMPT_LOOKUP']),
                            'note': TEXT}, req=['target', 'kind'])), False, '陣列〈物件〉', '', '與其他欄位的關聯', ['FLD']),
    F('sensitivity', ENUM(['NONE', 'PERSONAL', 'CONFIDENTIAL']), True, '列舉', 'NONE／PERSONAL／CONFIDENTIAL', '敏感分類'),
    F('usageEvidence', ENUM(['DATA_HAS_VALUE', 'CODE_REFERENCED', 'METADATA_ONLY', 'NOT_CHECKED']), True, '列舉',
      'DATA_HAS_VALUE／CODE_REFERENCED／METADATA_ONLY／NOT_CHECKED', '使用證據等級（供排優先序，不代表排除）'),
])

item('DRV', '^[A-Z][A-Z0-9_]{1,59}$', '<代號>', [
    F('name', TEXT, True, '文字', '', '概念名稱（例：申請人的直屬主管）'),
    F('meaning', TEXT, True, '文字', '', '業務意義'),
    F('inputs', ARR(OBJ({'name': SLUG, 'from': DOPERAND})), True, '陣列〈物件〉', '可空', '輸入參數與來源', ['FLD', 'DRV']),
    F('resultType', ENUM(['PERSON_ID', 'CODE', 'NUMBER', 'DATE', 'TEXT', 'BOOLEAN', 'ROW_SET']), True, '列舉',
      'PERSON_ID／CODE／NUMBER／DATE／TEXT／BOOLEAN／ROW_SET', '結果型別'),
    F('resolution', OBJ({
        'sources': ARR(R('ENT'), mn=1, uniq=True),
        'joins': ARR(OBJ({'left': R('FLD'), 'right': DOPERAND})),
        'filter': DCOND,
        'effectiveDating': ARR(OBJ({'entity': R('ENT'), 'rule': ENUM(['CURRENT_ROW', 'AS_OF', 'NONE']),
                                    'asOf': DOPERAND, 'effStatusActiveOnly': BOOL},
                                   req=['entity', 'rule', 'effStatusActiveOnly'])),
        'pick': R('FLD'),
        'tieBreak': VS(TEXT, na=True),
    }), True, '物件', 'sources≥1；有效日實體須各有一條 effectiveDating', '查找規則：從哪些表、怎麼串、篩選、取哪一欄',
      ['ENT', 'FLD', 'DRV']),
    F('whenNotFound', {'type': 'object', 'required': ['result', 'note'],
                       'properties': {'result': ENUM(['EMPTY', 'FALLBACK']), 'fallback': R('DRV'), 'note': TEXT},
                       'additionalProperties': False,
                       'allOf': [{'if': {'properties': {'result': {'const': 'FALLBACK'}}},
                                  'then': {'required': ['fallback']}}]},
      True, '物件', 'result＝EMPTY／FALLBACK', '查無結果時的行為（訊息與阻擋寫在 09）', ['DRV']),
    F('whenMultiple', OBJ({'rule': ENUM(['UNIQUE_BY_KEY', 'FIRST_BY_ORDER', 'ALL_ROWS']),
                           'orderBy': ARR(R('FLD'), mn=1), 'note': TEXT}, req=['rule', 'note']),
      True, '物件', 'rule＝UNIQUE_BY_KEY／FIRST_BY_ORDER／ALL_ROWS', '多筆時的取法', ['FLD']),
    F('implementedAt', ARR(R('OBJ'), mn=1, uniq=True), True, '陣列〈ID〉', '≥1', '原系統實作位置', ['OBJ']),
])

item('XF', '^[A-Z0-9_$#@]+$', '<Record 原名>', [
    F('entity', R('ENT'), True, 'ID 參照', '', '所屬實體', ['ENT']),
    F('fields', ARR({'type': 'string', 'pattern': '^[A-Z0-9_$#@]+$'}, mn=1, uniq=True), True,
      '陣列〈原名〉', '≥1', '判定無用的欄位'),
    F('dataCheck', {'type': 'string', 'pattern': '^非預設 0 筆（全表非空，查詢日 \\d{4}-\\d{2}-\\d{2}）$'}, True,
      '固定格式', '非預設 0 筆（全表非空，查詢日 YYYY-MM-DD）', '資料剖析結論'),
    F('codeChecks', OBJ({'a': TEXT, 'b': TEXT, 'c': TEXT}), True, '物件', 'a／b／c 三種查法都要有結果',
      '程式面查法結果'),
], evidence_min=2)

item('ROLE', '^(ROLE|PERMISSION_LIST|DYNAMIC_ROLE|OTHER):[A-Za-z0-9_$#@.-]+$', '<主體型別>:<原名>', [
    F('principalType', ENUM(['ROLE', 'PERMISSION_LIST', 'DYNAMIC_ROLE', 'OTHER']), True, '列舉',
      'ROLE／PERMISSION_LIST／DYNAMIC_ROLE／OTHER', '主體型別'),
    F('object', R('OBJ'), True, 'ID 參照', '', '對應的原系統物件', ['OBJ']),
    F('name', TEXT, True, '文字', '', '業務名稱'),
    F('membership', {'type': 'object', 'required': ['kind', 'note'],
                     'properties': {'kind': ENUM(['STATIC_ASSIGNMENT', 'DYNAMIC_RULE']), 'rule': R('DRV'), 'note': TEXT},
                     'additionalProperties': False,
                     'allOf': [{'if': {'properties': {'kind': {'const': 'DYNAMIC_RULE'}}},
                                'then': {'required': ['rule']}}]},
      True, '物件', 'kind＝STATIC_ASSIGNMENT／DYNAMIC_RULE（後者必附 DRV）', '使用者如何取得此角色', ['DRV']),
])

item('PERM', '^[A-Z_]+:[A-Za-z0-9_$#@.-]+>[A-Z_]+:[A-Za-z0-9_$#@.-]+$', '<主體鍵>><資源鍵>', [
    F('principal', R('ROLE'), True, 'ID 參照', '', '權限主體', ['ROLE']),
    F('resource', R('OBJ'), True, 'ID 參照', '', '受控資源（Component／Page／程序）', ['OBJ']),
    F('actions', ARR(ENUM(['ADD', 'UPDATE_DISPLAY', 'UPDATE_DISPLAY_ALL', 'CORRECTION', 'DISPLAY_ONLY',
                           'RUN_PROCESS', 'VIEW_ONLY']), mn=1, uniq=True), True, '陣列〈列舉〉',
      'ADD／UPDATE_DISPLAY／UPDATE_DISPLAY_ALL／CORRECTION／DISPLAY_ONLY／RUN_PROCESS／VIEW_ONLY', '允許的動作'),
    F('dataScope', {'oneOf': [{'const': 'ALL_ROWS'}, OBJ({'condition': DCOND, 'note': TEXT}, req=['condition'])]},
      True, 'ALL_ROWS｜物件', 'condition 只能用資料運算元', '資料範圍（列層級）', ['FLD', 'DRV']),
    F('denial', OBJ({'effect': ENUM(['NOT_IN_NAVIGATION', 'ACCESS_DENIED_MESSAGE', 'ROWS_FILTERED',
                                     'CONTROL_HIDDEN', 'CONTROL_DISABLED']), 'note': TEXT}, req=['effect']),
      True, '物件', 'NOT_IN_NAVIGATION／ACCESS_DENIED_MESSAGE／ROWS_FILTERED／CONTROL_HIDDEN／CONTROL_DISABLED', '無權時的效果'),
    F('enforcement', ENUM(['COMPONENT_SECURITY', 'ROW_LEVEL_SECURITY', 'PEOPLECODE_CHECK', 'PAGE_DISPLAY_CONTROL']),
      True, '列舉', 'COMPONENT_SECURITY／ROW_LEVEL_SECURITY／PEOPLECODE_CHECK／PAGE_DISPLAY_CONTROL', '檢查位置'),
])

STATE_OR_INITIAL = {'anyOf': [R('STATE'), {'const': 'INITIAL'}]}
item('STATE', '^[A-Z][A-Z0-9_]*:[^\\s:]+$', '<狀態實體>:<狀態碼>', [
    F('entityKey', SLUG, True, '代號', '', '狀態實體（輸入檔的狀態圖分組）'),
    F('stateKind', ENUM(['SIMPLE', 'COMPOSITE']), True, '列舉', 'SIMPLE／COMPOSITE', '狀態種類'),
    F('code', RAW, False, '原文', 'SIMPLE 必填', '狀態碼（儲存值）'),
    F('name', RAW, True, '原文', '', '狀態圖上的名稱'),
    F('parent', R('STATE'), False, 'ID 參照', '', '所屬複合狀態', ['STATE']),
    F('binding', R('FLD'), False, 'ID 參照', 'SIMPLE 必填', '保存狀態碼的欄位', ['FLD']),
    F('domainLabel', VS(RAW, na=True), False, '原文' + NA_U(True, False), 'SIMPLE 必填', '值域中的顯示文字（Translate／對照表）'),
    F('isInitialTarget', BOOL, True, '布林', '', '是否由 [*] 進入（新建）'),
    F('isFinal', BOOL, True, '布林', '', '是否為終點（→[*]）'),
    F('dataPresence', ENUM(['HAS_DATA', 'NO_DATA', 'NOT_CHECKED']), False, '列舉', 'SIMPLE 必填',
      'PROD 是否有此狀態碼的資料'),
], extra=[{'if': {'required': ['stateKind'], 'properties': {'stateKind': {'const': 'SIMPLE'}}},
           'then': {'required': ['code', 'binding', 'domainLabel', 'dataPresence']}}],
   basis=['AUTHORITATIVE_DOC'])

item('TRN', '^[A-Z][A-Z0-9_]*:[^\\s>]+>[^\\s>]+$', '<狀態實體>:<起>><迄>（新建的起點寫 *）', [
    F('entityKey', SLUG, True, '代號', '', '狀態實體'),
    F('from', STATE_OR_INITIAL, True, 'ID 參照｜INITIAL', '', '起始狀態（新建為 INITIAL）', ['STATE']),
    F('to', R('STATE'), True, 'ID 參照', '', '目標狀態', ['STATE']),
    F('via', ARR(RAW, mn=1), False, '陣列〈原文〉', '', '收合掉的 choice／fork／join 節點'),
    F('trigger', VS(OBJ({'kind': ENUM(['USER_ACTION', 'BATCH', 'SYSTEM_EVENT', 'INTERFACE']),
                         'object': R('OBJ'), 'action': RAW, 'event': ENUM(PC_EVENTS)}, req=['kind', 'object', 'action']),
                     unres=True), True, '物件' + NA_U(False, True),
      'kind＝USER_ACTION／BATCH／SYSTEM_EVENT／INTERFACE', '觸發方式、所在物件與動作原名', ['OBJ']),
    F('actor', VS(COND, na=True, unres=True), True, '條件式' + NA_U(True, True), '非 BATCH 觸發不得 NA（schema）',
      '誰能觸發（角色、資格的判定方式）；只有批次觸發可以是 NA', ['FLD', 'DRV', 'STATE', 'ROLE']),
    F('guard', VS(COND, na=True, unres=True), True, '條件式' + NA_U(True, True), '有 via（經 choice 收合）時不得 NA（schema）',
      '轉移條件（選擇此目標的條件）', ['FLD', 'DRV', 'STATE', 'ROLE']),
    F('writes', VS(ARR(ASSIGN, mn=1), unres=True), True, '陣列〈指派〉' + NA_U(False, True),
      '必含狀態欄位＝目標狀態碼', '轉移時寫入的欄位與值', ['FLD', 'DRV', 'STATE', 'ROLE']),
    F('sideEffects', VS(ARR(OBJ({'description': TEXT, 'fields': ARR(R('FLD'), uniq=True)}), mn=1), na=True),
      True, '陣列〈物件〉' + NA_U(True, False), '', '其他副作用（通知、介面等於 06／09 反查）', ['FLD']),
    F('implementedAt', VS(ARR(OBJ({'object': R('OBJ'), 'event': RAW}), mn=1), unres=True), True,
      '陣列〈物件〉' + NA_U(False, True), '找不到＝UNRESOLVED（DIAGRAM_EDGE_UNIMPLEMENTED）', '原系統實作位置', ['OBJ']),
    F('reentry', VS(TEXT, unres=True), True, '文字' + NA_U(False, True), '', '重複觸發或同時操作時的行為'),
], extra=[{'if': {'required': ['via']}, 'then': {'properties': {'guard': {'not': {'required': ['na']}}}}},
          {'if': {'required': ['trigger'], 'properties': {'trigger': {'required': ['kind'],
                                                                      'properties': {'kind': {'not': {'const': 'BATCH'}}}}}},
           'then': {'properties': {'actor': {'not': {'required': ['na']}}}}}],
   basis=['AUTHORITATIVE_DOC'])

item('FLOW', '^[A-Z][A-Z0-9_]*:\\S.*$', '<狀態實體>:<情境類型原文>', [
    F('entityKey', SLUG, True, '代號', '', '狀態實體'),
    F('scenarioType', RAW, True, '原文', 'flowchart 邊標籤原文', '情境類型'),
    F('narrative', TEXT, True, '文字', '', '情境說明'),
    F('steps', ARR(OBJ({'seq': {'type': 'integer', 'minimum': 1}, 'transition': R('TRN'), 'description': TEXT}), mn=1),
      True, '陣列〈物件〉', '每條同標籤的邊恰一步', '情境步驟（依拓撲順序）', ['TRN']),
    F('entryStates', ARR(STATE_OR_INITIAL, mn=1, uniq=True), True, '陣列〈ID｜INITIAL〉', '≥1', '進入此情境的狀態', ['STATE']),
    F('exitStates', ARR(R('STATE'), mn=1, uniq=True), True, '陣列〈ID〉', '≥1', '離開此情境的狀態', ['STATE']),
    F('preconditions', VS(COND, na=True), True, '條件式' + NA_U(True, False), '', '前置條件', ['FLD', 'DRV', 'STATE', 'ROLE']),
    F('exceptions', VS(TEXT, na=True), True, '文字' + NA_U(True, False), '', '例外與中斷'),
], basis=['AUTHORITATIVE_DOC'])

item('IF', '^[A-Z_]+:[A-Za-z0-9_$#@.-]+$', '<物件型別>:<原名>', [
    F('ifType', ENUM(['BATCH_AE', 'BATCH_SQR', 'IB_SERVICE', 'FILE_IN', 'FILE_OUT', 'EMAIL', 'NOTIFICATION', 'OTHER']),
      True, '列舉', 'BATCH_AE／BATCH_SQR／IB_SERVICE／FILE_IN／FILE_OUT／EMAIL／NOTIFICATION／OTHER', '介面型別'),
    F('object', R('OBJ'), True, 'ID 參照', '', '原系統物件', ['OBJ']),
    F('name', TEXT, True, '文字', '', '業務名稱'),
    F('direction', ENUM(['INBOUND', 'OUTBOUND', 'INTERNAL']), True, '列舉', 'INBOUND／OUTBOUND／INTERNAL', '方向'),
    F('trigger', {'type': 'object', 'required': ['kind', 'note'],
                  'properties': {'kind': ENUM(['SCHEDULE', 'ON_DEMAND', 'ON_TRANSITION', 'ON_SAVE', 'EVENT']),
                                 'transitions': ARR(R('TRN'), mn=1, uniq=True), 'note': TEXT},
                  'additionalProperties': False,
                  'allOf': [{'if': {'properties': {'kind': {'const': 'ON_TRANSITION'}}},
                             'then': {'required': ['transitions']}}]},
      True, '物件', 'kind＝SCHEDULE／ON_DEMAND／ON_TRANSITION／ON_SAVE／EVENT', '觸發方式', ['TRN']),
    F('performs', ARR(R('TRN'), uniq=True), True, '陣列〈ID〉', '可空', '本介面執行的狀態轉移', ['TRN']),
    F('reads', ARR(R('FLD'), uniq=True), True, '陣列〈ID〉', '可空', '讀取欄位', ['FLD']),
    F('writes', ARR(R('FLD'), uniq=True), True, '陣列〈ID〉', '可空', '寫入欄位', ['FLD']),
    F('parameters', VS(ARR(OBJ({'name': RAW, 'source': {'anyOf': [DOPERAND, OBJ({'expr': TEXT})]}}), mn=1), na=True),
      True, '陣列〈物件〉' + NA_U(True, False), '', '參數／Run Control', ['FLD', 'DRV']),
    F('format', VS(OBJ({'layout': TEXT, 'encoding': RAW,
                        'fields': ARR(OBJ({'seq': {'type': 'integer', 'minimum': 1}, 'name': RAW, 'field': R('FLD'),
                                           'length': {'type': 'integer', 'minimum': 1}, 'format': RAW},
                                          req=['seq', 'name']), mn=1)}), na=True),
      True, '物件' + NA_U(True, False), '檔案型才需要', '格式、編碼、欄位順序', ['FLD']),
    F('errorHandling', VS(TEXT, unres=True), True, '文字' + NA_U(False, True), '', '錯誤處理'),
    F('retry', VS(TEXT, na=True, unres=True), True, '文字' + NA_U(True, True), '', '重試'),
    F('idempotency', VS(TEXT, unres=True), True, '文字' + NA_U(False, True), '', '重送／重複執行的結果'),
])

ACTOR_OPERAND = {'oneOf': [OBJ({'role': R('ROLE')}), OBJ({'drv': R('DRV')}), OBJ({'ctx': ENUM(CTX)})]}
item('FR', '^[A-Za-z0-9_$#.-]+:[A-Z][A-Z0-9_]*$', '<Component>:<操作代號>', [
    F('name', TEXT, True, '文字', '', '功能名稱'),
    F('description', TEXT, True, '文字', '', '功能說明'),
    F('frKind', ENUM(['TRANSITION', 'MAINTAIN', 'QUERY', 'BATCH', 'OUTPUT']), True, '列舉',
      'TRANSITION／MAINTAIN／QUERY／BATCH／OUTPUT', '功能種類'),
    F('entry', OBJ({'object': R('OBJ'), 'modes': ARR(ENUM(MODES), mn=1, uniq=True)}), True, '物件', '',
      '入口物件與模式', ['OBJ']),
    F('actors', ARR(ACTOR_OPERAND, mn=1), True, '陣列〈角色｜衍生概念｜情境〉', '≥1', '操作者摘要（判定細節在 04 的 actor）',
      ['ROLE', 'DRV']),
    F('realizes', ARR(R('TRN'), uniq=True), True, '陣列〈ID〉', 'TRANSITION 時≥1，其他種類必須為空', '實現的狀態轉移', ['TRN']),
    F('preconditions', VS(COND, na=True), True, '條件式' + NA_U(True, False), '', '前置條件', ['FLD', 'DRV', 'STATE', 'ROLE']),
    F('outcome', TEXT, True, '文字', '', '完成後的結果'),
    F('priority', ENUM(['MUST', 'SHOULD', 'COULD']), True, '列舉', 'MUST／SHOULD／COULD（預設 MUST）', '優先序'),
], extra=[{'if': {'required': ['frKind'], 'properties': {'frKind': {'const': 'TRANSITION'}}},
           'then': {'properties': {'realizes': {'minItems': 1}}},
           'else': {'properties': {'realizes': {'maxItems': 0}}}}])

UI_FIELDS = [
    F('uiKind', ENUM(['SCREEN', 'CONTROL']), True, '列舉', 'SCREEN／CONTROL', '畫面或元件'),
    F('usedBy', ARR(R('FR'), mn=1, uniq=True), True, '陣列〈ID〉', '≥1', '使用此畫面／元件的功能', ['FR']),
    # SCREEN
    F('component', R('OBJ'), False, 'ID 參照', 'SCREEN 必填', 'Component', ['OBJ']),
    F('page', R('OBJ'), False, 'ID 參照', 'SCREEN 必填', 'Page', ['OBJ']),
    F('title', RAW, False, '原文', 'SCREEN 必填', '畫面標題'),
    F('pageRole', ENUM(['MAIN', 'SUBPAGE', 'SECONDARY', 'SEARCH', 'MODAL']), False, '列舉',
      'MAIN／SUBPAGE／SECONDARY／SEARCH／MODAL；SCREEN 必填', '頁面角色'),
    F('modes', ARR(ENUM(MODES), mn=1, uniq=True), False, '陣列〈列舉〉', 'SCREEN 必填', '可用模式'),
    F('searchKeys', VS(ARR(R('FLD'), mn=1), na=True), False, '陣列〈ID〉' + NA_U(True, False), 'SCREEN 必填', '查詢鍵', ['FLD']),
    F('regions', ARR(OBJ({'key': SLUG, 'label': VS(RAW, na=True), 'scrollLevel': {'type': 'integer', 'minimum': 0, 'maximum': 3},
                          'parentRegion': SLUG, 'repeating': BOOL}, req=['key', 'label', 'scrollLevel', 'repeating']), mn=1),
      False, '陣列〈物件〉', 'SCREEN 必填', '區塊與 scroll level'),
    # CONTROL
    F('screen', R('UI'), False, 'ID 參照', 'CONTROL 必填', '所屬畫面', ['UI']),
    F('region', SLUG, False, '代號', 'CONTROL 必填', '所屬區塊'),
    F('controlType', ENUM(['EDIT_BOX', 'DROP_DOWN', 'CHECKBOX', 'RADIO', 'PROMPT', 'LONG_EDIT', 'DATE', 'PUSH_BUTTON',
                           'HYPERLINK', 'GRID', 'SCROLL_AREA', 'STATIC_TEXT', 'IMAGE', 'ATTACHMENT', 'OTHER']),
      False, '列舉', 'EDIT_BOX／DROP_DOWN／…／PUSH_BUTTON…；CONTROL 必填', '控制項型別'),
    F('binding', VS({'oneOf': [OBJ({'fld': R('FLD')}), OBJ({'drv': R('DRV')})]}, na=True), False,
      '物件' + NA_U(True, False), 'CONTROL 必填', '綁定的欄位或衍生值（按鈕寫 NA）', ['FLD', 'DRV']),
    F('label', VS(RAW, na=True), False, '原文' + NA_U(True, False), 'CONTROL 必填', '畫面文字'),
    F('presence', ENUM(['VISIBLE', 'CONDITIONAL', 'HIDDEN_TECHNICAL']), False, '列舉',
      'VISIBLE／CONDITIONAL／HIDDEN_TECHNICAL；CONTROL 必填', '出現方式'),
    F('visibility', {'anyOf': [{'const': 'ALWAYS'}, COND]}, False, 'ALWAYS｜條件式', 'CONTROL 必填',
      '顯示條件', ['FLD', 'DRV', 'STATE', 'ROLE']),
    F('editability', {'anyOf': [{'const': 'ALWAYS'}, {'const': 'NEVER'}, COND]}, False, 'ALWAYS｜NEVER｜條件式',
      'CONTROL 必填', '可編輯條件', ['FLD', 'DRV', 'STATE', 'ROLE']),
    F('options', ARR(OBJ({'label': RAW, 'stored': RAW}), mn=1), False, '陣列〈物件〉', '儲存值須屬於欄位值域',
      '選項：顯示文字↔儲存值'),
    F('valueSource', OBJ({'kind': ENUM(['XLAT', 'PROMPT', 'STATIC', 'DERIVED', 'FREE', 'NONE']),
                          'prompt': OBJ({'entity': R('ENT'), 'filter': COND}, req=['entity'])}, req=['kind']),
      False, '物件', 'CONTROL 必填', '值來源', ['ENT', 'FLD', 'DRV', 'STATE', 'ROLE']),
    F('displayDefault', VS(OPERAND, na=True), False, '運算元' + NA_U(True, False), 'CONTROL 必填', '畫面初值（寫入資料的預設在 09）',
      ['FLD', 'DRV', 'STATE', 'ROLE']),
    F('interactions', ARR(OBJ({'event': ENUM(['FIELD_CHANGE', 'PUSH_BUTTON', 'ROW_INSERT', 'ROW_DELETE', 'PAGE_ACTIVATE', 'PROMPT_SELECT']),
                               'effect': ENUM(['REFRESH', 'NAVIGATE', 'RECALCULATE', 'OPEN_MODAL', 'INVOKE_FUNCTION']),
                               'targets': ARR(R('UI'), uniq=True), 'note': TEXT})), False, '陣列〈物件〉', '',
      '純畫面互動（會拒絕或寫資料的邏輯寫在 09）', ['UI']),
]
item('UI', '^[A-Za-z0-9_$#.-]+\\.[A-Z0-9_$#@]+(\\.[A-Z0-9_$#@]+\\.[A-Z0-9_$#@]+|\\.@[A-Z0-9_]+)?$',
     '<Component>.<Page>[.<Record>.<欄位>]', UI_FIELDS,
     extra=[{'if': {'required': ['uiKind'], 'properties': {'uiKind': {'const': 'SCREEN'}}},
             'then': {'required': ['component', 'page', 'title', 'pageRole', 'modes', 'searchKeys', 'regions']}},
            {'if': {'required': ['uiKind'], 'properties': {'uiKind': {'const': 'CONTROL'}}},
             'then': {'required': ['screen', 'region', 'controlType', 'binding', 'label', 'presence', 'visibility',
                                   'editability', 'valueSource', 'displayDefault']}},
            {'if': {'required': ['presence'], 'properties': {'presence': {'const': 'CONDITIONAL'}}},
             'then': {'properties': {'visibility': {'not': {'const': 'ALWAYS'}}}}}])

item('MSG', '^(\\d+,\\d+|TEXT:[0-9a-f]{8})$', '<訊息集>,<編號>｜TEXT:<雜湊>', [
    F('messageSet', VS({'type': 'integer', 'minimum': 1}, na=True), True, '整數' + NA_U(True, False), '寫死字串寫 NA', '訊息集'),
    F('messageNumber', VS({'type': 'integer', 'minimum': 1}, na=True), True, '整數' + NA_U(True, False), '', '訊息編號'),
    F('text', RAW, True, '原文', '', '訊息原文'),
    F('severity', ENUM(['ERROR', 'WARNING', 'MESSAGE', 'CANCEL']), True, '列舉', 'ERROR／WARNING／MESSAGE／CANCEL', '嚴重度'),
    F('parameters', ARR(TEXT, mn=1), False, '陣列〈文字〉', '', '參數意義（依序）'),
])

item('BR', '^[A-Za-z0-9_$#@.]+:[A-Z][A-Z0-9_]*$', '<實作位置>:<規則代號>', [
    F('name', TEXT, True, '文字', '', '規則名稱'),
    F('brKind', ENUM(['VALIDATION', 'CALCULATION', 'DEFAULTING', 'DERIVATION', 'AUTHORIZATION', 'SIDE_EFFECT', 'CONSTRAINT']),
      True, '列舉', 'VALIDATION／CALCULATION／DEFAULTING／DERIVATION／AUTHORIZATION／SIDE_EFFECT／CONSTRAINT', '規則種類'),
    F('appliesTo', ARR(R('FR'), mn=1, uniq=True), True, '陣列〈ID〉', '≥1', '適用的功能', ['FR']),
    F('trigger', OBJ({'event': ENUM(PC_EVENTS), 'control': R('UI'), 'transitions': ARR(R('TRN'), mn=1, uniq=True),
                      'modes': ARR(ENUM(MODES), mn=1, uniq=True)}, req=['event']), True, '物件', 'event 必填',
      '觸發事件、元件、轉移、模式', ['UI', 'TRN']),
    F('condition', COND, True, '條件式', '無條件寫 ALWAYS', '精確條件', ['FLD', 'DRV', 'STATE', 'ROLE']),
    F('action', {'type': 'object', 'required': ['kind'],
                 'properties': {'kind': ENUM(['REJECT', 'WARN', 'SET_VALUE', 'CLEAR_VALUE', 'INVOKE_INTERFACE', 'NOTIFY']),
                                'message': R('MSG'), 'assignments': ARR(ASSIGN, mn=1), 'interface': R('IF')},
                 'additionalProperties': False,
                 'allOf': [{'if': {'properties': {'kind': {'enum': ['REJECT', 'WARN']}}}, 'then': {'required': ['message']}},
                           {'if': {'properties': {'kind': {'enum': ['SET_VALUE', 'CLEAR_VALUE']}}}, 'then': {'required': ['assignments']}},
                           {'if': {'properties': {'kind': {'enum': ['INVOKE_INTERFACE', 'NOTIFY']}}}, 'then': {'required': ['interface']}}]},
      True, '物件', 'REJECT／WARN 必附 message；SET_VALUE 必附 assignments；INVOKE_INTERFACE／NOTIFY 必附 interface',
      '動作', ['MSG', 'FLD', 'DRV', 'STATE', 'ROLE', 'IF']),
    F('order', VS({'type': 'integer', 'minimum': 1}, unres=True), True, '整數' + NA_U(False, True), '', '同一觸發點內的執行順序'),
    F('boundaries', VS(TEXT, na=True), True, '文字' + NA_U(True, False), '', 'NULL／空白／0／日期邊界的處理'),
    F('modeDifferences', VS(TEXT, na=True), True, '文字' + NA_U(True, False), '', '不同模式或角色的差異'),
    F('implementedAt', OBJ({'object': R('OBJ'), 'event': RAW}), True, '物件', '', '原系統實作位置', ['OBJ']),
])

item('OP', '^[A-Za-z0-9_$#.-]+:[A-Z][A-Z0-9_]*:[A-Z][A-Z0-9_]*$', '<FR 鍵>:<操作代號>', [
    F('fr', R('FR'), True, 'ID 參照', '', '所屬功能', ['FR']),
    F('name', TEXT, True, '文字', '', '操作名稱'),
    F('opKind', ENUM(['LOAD', 'SEARCH', 'CREATE', 'UPDATE', 'TRANSITION', 'DELETE', 'LOOKUP', 'BATCH_RUN']), True, '列舉',
      'LOAD／SEARCH／CREATE／UPDATE／TRANSITION／DELETE／LOOKUP／BATCH_RUN', '操作種類'),
    F('invokedFrom', VS(ARR(R('UI'), mn=1, uniq=True), na=True), True, '陣列〈ID〉' + NA_U(True, False), '', '觸發的畫面元件', ['UI']),
    F('authorization', COND, True, '條件式', '', '誰能執行', ['FLD', 'DRV', 'STATE', 'ROLE']),
    F('inputs', ARR(OBJ({'name': SLUG, 'field': R('FLD'), 'drv': R('DRV'), 'required': BOOL}, req=['name', 'required'])),
      True, '陣列〈物件〉', '可空', '輸入', ['FLD', 'DRV']),
    F('outputs', ARR(OBJ({'name': SLUG, 'field': R('FLD'), 'drv': R('DRV')}, req=['name'])), True, '陣列〈物件〉', '可空', '輸出',
      ['FLD', 'DRV']),
    F('preconditions', VS(COND, na=True), True, '條件式' + NA_U(True, False), '', '前置條件', ['FLD', 'DRV', 'STATE', 'ROLE']),
    F('validations', ARR(R('BR'), uniq=True), True, '陣列〈ID〉', '依執行順序；可空', '套用的檢核規則', ['BR']),
    F('effects', VS(OBJ({'transitions': ARR(R('TRN'), mn=1, uniq=True), 'writes': ARR(ASSIGN),
                         'interfaces': ARR(R('IF'), mn=1, uniq=True)}, req=['writes']), na=True), True,
      '物件' + NA_U(True, False), '唯讀操作寫 NA', '轉移、寫入、觸發的介面', ['TRN', 'FLD', 'DRV', 'STATE', 'ROLE', 'IF']),
    F('transaction', OBJ({
        'boundary': ENUM(['SINGLE_UNIT', 'MULTI_STEP', 'READ_ONLY']),
        'writeOrder': VS(TEXT, na=True),
        'onFailure': OBJ({'kind': ENUM(['ROLLBACK_ALL', 'PARTIAL_COMMIT', 'NOT_APPLICABLE']), 'note': TEXT}),
        'concurrency': VS(OBJ({'strategy': ENUM(['LAST_WRITE_WINS', 'STALE_DATA_CHECK', 'ROW_LOCK', 'NOT_APPLICABLE']),
                               'legacyBehavior': TEXT, 'message': R('MSG')}, req=['strategy', 'legacyBehavior']), unres=True),
        'idempotency': VS(OBJ({'repeatable': BOOL, 'behavior': TEXT}), unres=True),
    }), True, '物件', 'boundary／writeOrder／onFailure／concurrency／idempotency', '交易語意', ['MSG']),
    F('legacyOrigin', OBJ({'object': R('OBJ'), 'events': ARR(RAW, mn=1)}), True, '物件', '', '原系統對應的物件與事件鏈', ['OBJ']),
])

TC_STEP = OBJ({'seq': {'type': 'integer', 'minimum': 1}, 'action': TEXT, 'control': R('UI'), 'operation': R('OP'),
               'inputs': ARR(OBJ({'field': R('FLD'), 'value': {'type': 'string'}}), mn=1)}, req=['seq', 'action'])
item('TC', '^[A-Za-z0-9_$#.-]+:[A-Z][A-Z0-9_]*:(POSITIVE|NEGATIVE|BOUNDARY):[A-Z][A-Z0-9_]*$',
     '<FR 鍵>:<類型>:<代號>', [
    F('name', TEXT, True, '文字', '', '案例名稱'),
    F('scenarioType', ENUM(['POSITIVE', 'NEGATIVE', 'BOUNDARY']), True, '列舉', 'POSITIVE／NEGATIVE／BOUNDARY', '正例／反例／邊界'),
    F('fr', R('FR'), True, 'ID 參照', '', '主要功能', ['FR']),
    F('covers', {'type': 'object', 'minProperties': 1,
                 'properties': {'rules': ARR(R('BR'), mn=1, uniq=True), 'transitions': ARR(R('TRN'), mn=1, uniq=True),
                                'flows': ARR(R('FLOW'), mn=1, uniq=True), 'controls': ARR(R('UI'), mn=1, uniq=True),
                                'operations': ARR(R('OP'), mn=1, uniq=True)},
                 'additionalProperties': False}, True, '物件', '至少一類', '覆蓋的規則／轉移／情境／元件／操作',
      ['BR', 'TRN', 'FLOW', 'UI', 'OP']),
    F('preconditions', OBJ({'state': STATE_OR_INITIAL, 'actor': COND,
                            'data': ARR(OBJ({'field': R('FLD'), 'value': {'type': 'string'}, 'note': TEXT}, req=['field', 'value'])),
                            'synthetic': {'const': True}}, req=['actor', 'data', 'synthetic']),
      True, '物件', 'synthetic 必為 true', '前置狀態、操作者、前置資料（合成）', ['STATE', 'FLD', 'DRV', 'ROLE']),
    F('steps', ARR(TC_STEP, mn=1), True, '陣列〈物件〉', '≥1', '操作步驟', ['UI', 'OP', 'FLD']),
    F('expected', {'type': 'object', 'minProperties': 1,
                   'properties': {'message': R('MSG'), 'resultState': R('STATE'),
                                  'controls': ARR(OBJ({'control': R('UI'), 'visible': BOOL, 'editable': BOOL, 'value': RAW},
                                                      req=['control']), mn=1),
                                  'data': ARR(OBJ({'field': R('FLD'), 'value': {'type': 'string'}}), mn=1),
                                  'noDataChange': BOOL},
                   'additionalProperties': False}, True, '物件', '至少一項', '預期訊息、狀態、元件、資料',
      ['MSG', 'STATE', 'UI', 'FLD']),
    F('verification', TEXT, True, '文字', '', '如何核對'),
])

ALL_REF_UPTO_TASK = {'type': 'string', 'pattern': '^(' + '|'.join(SPEC_PREFIXES + ['TASK']) + ')-\\d{3,}$'}
item('TASK', '^(FOUNDATION:[A-Z][A-Z0-9_]*|SLICE:\\S+)$', 'FOUNDATION:<代號>｜SLICE:<FR 鍵>', [
    F('taskKind', ENUM(['SLICE', 'FOUNDATION']), True, '列舉', 'SLICE／FOUNDATION', '工作種類'),
    F('fr', VS(R('FR'), na=True), True, 'ID 參照' + NA_U(True, False), 'FOUNDATION 寫 NA', '對應功能', ['FR']),
    F('name', TEXT, True, '文字', '', '工作名稱'),
    F('order', {'type': 'integer', 'minimum': 1}, True, '整數', '', '建議順序'),
    F('dependsOn', ARR(R('TASK'), uniq=True), True, '陣列〈ID〉', '可空', '前置工作', ['TASK']),
    F('members', OBJ({k: ARR(R(p), uniq=True) for k, p in [
        ('entities', 'ENT'), ('fields', 'FLD'), ('derivations', 'DRV'), ('roles', 'ROLE'), ('transitions', 'TRN'),
        ('controls', 'UI'), ('rules', 'BR'), ('operations', 'OP'), ('tests', 'TC')]}, req=[]),
      True, '物件', '外環計算', '本工作涵蓋的項目', ['ENT', 'FLD', 'DRV', 'ROLE', 'TRN', 'UI', 'BR', 'OP', 'TC']),
    F('deliverables', ARR(ENUM(['DATA_STRUCTURE', 'OPERATIONS', 'SCREENS', 'RULES', 'SECURITY', 'TESTS']), mn=1, uniq=True),
      True, '陣列〈列舉〉', 'DATA_STRUCTURE／OPERATIONS／SCREENS／RULES／SECURITY／TESTS', '交付物'),
], basis=['COMPUTED'])

item('DOD', '^(GLOBAL:[A-Z][A-Z0-9_]*|TASK:\\S+)$', 'GLOBAL:<代號>｜TASK:<工作鍵>', [
    F('scope', ENUM(['GLOBAL', 'TASK']), True, '列舉', 'GLOBAL／TASK', '適用範圍'),
    F('task', R('TASK'), False, 'ID 參照', 'scope＝TASK 時必填', '對應工作', ['TASK']),
    F('criteria', ARR(OBJ({'kind': ENUM(['TESTS_PASS', 'RULES_IMPLEMENTED', 'STORED_VALUES_PRESERVED', 'MESSAGES_PRESERVED',
                                         'NO_EXCLUDED_FIELDS', 'OPEN_QUESTIONS_CLOSED', 'TRACE_IDS_RECORDED',
                                         'BLANK_SEMANTICS_PRESERVED']),
                           'statement': TEXT, 'refs': ARR(ALL_REF_UPTO_TASK, uniq=True),
                           'evidenceRequired': ENUM(['TEST_REPORT', 'CODE_REFERENCE', 'REVIEW_RECORD'])}), mn=1),
      True, '陣列〈物件〉', 'kind／statement／refs／evidenceRequired', '完成條件', SPEC_PREFIXES + ['TASK']),
], extra=[{'if': {'required': ['scope'], 'properties': {'scope': {'const': 'TASK'}}}, 'then': {'required': ['task']}}],
   basis=['COMPUTED', 'TEMPLATE'])

OFF_DIAGRAM = ['OFF_DIAGRAM_STATE', 'OFF_DIAGRAM_TRANSITION']
item('Q', '^[A-Z][A-Z_]*:\\S+$', '<類別>:<自然鍵>', [
    F('category', ENUM(OFF_DIAGRAM + ['DIAGRAM_EDGE_UNIMPLEMENTED', 'SCOPE_CANDIDATE', 'EVIDENCE_GAP',
                                      'READER_UNDERSPECIFIED', 'READER_DIVERGENT', 'READER_CONTRADICTION', 'INPUT_MISSING']),
      True, '列舉', 'OFF_DIAGRAM_STATE／OFF_DIAGRAM_TRANSITION／DIAGRAM_EDGE_UNIMPLEMENTED／SCOPE_CANDIDATE／EVIDENCE_GAP／READER_*／INPUT_MISSING',
      '問題類別'),
    F('severity', ENUM(['BLOCKING', 'INFO']), True, '列舉', '圖外與 INPUT_MISSING 必為 INFO，其餘必為 BLOCKING', '是否阻擋完成'),
    F('grade', ENUM(['HIGH', 'LOW']), False, '列舉', '圖外類必填', '圖外分級：HIGH＝PROD 有資料；LOW＝僅核心程式賦值'),
    F('question', TEXT, True, '文字', '', '問題敘述'),
    F('affects', ARR(D('refSpec'), uniq=True), True, '陣列〈ID〉', '可空', '受影響的規格項目', SPEC_PREFIXES),
    F('observed', OBJ({'entityKey': SLUG, 'code': RAW, 'from': RAW, 'to': RAW, 'location': RAW}, req=[]), False, '物件',
      '圖外類必填', '觀察到的狀態碼／轉移／位置'),
    F('raisedBy', ENUM(['PARSER', 'RESEARCH', 'REVIEW', 'READER', 'GATE']), True, '列舉', 'PARSER／RESEARCH／REVIEW／READER／GATE', '提出來源'),
    F('status', ENUM(['OPEN', 'ANSWERED', 'WITHDRAWN', 'ACCEPTED_AS_GAP']), True, '列舉', 'OPEN／ANSWERED／WITHDRAWN／ACCEPTED_AS_GAP',
      '狀態（ANSWERED／ACCEPTED_AS_GAP 由 19 的決策反查）'),
    F('proposedAnswer', TEXT, False, '文字', '僅供參考', '研究端建議的答案（不等於決策）'),
], extra=[{'if': {'required': ['category'], 'properties': {'category': {'enum': OFF_DIAGRAM}}},
           'then': {'required': ['grade', 'observed'], 'properties': {'severity': {'const': 'INFO'}}},
           'else': {'not': {'required': ['grade']}}},
          {'if': {'required': ['category'], 'properties': {'category': {'const': 'INPUT_MISSING'}}},
           'then': {'properties': {'severity': {'const': 'INFO'}}}},
          {'if': {'required': ['category'], 'properties': {'category': {'enum': [
              'DIAGRAM_EDGE_UNIMPLEMENTED', 'SCOPE_CANDIDATE', 'EVIDENCE_GAP', 'READER_UNDERSPECIFIED',
              'READER_DIVERGENT', 'READER_CONTRADICTION']}}},
           'then': {'properties': {'severity': {'const': 'BLOCKING'}}}}],
   basis=['COMPUTED'])

item('DEC', '^DEC:\\d{4}$', 'DEC:<四位序號>', [
    F('title', TEXT, True, '文字', '', '決策標題'),
    F('context', TEXT, True, '文字', '', '背景'),
    F('options', ARR(OBJ({'option': TEXT, 'consequence': TEXT}), mn=2), False, '陣列〈物件〉', '≥2', '考慮過的選項'),
    F('decision', TEXT, True, '文字', '', '決定'),
    F('rationale', TEXT, True, '文字', '', '理由'),
    F('decidedBy', TEXT, True, '文字', '只寫職稱或單位類別', '決策者'),
    F('decidedOn', DATE, True, '日期', '', '決策日期'),
    F('status', ENUM(['ACCEPTED', 'SUPERSEDED', 'REVOKED']), True, '列舉', 'ACCEPTED／SUPERSEDED／REVOKED', '決策狀態'),
    F('supersedes', R('DEC'), False, 'ID 參照', '', '取代的舊決策', ['DEC']),
    F('resolves', ARR(R('Q'), uniq=True), True, '陣列〈ID〉', '可空', '回答的問題', ['Q']),
    F('affects', ARR(D('refSpec'), uniq=True), True, '陣列〈ID〉', '可空', '影響的規格項目', SPEC_PREFIXES),
    F('effect', ENUM(['NO_CHANGE', 'DROP', 'ADD_SCOPE', 'ACCEPT_GAP', 'AMEND_INPUT']), True, '列舉',
      'NO_CHANGE／DROP／ADD_SCOPE／ACCEPT_GAP／AMEND_INPUT', '對規格的效果'),
], basis=['HUMAN_DECISION'])

# items a PeopleCode program disposition may point to (all ranked below 09 or inside 09)
IMPL_PREFIXES = ['BR', 'MSG', 'TRN', 'DRV', 'UI', 'IF']

# doc -> item prefixes, extra envelope props
DOC_ITEMS = {
    '01-overview': ['GOAL', 'RESP', 'OBJ'],
    '02-functional-requirements': ['FR'],
    '03-roles-permissions': ['ROLE', 'PERM'],
    '04-workflow': ['STATE', 'TRN', 'FLOW'],
    '05-ui': ['UI'],
    '06-architecture': ['IF'],
    '07-database': ['ENT', 'FLD', 'DRV', 'XF'],
    '08-api': ['OP'],
    '09-business-logic': ['MSG', 'BR'],
    '14-testing': ['TC'],
    '16-ai-instructions': ['AI'],
    '17-tasks': ['TASK'],
    '18-definition-of-done': ['DOD'],
    '19-decision-log': ['DEC'],
    '90-questions': ['Q'],
}
DOC_EXTRA = {
    '01-overview': [F('projectInputStatus', ENUM(['PROVIDED', 'NOT_PROVIDED']), True, '列舉', 'PROVIDED／NOT_PROVIDED',
                      '專案輸入檔是否提供')],
    '04-workflow': [F('diagramSources', ARR(OBJ({'entityKey': SLUG, 'flowchart': RAW, 'stateDiagram': RAW,
                                                 'fingerprint': D('sha256')}), mn=1), True, '陣列〈物件〉', '≥1',
                      '狀態圖來源（每個狀態實體一組 flowchart＋stateDiagram-v2）')],
    '09-business-logic': [F('programDispositions', ARR(OBJ({
        'program': R('OBJ'),
        'kinds': ARR(ENUM(['BUSINESS_RULES', 'UI_BEHAVIOR', 'TRANSITION_IMPL', 'DERIVATION_IMPL', 'NO_BUSINESS_LOGIC',
                           'OFF_DIAGRAM_ONLY']), mn=1, uniq=True),
        'items': ARR({'type': 'string', 'pattern': '^(' + '|'.join(IMPL_PREFIXES) + ')-\\d{3,}$'}, uniq=True),
        'note': TEXT}, req=['program', 'kinds', 'items'])), True, '陣列〈物件〉',
        '核心 PeopleCode 清單每支恰一筆；items 只能指 ' + '／'.join(IMPL_PREFIXES),
        'PeopleCode 程式處置（覆蓋率分母）', ['OBJ'] + IMPL_PREFIXES)],
    '90-questions': [F('suppressed', OBJ({'definitionOnlyCount': {'type': 'integer', 'minimum': 0},
                                          'definitionOnlyCodes': ARR(OBJ({'entityKey': SLUG, 'code': RAW}), uniq=True)}),
                       True, '物件', '', '只存在於值域定義、沒有資料也沒有核心程式使用的狀態碼（只計數，不列題）')],
}

def item_schema(prefix):
    t = ITEM_TYPES[prefix]
    props = {'id': {'type': 'string', 'pattern': f'^{prefix}-\\d{{3,}}$'},
             'key': {'type': 'string', 'pattern': t['key_pattern'], 'description': '自然鍵：' + t['key_label']}}
    for f in t['fields']:
        props[f.name] = f.prop()
    req = [f.name for f in t['fields'] if f.req]
    allof = [{'$ref': f'{C}#/$defs/itemBase'}, {'properties': props, 'required': req}]
    if t['basis']:
        allof.append({'properties': {'basis': {'enum': t['basis']}}})
    if t['evidence_min']:
        allof.append({'properties': {'evidence': {'minItems': t['evidence_min']}}})
    allof += t['extra']
    return {'type': 'object', 'title': f'{prefix}（{PREFIX_INFO[prefix][2]}）', 'allOf': allof,
            'unevaluatedProperties': False}

def doc_schema(doc):
    title = dict(DOC_TYPES)[doc]
    defs = {p: item_schema(p) for p in DOC_ITEMS[doc]}
    props = {'docType': {'const': doc},
             'items': {'type': 'array', 'items': {'oneOf': [{'$ref': f'#/$defs/{p}'} for p in DOC_ITEMS[doc]]}}}
    req = []
    for f in DOC_EXTRA.get(doc, []):
        props[f.name] = f.prop()
        if f.req:
            req.append(f.name)
    return {
        '$schema': 'https://json-schema.org/draft/2020-12/schema',
        '$id': URN + doc,
        'title': title,
        'description': '項目型別：' + '、'.join(f'{p}（{PREFIX_INFO[p][2]}）' for p in DOC_ITEMS[doc]),
        'allOf': [{'$ref': f'{C}#/$defs/envelope'}, {'properties': props, 'required': req}],
        'unevaluatedProperties': False,
        '$defs': defs,
    }

def evidence_schema():
    return {
        '$schema': 'https://json-schema.org/draft/2020-12/schema',
        '$id': URN + 'evidence',
        'title': '證據登錄（evidence.json）',
        'type': 'object',
        'required': ['schemaVersion', 'jobId', 'revision', 'items'],
        'properties': {
            'schemaVersion': {'const': '1.0'},
            'jobId': {'type': 'string', 'pattern': '^clone-[0-9a-f]{16}$'},
            'revision': {'type': 'string', 'pattern': '^r\\d{4}$'},
            'items': ARR({'$ref': f'{C}#/$defs/evidenceItem'}, uniq=True),
        },
        'additionalProperties': False,
    }

def write_all():
    os.makedirs(OUT, exist_ok=True)
    files = {'common.schema.json': build_common(), 'evidence.schema.json': evidence_schema()}
    for doc in DOC_IDS:
        files[f'{doc}.schema.json'] = doc_schema(doc)
    for name, s in files.items():
        with open(os.path.join(OUT, name), 'w', encoding='utf-8', newline='\n') as fh:
            fh.write(json.dumps(s, ensure_ascii=False, indent=2) + '\n')
    return files

# ---------- markdown tables ----------
def md_escape(s):
    return s.replace('|', '\\|')

def field_table(prefix):
    t = ITEM_TYPES[prefix]
    rows = ['| 欄位 | 型別 | 必填 | 值域／限制 | 參照 | 說明 |', '|---|---|---|---|---|---|']
    rows.append(f'| `key` | 自然鍵 | ✓ | `{md_escape(t["key_label"])}` |  | 外環據以派發 ID |')
    for f in t['fields']:
        refs = '、'.join(f.refs)
        rows.append(f'| `{f.name}` | {md_escape(f.tlabel)} | {"✓" if f.req else ""} | {md_escape(f.clabel)} | {refs} | {md_escape(f.desc)} |')
    return '\n'.join(rows)

def extra_table(doc):
    fs = DOC_EXTRA.get(doc, [])
    if not fs:
        return ''
    rows = ['| 外殼欄位 | 型別 | 必填 | 值域／限制 | 說明 |', '|---|---|---|---|---|']
    for f in fs:
        rows.append(f'| `{f.name}` | {md_escape(f.tlabel)} | {"✓" if f.req else ""} | {md_escape(f.clabel)} | {md_escape(f.desc)} |')
    return '\n'.join(rows)

def ref_targets(prefix):
    """All prefixes an item type may reference (from x-ref annotations)."""
    out = set()
    for f in ITEM_TYPES[prefix]['fields']:
        out |= set(f.refs)
    return out

if __name__ == '__main__':
    files = write_all()
    print('wrote', len(files), 'schema files')
