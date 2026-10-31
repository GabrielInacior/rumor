'use strict';
// Validação determinística da teoria (o quadro da equipe) contra a solução oficial do caso.
// Fica separada da sala para ser testada sozinha e para que a regra seja uma só.

function linkMatches(link, edge, linkTypes) {
  if (link.type !== edge.type) return false;
  if (link.a === edge.from && link.b === edge.to) return true;
  const lt = linkTypes.find((t) => t.id === edge.type);
  const directed = lt ? lt.directed !== false : true;
  return !directed && link.a === edge.to && link.b === edge.from;
}

/**
 * @param {object} caseData caso completo (com solution)
 * @param {{links: Array<{a:string,b:string,type:string,evidence:string|null}>}} board
 * @returns {{correct:boolean, score:number, categories:Array<{id,label,status,found,total}>}}
 *   status: "ok" | "falta_prova" | "incompleto" | "errado"
 */
function validateBoard(caseData, board, culprit) {
  const sol = caseData.solution;
  const links = board.links || [];
  const cats = sol.categories.map((c) => ({
    id: c.id, label: c.label, total: 0, found: 0, proved: 0, trap: false,
  }));
  const byId = Object.fromEntries(cats.map((c) => [c.id, c]));
  let score = 0;

  for (const edge of sol.edges) {
    const cat = byId[edge.category];
    cat.total += 1;
    const hit = links.find((l) => linkMatches(l, edge, caseData.link_types));
    if (!hit) continue;
    cat.found += 1;
    const needs = edge.evidence || [];
    if (needs.length === 0 || (hit.evidence && needs.includes(hit.evidence))) {
      cat.proved += 1;
      score += 100;
    } else {
      score += 50;
    }
  }
  for (const trap of sol.traps || []) {
    if (links.some((l) => linkMatches(l, trap, caseData.link_types))) {
      byId[trap.category].trap = true;
      score -= 60;
    }
  }

  // apontar o culpado: categoria extra quando o caso tem culpado definido
  const culpritCat = [];
  if (sol.culprit) {
    const ok = culprit === sol.culprit;
    if (ok) score += 150;
    culpritCat.push({ id: 'culpado', label: sol.culprit_question || 'Quem é o responsável', status: culprit ? (ok ? 'ok' : 'errado') : 'incompleto', found: ok ? 1 : 0, total: 1 });
  }
  let correct = true;
  const categories = cats.map((c) => {
    let status = 'ok';
    if (c.trap) status = 'errado';
    else if (c.found < c.total) status = 'incompleto';
    else if (c.proved < c.total) status = 'falta_prova';
    if (status !== 'ok') correct = false;
    // "found" de cada categoria é exibido como progresso; não revela QUAL linha falta.
    return { id: c.id, label: c.label, status, found: c.proved, total: c.total };
  });
  for (const c of culpritCat) if (c.status !== 'ok') correct = false;
  return { correct, score: Math.max(0, score), categories: [...categories, ...culpritCat] };
}

module.exports = { validateBoard };
