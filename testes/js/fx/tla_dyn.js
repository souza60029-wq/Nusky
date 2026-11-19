const m = await import('./tla.js');
globalThis.__log.push(['dyn', m.x]);
