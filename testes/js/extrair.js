// Gera testes/js/ambiente.js e testes/js/extra.js a partir do JavaScript embutido nos arquivos Swift,
// que são a única fonte da verdade. Os testes rodam sobre o código que o app realmente usa.
const fs = require('fs'), path = require('path');
function extrair(arquivoSwift, marca, saida) {
  const swift = fs.readFileSync(path.join(__dirname, '../../app/Nusky', arquivoSwift), 'utf8');
  const ini = swift.indexOf(marca);
  if (ini < 0) throw new Error('não achei o início do JavaScript em ' + arquivoSwift);
  const fim = swift.lastIndexOf('\n"""#');
  fs.writeFileSync(path.join(__dirname, saida), swift.slice(ini + marca.length, fim) + '\n');
}
extrair('AmbienteJS.swift', 'static let codigo = #"""\n', 'ambiente.js');
extrair('AmbienteJSExtra.swift', 'static let extra = #"""\n', 'extra.js');
extrair('AmbienteJSModerno.swift', 'static let moderno = #"""\n', 'moderno.js');
