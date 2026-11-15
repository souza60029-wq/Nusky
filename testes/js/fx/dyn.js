import('./dep.js').then(m => globalThis.__log.push(['dyn', m.a, m.default]));
globalThis.__log.push(['meta', import.meta.url.split('/').pop()]);
