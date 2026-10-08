# -*- coding: utf-8 -*-
"""參照方向（跨文件只能指向層級更低者）與文件層級無循環的檢查。"""
import collections
import schema_gen as g
def doc_graph():
    bad, edges = [], set()
    for p in g.ITEM_TYPES:
        sdoc, srank, _ = g.PREFIX_INFO[p]
        for t in g.ref_targets(p):
            tdoc, trank, _ = g.PREFIX_INFO[t]
            if tdoc == sdoc: continue
            if not trank < srank: bad.append((p, t))
            edges.add((sdoc, tdoc))
    for doc, fs in g.DOC_EXTRA.items():
        for f in fs:
            for t in f.refs:
                tdoc = g.PREFIX_INFO[t][0]
                if tdoc != doc: edges.add((doc, tdoc))
    adj = collections.defaultdict(set)
    for a, b in edges: adj[a].add(b)
    return bad, adj
def topo(adj):
    indeg = {d: 0 for d in g.DOC_IDS}
    for a in adj:
        for b in adj[a]: indeg[a] += 1   # a depends on b
    order, ready = [], sorted([d for d in g.DOC_IDS if indeg[d] == 0])
    deps = {d: set(adj[d]) for d in g.DOC_IDS}
    done = set()
    while ready:
        d = ready.pop(0); order.append(d); done.add(d)
        ready = sorted(set(ready) | {x for x in g.DOC_IDS if x not in done and x not in ready and deps[x] <= done})
    return order
if __name__ == '__main__':
    import sys
    bad, adj = doc_graph()
    order = topo(adj)
    print('upward refs:', bad)
    print('acyclic:', len(order) == len(g.DOC_IDS))
    print('order:', order)
    if bad or len(order) != len(g.DOC_IDS):
        sys.exit(1)
