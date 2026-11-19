globalThis.__log.push('antes');
await new Promise(r => setTimeout(r, 15));
globalThis.__log.push('depois');
export default 7;
