const s1 = "import x from 'y'; export const nope = 1";
const s2 = `template ${ 'import {a} from "b"' + `inner ${1 + 1}` } export default 3`;
const re = /import\s+x\/;'"`/g; // "export default"
/* import 'comentario'; export {z}; */
const obj = { import: 1, export: 2 };
const obj2 = { x: obj.import + obj.export };
const div = 10 / 2 / 1;
const t = `a${ `b${ `c` }` }d`;
globalThis.__log.push(['tricky', s1.length, s2, re.source, obj2.x, div, t]);
export const ok = true;
