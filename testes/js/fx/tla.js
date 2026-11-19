const v = await Promise.resolve(5);
globalThis.__log.push(['tla', v]);
export const x = v * 2;
