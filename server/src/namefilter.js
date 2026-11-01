'use strict';
// Filtro do nome que o aluno digita: bloqueia palavrão, termo sexual e xingamento, inclusive
// disfarçado (acento, número no lugar de letra, letra repetida, ponto ou espaço no meio).
// Palavras curtas e ambíguas só contam como palavra inteira (não barra Rolando, Carolina...).
const LIST = require('./name_block.json');

const LEET = { 0: 'o', 1: 'i', 3: 'e', 4: 'a', 5: 's', 7: 't', 8: 'b', 9: 'g', '@': 'a', $: 's', '!': 'i', '|': 'i' };

function base(s) {
  return String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[0-9@$!|]/g, (c) => LEET[c] || c)
    .replace(/ph/g, 'f').replace(/k/g, 'c').replace(/y/g, 'i').replace(/w/g, 'v');
}
const squeeze = (s) => s.replace(/(.)\1+/g, '$1');
// a lista passa pela mesma normalização (k->c, letras dobradas...) para casar com o nome
const ANY = [...new Set(LIST.anywhere.map((w) => squeeze(base(w))))];
const WORD = new Set(LIST.word.map((w) => squeeze(base(w))));
const SURNAMES = new Set(['pinto', 'rola', 'rolla']);
const SUFFIX = /(s|zinh[oa]s?|inh[oa]s?|zao|ao|ona|udo|uda|ada|ado)$/;

function blocked(name) {
  const b = base(name);
  const words = b.split(/[^a-z]+/).filter(Boolean).map(squeeze);
  const joined = squeeze(b.replace(/[^a-z]/g, ''));
  for (const w of ANY) if (joined.includes(w)) return true;
  // sobrenomes reais que também são palavrão (Pinto, Rola): barra só quando o nome é só isso
  if (words.length > 1 && words.some((w) => SURNAMES.has(w))) {
    const rest = words.filter((w) => !SURNAMES.has(w));
    if (rest.length > 0 && rest.every((w) => !WORD.has(w) && !WORD.has(w.replace(SUFFIX, '')))) {
      const jr = squeeze(rest.join(''));
      if (!ANY.some((x) => jr.includes(x))) return false;
    }
  }
  const cands = [...words, joined];
  for (const w of cands) {
    if (WORD.has(w)) return true;
    const stem = w.replace(SUFFIX, '');
    if (stem.length >= 2 && stem !== w && WORD.has(stem)) return true;
  }
  return false;
}

/** Valida e arruma o nome. Devolve { ok, name } ou { ok:false, msg }. */
function checkName(raw) {
  let name = String(raw || '').replace(/\s+/g, ' ').trim().slice(0, 20);
  if (!/^[\p{L} '.-]+$/u.test(name)) return { ok: false, msg: 'Use só letras no nome.' };
  if (name.replace(/[^\p{L}]/gu, '').length < 2) return { ok: false, msg: 'Digite pelo menos 2 letras.' };
  if (blocked(name)) return { ok: false, msg: 'Esse nome não pode. Use seu nome de verdade ou um codinome.' };
  name = name.split(' ').map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join(' ');
  return { ok: true, name };
}

module.exports = { checkName, blocked };
