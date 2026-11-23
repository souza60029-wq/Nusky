// Roda todos os testes de JavaScript, um por um. Uso: cd testes/js && node rodar-tudo.js
const { spawnSync } = require('child_process');
const testes = ['extrair.js', 'teste.js', 'teste_vivo.js', 'teste_nativo.js', 'teste_modulos.js', 'teste_ids.js', 'teste_extra.js', 'teste_compat.js', 'teste_rx_integrado.js', 'teste_componentes.js', 'teste_polyfills.js', 'poda_css.js', 'teste_modernizar.js'];
let falhou = false;
for (const t of testes) {
  const r = spawnSync(process.execPath, [t], { cwd: __dirname, encoding: 'utf8' });
  const saida = (r.stdout || '') + (r.stderr || '');
  const ruim = r.status !== 0 || /FALHOU|FALHAS:|divergências/.test(saida.replace(/ 0 divergências/g, ''));
  console.log((ruim ? 'FALHOU ' : 'ok     ') + t);
  if (ruim) { falhou = true; console.log(saida.split('\n').filter(l => /FALHOU|FALHAS|Error|ERROS/.test(l)).slice(0, 12).join('\n')); }
}
process.exit(falhou ? 1 : 0);
