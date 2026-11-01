'use strict';
// Imprime o caso público exatamente como o servidor entrega ao aluno (para as sondas do Godot).
// node tools/dev/public_case.js <id_do_caso>
const fs = require('fs');
const path = require('path');
const { publicCase } = require('../../server/src/room');
const c = JSON.parse(fs.readFileSync(path.join(__dirname, '../../server/cases', process.argv[2] + '.json'), 'utf8'));
process.stdout.write(JSON.stringify(publicCase(c)));
