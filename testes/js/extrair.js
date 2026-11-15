// Gera testes/js/ambiente.js a partir do JavaScript embutido em app/Nusky/AmbienteJS.swift,
// que é a única fonte da verdade. Os testes rodam sobre o código que o app realmente usa.
const fs = require('fs'), path = require('path');
const swift = fs.readFileSync(path.join(__dirname, '../../app/Nusky/AmbienteJS.swift'), 'utf8');
const marca = 'static let codigo = #"""\n';
const ini = swift.indexOf(marca);
if (ini < 0) throw new Error('não achei o início do JavaScript em AmbienteJS.swift');
const fim = swift.lastIndexOf('\n"""#');
fs.writeFileSync(path.join(__dirname, 'ambiente.js'), swift.slice(ini + marca.length, fim) + '\n');
