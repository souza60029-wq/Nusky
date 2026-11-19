const f = async () => { await null; return 3; };
globalThis.__log.push(['sem-tla', typeof f]);
export const ok = 1;
