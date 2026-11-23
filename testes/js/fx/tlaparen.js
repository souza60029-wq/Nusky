// Padrão do chunk do ChatGPT (rspack): await no topo DENTRO de parênteses, com auto-importação e export {x as default}.
import * as eu from "./tlaparen.js";
import { base } from "./tlabase.js";
globalThis.__log.push(['eu', typeof eu]);
var z = Promise.resolve({ a: 1, b: 2, c: 3 }), A = (z = await z).a, B = z.b, C = z.c;
globalThis.__log.push(['paren', A, B, C, base]);
globalThis.__log.push(['chamada', Math.max(await Promise.resolve(3), 1)]);
globalThis.__log.push(['lista', [await Promise.resolve(7), 8]]);
try { globalThis.__log.push(['bloco', await Promise.resolve('b')]); } catch (e) { globalThis.__log.push('erro'); }
if (A) { globalThis.__log.push(['if', await Promise.resolve('i')]); }
for await (const v of (async function* () { yield 'f1'; yield 'f2'; })()) globalThis.__log.push(['for', v]);
export { A as default, B as handle, C as shouldRevalidate };
