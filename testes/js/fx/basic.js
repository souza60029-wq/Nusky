import def, { a, b as c } from './dep.js';
import * as ns from './dep.js';
import './efeito.js';
globalThis.__log.push(['basic', def, a, c, ns.a, Object.keys(ns).sort().join()]);
export const x = 1, y = 2;
export let z; z = 3;
export function f() { return 'f' }
export class K { m() { return 'K' } }
export default function () { return 'padrao' }
globalThis.__log.push(['basic2', x, y, z]);
