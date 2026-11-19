async function* g() { yield 1; yield 2; }
let soma = 0;
for await (const n of g()) soma += n;
globalThis.__log.push(['for-await', soma]);
