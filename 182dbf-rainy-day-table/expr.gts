// A tiny, safe expression language for rules and bot policies.
// Games are data, so conditions like `handTotal(self) < 17 && rules.hitSoft17`
// arrive as strings. This parses them into a tree once (cached) and evaluates
// against a scope. No access to JS globals; only names the scope provides.

export type Node =
  | { t: 'num'; v: number }
  | { t: 'str'; v: string }
  | { t: 'name'; path: string[] }
  | { t: 'call'; fn: string; args: Node[] }
  | { t: 'un'; op: string; a: Node }
  | { t: 'bin'; op: string; a: Node; b: Node }
  | { t: 'tern'; c: Node; a: Node; b: Node };

type Tok = { k: 'num' | 'str' | 'id' | 'op'; v: string };

function lex(src: string): Tok[] {
  let out: Tok[] = [];
  let i = 0;
  while (i < src.length) {
    let c = src[i];
    if (/\s/.test(c)) {
      i++;
      continue;
    }
    if (/[0-9]/.test(c) || (c === '.' && /[0-9]/.test(src[i + 1] ?? ''))) {
      let j = i;
      while (j < src.length && /[0-9.]/.test(src[j])) j++;
      out.push({ k: 'num', v: src.slice(i, j) });
      i = j;
      continue;
    }
    if (c === "'" || c === '"') {
      let j = i + 1;
      let s = '';
      while (j < src.length && src[j] !== c) {
        if (src[j] === '\\') j++;
        s += src[j];
        j++;
      }
      if (j >= src.length) throw new Error(`unclosed string in "${src}"`);
      out.push({ k: 'str', v: s });
      i = j + 1;
      continue;
    }
    if (/[A-Za-z_$]/.test(c)) {
      let j = i;
      while (j < src.length && /[A-Za-z0-9_$.]/.test(src[j])) j++;
      out.push({ k: 'id', v: src.slice(i, j) });
      i = j;
      continue;
    }
    let two = src.slice(i, i + 2);
    if (['==', '!=', '<=', '>=', '&&', '||'].includes(two)) {
      out.push({ k: 'op', v: two });
      i += 2;
      continue;
    }
    if ('+-*/%<>!(),?:'.includes(c)) {
      out.push({ k: 'op', v: c });
      i++;
      continue;
    }
    throw new Error(`unexpected "${c}" in "${src}"`);
  }
  return out;
}

const BP: Record<string, number> = {
  '||': 1,
  '&&': 2,
  '==': 3,
  '!=': 3,
  '<': 4,
  '<=': 4,
  '>': 4,
  '>=': 4,
  '+': 5,
  '-': 5,
  '*': 6,
  '/': 6,
  '%': 6,
};

// Rules compare loosely, as people write them ("hp == 0" when hp is the
// string "0"): numbers and numeric strings match by value, null matches
// undefined, anything else must be identical.
const isNil = (v: unknown) => v === null || v === undefined;
function looseEq(a: any, b: any): boolean {
  if (a === b) return true;
  if (isNil(a) || isNil(b)) return isNil(a) && isNil(b);
  if (typeof a === 'object' || typeof b === 'object') return false;
  if (typeof a === 'string' && typeof b === 'string') return false;
  let x = Number(a);
  let y = Number(b);
  return !Number.isNaN(x) && x === y;
}

export function parse(src: string): Node {
  let toks = lex(src);
  let p = 0;
  const peek = () => toks[p];
  const eat = (v?: string) => {
    let t = toks[p];
    if (!t || (v !== undefined && t.v !== v)) {
      throw new Error(`expected "${v ?? 'a value'}" in "${src}"`);
    }
    p++;
    return t;
  };
  function primary(): Node {
    let t = eat();
    if (t.k === 'num') return { t: 'num', v: Number(t.v) };
    if (t.k === 'str') return { t: 'str', v: t.v };
    if (t.k === 'op' && t.v === '(') {
      let e = expr(0);
      eat(')');
      return e;
    }
    if (t.k === 'op' && (t.v === '!' || t.v === '-')) {
      return { t: 'un', op: t.v, a: primary() };
    }
    if (t.k === 'id') {
      if (peek()?.v === '(') {
        eat('(');
        let args: Node[] = [];
        if (peek()?.v !== ')') {
          args.push(expr(0));
          while (peek()?.v === ',') {
            eat(',');
            args.push(expr(0));
          }
        }
        eat(')');
        return { t: 'call', fn: t.v, args };
      }
      return { t: 'name', path: t.v.split('.') };
    }
    throw new Error(`unexpected "${t.v}" in "${src}"`);
  }
  function expr(min: number): Node {
    let left = primary();
    for (;;) {
      let t = peek();
      if (!t || t.k !== 'op') break;
      if (t.v === '?' && min === 0) {
        eat('?');
        let a = expr(0);
        eat(':');
        let b = expr(0);
        left = { t: 'tern', c: left, a, b };
        continue;
      }
      let bp = BP[t.v];
      if (bp === undefined || bp <= min) break;
      eat();
      left = { t: 'bin', op: t.v, a: left, b: expr(bp) };
    }
    return left;
  }
  let tree = expr(0);
  if (p < toks.length) throw new Error(`unexpected "${toks[p].v}" in "${src}"`);
  return tree;
}

const cache = new Map<string, Node>();
export function compile(src: string): Node {
  let n = cache.get(src);
  if (!n) {
    n = parse(src);
    cache.set(src, n);
  }
  return n;
}

export interface Scope {
  // Resolve a bare or dotted name (`n`, `rules.hitSoft17`, `args.amount`).
  name(path: string[]): unknown;
  // Call a built-in or game-defined function.
  call(fn: string, args: unknown[]): unknown;
}

export function evaluate(node: Node, scope: Scope): any {
  switch (node.t) {
    case 'num':
    case 'str':
      return node.v;
    case 'name':
      if (node.path.length === 1) {
        let n = node.path[0];
        if (n === 'true') return true;
        if (n === 'false') return false;
        if (n === 'null') return null;
      }
      return scope.name(node.path);
    case 'call':
      return scope.call(
        node.fn,
        node.args.map((a) => evaluate(a, scope)),
      );
    case 'un': {
      let v = evaluate(node.a, scope);
      return node.op === '!' ? !v : -v;
    }
    case 'tern':
      return evaluate(node.c, scope)
        ? evaluate(node.a, scope)
        : evaluate(node.b, scope);
    case 'bin': {
      if (node.op === '&&') {
        return evaluate(node.a, scope) && evaluate(node.b, scope);
      }
      if (node.op === '||') {
        return evaluate(node.a, scope) || evaluate(node.b, scope);
      }
      let a = evaluate(node.a, scope);
      let b = evaluate(node.b, scope);
      switch (node.op) {
        case '==':
          return looseEq(a, b);
        case '!=':
          return !looseEq(a, b);
        case '<':
          return a < b;
        case '<=':
          return a <= b;
        case '>':
          return a > b;
        case '>=':
          return a >= b;
        case '+':
          return a + b;
        case '-':
          return a - b;
        case '*':
          return a * b;
        case '/':
          return a / b;
        case '%':
          return a % b;
      }
    }
  }
  throw new Error('bad expression node');
}

// Names a tree reads, for validation ("unknown name n").
export function namesIn(
  node: Node,
  out: string[][] = [],
  calls: string[] = [],
) {
  switch (node.t) {
    case 'name':
      out.push(node.path);
      break;
    case 'call':
      calls.push(node.fn);
      node.args.forEach((a) => namesIn(a, out, calls));
      break;
    case 'un':
      namesIn(node.a, out, calls);
      break;
    case 'bin':
      namesIn(node.a, out, calls);
      namesIn(node.b, out, calls);
      break;
    case 'tern':
      namesIn(node.c, out, calls);
      namesIn(node.a, out, calls);
      namesIn(node.b, out, calls);
      break;
  }
  return { names: out, calls };
}

// Policy sentences: turn `handTotal(self) < 17 && isSoft(self)` into
// "my hand total is under 17 and my hand is soft"-ish plain words.
export function describe(src: string): string {
  if (src.trim() === 'true') return 'otherwise';
  const words = (n: string) =>
    n.replace(/([a-z])([A-Z])/g, (_m, a, b) => `${a} ${b.toLowerCase()}`);
  let s = src
    .replace(/\bres\(self,\s*'(\w+)'\)/g, (_m, n: string) => `my ${n}`)
    .replace(
      /\bis([A-Z]\w*)\(self\)/g,
      (_m, n: string) => `I'm ${words(n[0].toLowerCase() + n.slice(1))}`,
    )
    .replace(/\b(\w+)\(self\)/g, (_m, n: string) => `my ${words(n)}`)
    .replace(/\bself\b/g, 'me')
    .replace(/\s*&&\s*/g, ' and ')
    .replace(/\s*\|\|\s*/g, ' or ')
    .replace(/\s*<=\s*/g, ' ≤ ')
    .replace(/\s*>=\s*/g, ' ≥ ')
    .replace(/\s*==\s*/g, ' is ')
    .replace(/\s*!=\s*/g, ' is not ')
    .replace(/\s*<\s*/g, ' < ')
    .replace(/\s*>\s*/g, ' > ')
    .replace(/rules\./g, 'the house ')
    .replace(/([a-z])([A-Z])/g, (_m, a, b) => `${a} ${b.toLowerCase()}`);
  return `when ${s}`;
}
