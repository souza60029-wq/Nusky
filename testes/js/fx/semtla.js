// await só dentro de funções: o módulo NÃO é assíncrono e roda de uma vez.
async function f() { return await Promise.resolve(1); }
const g = async () => { const x = await f(); return (await f()) + x; };
class K { async m() { return (await f()); } }
globalThis.__log.push(['sync-antes']);
g().then(v => globalThis.__log.push(['depois', v]));
globalThis.__log.push(['sync-fim']);
