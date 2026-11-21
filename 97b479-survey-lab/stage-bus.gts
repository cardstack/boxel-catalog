// The interviewer's talking portrait (a Living Portrait card, living-portrait.gts)
// opens beside the chat. Cards on one page
// share this event bus (the same global the portrait listens on), so the chat
// can hand it each line to perform: lip-sync, blinks, a caption and, if the
// viewer turned it on, a voice. If the portrait isn't open, nothing happens.
export type Line = {
  speaker: string;
  text: string;
  at: number;
  dur: number;
  mood?: string;
  gesture?: string;
};
export type SceneMsg =
  | { kind: 'ping'; from: string }
  | { kind: 'here'; who: string; ready: boolean }
  | {
      kind: 'scene';
      id: string;
      lines: Line[];
      total: number;
      startAt: number;
      title: string;
    };

const BUS: EventTarget = ((globalThis as any).__tachieSceneBus ??=
  new EventTarget());
export const send = (msg: SceneMsg) =>
  BUS.dispatchEvent(new CustomEvent('msg', { detail: msg }));
export function listen(fn: (m: SceneMsg) => void) {
  const h = (e: Event) => fn((e as CustomEvent).detail);
  BUS.addEventListener('msg', h);
  return () => BUS.removeEventListener('msg', h);
}

// is the portrait open and ready? (it answers a ping with its name)
function ready(who: string, ms: number): Promise<boolean> {
  return new Promise((ok) => {
    let done = false;
    const finish = (v: boolean) => {
      if (done) return;
      done = true;
      stop();
      clearInterval(ping);
      ok(v);
    };
    const stop = listen((m) => {
      if (m.kind === 'here' && m.who === who && m.ready) finish(true);
    });
    const ping = setInterval(
      () => send({ kind: 'ping', from: 'interview' }),
      400,
    );
    send({ kind: 'ping', from: 'interview' });
    setTimeout(() => finish(false), ms);
  });
}

const CPS = 14; // characters a second, the portrait's own speaking speed

// hand one line to the portrait; wait a little in case it's still opening
export async function performLine(name: string, text: string, waitMs = 600) {
  const who = name.toLowerCase();
  if (!text || !(await ready(who, waitMs))) return;
  const dur = Math.max(1.2, text.length / CPS);
  const warm = /[!]|\bthanks?\b|\bthank you\b|\bha\b/i.test(text);
  send({
    kind: 'scene',
    id: `iv-${Date.now()}`,
    title: 'interview',
    lines: [
      { speaker: name, text, at: 0.25, dur, mood: warm ? 'happy' : 'calm' },
    ],
    total: dur + 1.6,
    startAt: performance.now() + 250,
  });
}
