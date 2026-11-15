import { a } from './dep.js'
export const asi1 = 1
export function asi2() { return a }
export default class extends Object { foo() { return 'cls' } }
const v = asi2()
globalThis.__log.push(['asi', v, asi1])
