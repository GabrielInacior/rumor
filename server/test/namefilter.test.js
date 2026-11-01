'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { checkName, blocked } = require('../src/namefilter');

const REAIS = `Ana Alice Amanda Ana Clara Ana Júlia Ana Luiza Beatriz Bianca Bruna Camila Carolina Catarina Cecília Clara Daniela Débora Eduarda Elisa Emanuelly
Esther Fernanda Gabriela Giovanna Helena Isabela Isadora Jéssica Joana Júlia Juliana Kamilly Lara Larissa Laura Lavínia Letícia Lívia Lorena Luana Luiza
Manuela Maria Eduarda Mariana Marina Melissa Milena Nicole Olívia Pietra Rafaela Rebeca Sabrina Sarah Sofia Stella Tainá Valentina Vitória Yasmin
Alexandre André Antônio Arthur Benjamin Bernardo Breno Bruno Caio Carlos Cauã Davi Diego Eduardo Enzo Felipe Fernando Gabriel Guilherme Gustavo Heitor
Henrique Igor Isaac Joaquim João Pedro Jorge José Kaique Kauã Leonardo Lorenzo Lucas Luiz Marcelo Marcos Matheus Miguel Murilo Nicolas Otávio Paulo
Pedro Rafael Raul Renan Ricardo Rodrigo Samuel Theo Thiago Tomás Vicente Vinícius Vitor Wesley Yuri Rolando Rolim Pintor Picasso Nazira Nazir
Alexsandro Dickson Essex Hancock Pombal Cunha Cury Curi Cuca Paulo Pauline Pauliana Saulo Raul Tadeu Bocage Sacramento Carola Carolaine Pina Piccolo
Vitória Régia Tereza Teresa Puttini Bustamante Rabelo Rabello Peixoto Pereira Pires Prates Pinheiro Silva Souza Oliveira Santos Lima Costa Rocha
Bunduki Cuthbert Xavier Xuxa Xande Cacá Kaká Kiko Kika Pipoca Biel Gui Dudu Duda Juju Lulu Nanda Malu Manu Tati Bia Lari Rafa Fefe Lele Mel Nina
Anderson Wellington Washington Jefferson Kennedy Michael Maicon Maycon Kevin Ryan Bryan Brayan Dylan Erick Patrick Richard Willian Thalles Thales
Ícaro Iago Ítalo Jonas Josué Kelvin Levi Luan Marcelo Mateus Nathan Noah Oliver Otto Pablo Ravi Ruan Saymon Taylor Valentim Wagner Yago Zeca`;
const RUINS = ['pinto', 'P1nt0', 'piiinto', 'penis', 'pênis', 'rola', 'R0L4', 'buceta', 'b.u.c.e.t.a', 'BUCETINHA', 'xibiu', 'perereca', 'pingulim', 'pingolo',
  'pingolim', 'piroca', 'caralho', 'krl', 'porra', 'desgraça', 'desgraçado', 'corno', 'filho da puta', 'filha da puta', 'fdp', 'f d p', 'puta que pariu',
  'pqp', 'vai tomar no cu', 'vtnc', 'arrombado', 'cuzao', 'cuzão', 'vagabunda', 'viado', 'merda', 'bosta', 'otario', 'Ana Puta', 'Pedro Pau', 'cu', 'xoxota',
  'xereca', 'punheta', 'siririca', 'gostosa', 'safado', 'tesao', 'porno', 'sexo', 'piranha', 'fuck', 'pussy', 'nazi', 'hitler', 'pau no cu', 'escroto',
  'babaca', 'baitola', 'boiola', 'chifrudo', 'pomba', 'bilau', 'pintinho', 'kct', 'Caralhoo', 'rolinha', 'pirocudo'];

test('nomes reais passam', () => {
  const nomes = REAIS.split(/\s+/).filter(Boolean);
  const barrados = nomes.filter((n) => blocked(n));
  assert.deepStrictEqual(barrados, [], 'falsos positivos: ' + barrados.join(', '));
  for (const n of ['João Pinto', 'Ana Rola', 'Maria Eduarda Pinto']) assert.strictEqual(blocked(n), false, n);
  assert.strictEqual(checkName('ana clara').name, 'Ana Clara');
});

test('palavrões e disfarces são barrados', () => {
  const passaram = RUINS.filter((n) => !blocked(n));
  assert.deepStrictEqual(passaram, [], 'passaram: ' + passaram.join(', '));
  assert.strictEqual(checkName('a').ok, false);
  assert.strictEqual(checkName('<b>').ok, false);
});
