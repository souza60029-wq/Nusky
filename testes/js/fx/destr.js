export const { p, q: [r1, r2], ...rest } = { p: 1, q: [2, 3], s: 4, t: 5 };
export const [aa1, , aa3 = 9] = [1, 2];
export var v1 = 'x', v2 = `y${1}`, v3 = (function(){ return 'z' })();
import * as me from './destr.js';
globalThis.__log.push(['destr', p, r1, r2, Object.keys(rest).join(), aa1, aa3, v1, v2, v3, Object.keys(me).sort().join()]);
