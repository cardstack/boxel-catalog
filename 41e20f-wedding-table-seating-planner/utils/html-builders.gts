import { htmlSafe } from '@ember/template';

let _keySeq = 0;
const _keys = new WeakMap<object, string>();
export function keyOf(obj: unknown): string {
  if (!obj || typeof obj !== 'object') return '';
  let k = _keys.get(obj);
  if (!k) {
    k = `k${++_keySeq}`;
    _keys.set(obj, k);
  }
  return k;
}
export function htmlBg(color: string | null | undefined) {
  return htmlSafe(`background:${color || '#c5a35c'}`);
}
export function htmlBarWidth(pct: string) {
  return htmlSafe(`width:${pct}`);
}
export function htmlWorld(style: string) {
  return htmlSafe(style);
}
export function htmlSeat(left: string, top: string, color: string) {
  return htmlSafe(`left:${left};top:${top};--seatcol:${color}`);
}
export function htmlGhost(x: number, y: number) {
  return htmlSafe(`left:${x}px;top:${y}px`);
}
