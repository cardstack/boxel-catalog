import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import TextAreaField from '@cardstack/base/text-area';
import BooleanField from '@cardstack/base/boolean';
import { TextFileDef } from '@cardstack/base/text-file-def';
import { restartableTask } from 'ember-concurrency';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
// GUESS: jalur import mengikuti boxel-catalog/commands/duplicate.gts
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Quote, QuoteLine } from './quote';
import { Client } from './client';
import AnalyzeBriefCommand from './commands/analyze-brief';
import { QUERIES, cardsOf, dataRealmOf } from './pipeline-link';

// Saran AI, hanya teks biasa (tanpa linksTo, tanpa harga)
export class AnalysisItem extends FieldDef {
  static displayName = 'Analysis Item';

  @field itemName = contains(StringField);
  @field unit = contains(StringField);
  @field qty = contains(NumberField);
  @field reason = contains(StringField);
}

// Ekspor chat WhatsApp, format dideteksi per baris:
// Android "31/10/2026 09.15 - Nama: pesan" (d/m/yy, koma opsional, jam "." atau ":", AM/PM opsional)
// iPhone  "[9/19/26, 12:35:37 PM] Nama: pesan" (m/d/yy)
const ANDROID_LINE =
  /^(\d{1,2}\/\d{1,2}\/(?:\d{2}|\d{4})),?\s+(\d{1,2}[.:]\d{2}(?:[.:]\d{2})?(?:\s*[AaPp]\.?\s?[Mm]\.?)?)\s+-\s+(.*)$/;
const IPHONE_LINE =
  /^\[(\d{1,2}\/\d{1,2}\/(?:\d{2}|\d{4})),\s+(\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AaPp]\.?\s?[Mm]\.?)?)\]\s+(.*)$/;
const DATE_PREFIX = /^\[?\d{1,2}\/\d{1,2}\/\d{2,4}/;
const SENDER = /^([^:]+?):\s(.*)$/;
const MEDIA =
  /^<[^>]*(media|omitted|disertakan|dihapus|deleted|invite)[^>]*>$/i;
// Ekspor iPhone menyisipkan tanda arah teks tak terlihat (U+200E dst.)
const INVISIBLE = /[\u200E\u200F\u202A-\u202E\uFEFF]/g;

type ChatMessage = { at: string; sender: string; text: string };

// Cache: semua computed + transcript membaca teks yang sama
let lastRaw: string | null | undefined;
let lastParsed: ReturnType<typeof parseChatUncached> | undefined;

function parseChat(raw: string | null | undefined) {
  if (lastParsed && raw === lastRaw) return lastParsed;
  lastRaw = raw;
  lastParsed = parseChatUncached(raw);
  return lastParsed;
}

function parseChatUncached(raw: string | null | undefined) {
  let messages: ChatMessage[] = [];
  let unparsed = 0;
  // null setelah baris sistem/media: lanjutan sesudahnya tidak ditempel ke mana pun
  let last: ChatMessage | null = null;

  for (let rawLine of (raw ?? '').split(/\r\n|\r|\n/)) {
    let line = rawLine.replace(INVISIBLE, '');
    if (!line.trim()) continue;
    let m = ANDROID_LINE.exec(line) ?? IPHONE_LINE.exec(line);
    if (!m) {
      if (DATE_PREFIX.test(line)) {
        unparsed++;
      } else if (last) {
        last.text += `\n${line.trim()}`;
      } else if (messages.length) {
        unparsed++;
      } // sebelum pesan pertama (mis. header enkripsi iPhone): abaikan
      continue;
    }
    let rest = m[3];
    let body = rest.startsWith('- ') ? null : SENDER.exec(rest);
    if (!body || MEDIA.test(body[2].trim())) {
      last = null; // baris sistem (tanpa pengirim) atau media
      continue;
    }
    last = {
      at: `${m[1]} ${m[2]}`,
      sender: body[1].trim(),
      text: body[2].trim(),
    };
    messages.push(last);
  }
  return { messages, unparsed };
}

// Teks tempelan menang; file dipakai hanya kalau rawChat kosong
const usesFile = (brief: Brief) =>
  !brief.rawChat?.trim() && Boolean(brief.chatFile?.content?.trim());

export class Brief extends CardDef {
  static displayName = 'Brief';
  static prefersWideFormat = true;

  @field title = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Brief) {
      return (
        this.cardInfo?.name?.trim() ||
        this.title?.trim() ||
        `Untitled ${this.constructor.displayName}`
      );
    },
  });

  @field client = linksTo(() => Client);
  @field rawChat = contains(TextAreaField);
  @field chatFile = linksTo(() => TextFileDef);

  // Lihat usesFile; link file undefined selama loading → pakai rawChat
  @field chatText = contains(TextAreaField, {
    computeVia: function (this: Brief) {
      return usesFile(this) ? this.chatFile!.content : (this.rawChat ?? '');
    },
  });

  @field messageCount = contains(NumberField, {
    computeVia: function (this: Brief) {
      return parseChat(this.chatText).messages.length;
    },
  });

  @field senders = containsMany(StringField, {
    computeVia: function (this: Brief) {
      return [
        ...new Set(parseChat(this.chatText).messages.map((m) => m.sender)),
      ];
    },
  });

  // Disimpan sebagai teks asli dari chat; urutan hari/bulan tidak ditebak
  @field firstMessageAt = contains(StringField, {
    computeVia: function (this: Brief) {
      return parseChat(this.chatText).messages[0]?.at ?? '';
    },
  });

  @field lastMessageAt = contains(StringField, {
    computeVia: function (this: Brief) {
      return parseChat(this.chatText).messages.at(-1)?.at ?? '';
    },
  });

  @field transcript = contains(TextAreaField, {
    computeVia: function (this: Brief) {
      return parseChat(this.chatText)
        .messages.map((m) => `${m.sender}: ${m.text}`)
        .join('\n');
    },
  });

  @field unparsedLines = contains(NumberField, {
    computeVia: function (this: Brief) {
      return parseChat(this.chatText).unparsed;
    },
  });

  // Hasil analisis AI (diisi nanti oleh Command); harga tetap dari ServiceItem
  @field analysisItems = containsMany(AnalysisItem);
  @field missingInfo = containsMany(StringField);
  @field clarifyingQuestions = containsMany(StringField);
  @field isComplete = contains(BooleanField);
  @field analysisError = contains(StringField);

  static isolated = class Isolated extends Component<typeof Brief> {
    // Fase 3: Quote draft dari saran AI. Harga tetap dari ServiceItem (linksTo),
    // AI hanya menentukan item + qty. Cara ini dikonfirmasi Justin (4 Nov).
    @tracked createMessage = '';

    get cannotCreateQuote() {
      let m = this.args.model;
      return (
        !m.isComplete ||
        !m.analysisItems?.length ||
        !this.serviceItems.length ||
        this.createQuoteTask.isRunning
      );
    }

    createQuoteTask = restartableTask(async () => {
      let model = this.args.model;
      this.createMessage = '';
      let byName = new Map(
        this.serviceItems.map((s) => [
          String(s.name ?? '')
            .trim()
            .toLowerCase(),
          s,
        ]),
      );
      let lines: any[] = [];
      let unmatched: string[] = [];
      for (let a of model.analysisItems ?? []) {
        if (!a) continue;
        let service = byName.get(
          String(a.itemName ?? '')
            .trim()
            .toLowerCase(),
        );
        if (service) {
          lines.push(new QuoteLine({ item: service, qty: a.qty ?? 1 } as any));
        } else {
          unmatched.push(a.itemName ?? '?');
        }
      }
      if (!lines.length) {
        this.createMessage =
          'None of the suggested services match the rate card.';
        return;
      }
      let cx = this.args.context?.toolContext;
      let realm = dataRealmOf(this.args.model);
      if (!cx || !realm) {
        this.createMessage = 'Missing command context or realm.';
        return;
      }
      try {
        let quote = new Quote({
          title: model.title || 'New quote',
          client: model.client,
          status: 'draft',
          discountPercent: 0,
          lines,
        } as any);
        let saved = await new SaveCardCommand(cx).execute({
          card: quote,
          realm,
        } as any);
        if (unmatched.length) {
          this.createMessage = `Quote created. Not in the rate card: ${unmatched.join(', ')}`;
        }
        (this.args as any).viewCard?.(saved ?? quote, 'isolated');
      } catch (e: any) {
        this.createMessage = `Could not create the quote: ${String(e?.message ?? e).slice(0, 200)}`;
      }
    });

    startCreateQuote = () => this.createQuoteTask.perform();

    // Semua ServiceItem di realm ini (resource: terisi bertahap, bukan promise)
    serviceItemsResource = cardsOf(this, QUERIES.serviceItem);

    // Urutan stabil: nomor katalog N menunjuk ke serviceItems[N - 1]
    get serviceItems(): any[] {
      return [...((this.serviceItemsResource as any)?.instances ?? [])]
        .filter(Boolean)
        .sort((a, b) =>
          String(a.name ?? '').localeCompare(String(b.name ?? '')),
        );
    }

    get cannotAnalyze() {
      return (
        !this.serviceItems.length ||
        !this.args.model.transcript?.trim() ||
        this.analyzeTask.isRunning
      );
    }

    analyzeTask = restartableTask(async () => {
      let model = this.args.model;
      model.analysisError = '';
      let items = this.serviceItems;
      let catalogText = items
        .map((s, i) => `${i + 1}. ${s.name ?? ''} (${s.unit ?? ''})`)
        .join('\n');
      try {
        let cx = this.args.context?.toolContext;
        if (!cx) {
          model.analysisError = 'Missing command context.';
          return;
        }
        let result = await new AnalyzeBriefCommand(cx).execute({
          transcript: model.transcript ?? '',
          catalogText,
        });
        let error =
          (result as any)?.error ?? (result as any)?.attributes?.error ?? '';
        let resultJson =
          (result as any)?.resultJson ??
          (result as any)?.attributes?.resultJson ??
          '';
        if (error) {
          model.analysisError = String(error);
          return;
        }
        let parsed: any;
        try {
          parsed = JSON.parse(resultJson);
        } catch {
          model.analysisError = 'Could not read the AI result.';
          return;
        }
        // Harga tidak diambil dari AI; hanya nama + satuan dari ServiceItem
        model.analysisItems = (Array.isArray(parsed.items) ? parsed.items : [])
          .filter((i: any) => items[i?.itemNumber - 1])
          .map((i: any) => {
            let s = items[i.itemNumber - 1];
            return new AnalysisItem({
              itemName: s.name ?? '',
              unit: s.unit ?? '',
              qty: i.qty,
              reason: i.reason ?? '',
            });
          });
        model.missingInfo = parsed.missingInfo ?? [];
        model.clarifyingQuestions = parsed.clarifyingQuestions ?? [];
        model.isComplete = parsed.isComplete === true;
      } catch (e: any) {
        model.analysisError = `AI analysis failed: ${String(e?.message ?? e).slice(0, 200)}`;
      }
    });

    startAnalyze = () => this.analyzeTask.perform();

    get senderList() {
      return (this.args.model.senders ?? []).join(', ') || '-';
    }

    // Satu baris per pesan; warna latar bergilir per pengirim (4 warna)
    get transcriptRows() {
      let messages = parseChat(this.args.model.chatText).messages;
      let senders = [...new Set(messages.map((m) => m.sender))];
      return messages.map((m) => ({
        sender: m.sender,
        lines: m.text.split('\n'),
        tone: `tone-${senders.indexOf(m.sender) % 4}`,
      }));
    }

    get notAnExport() {
      let { chatText, messageCount, unparsedLines } = this.args.model;
      if (!chatText?.trim()) return false;
      return !messageCount || (unparsedLines ?? 0) > messageCount;
    }

    // isComplete false saja tidak dihitung: bisa jadi nilai kosong default
    get hasAnalysis() {
      let m = this.args.model;
      return Boolean(
        m.analysisItems?.length ||
        m.missingInfo?.length ||
        m.clarifyingQuestions?.length ||
        m.isComplete,
      );
    }

    get sourceLabel() {
      return usesFile(this.args.model as Brief)
        ? 'Source: file'
        : 'Source: pasted text';
    }

    // Arah visual: ruang kerja chat (kiri) + panel asisten AI (kanan)
    <template>
      <article class='page'>
        <header class='head'>
          <div class='crumb'>
            <span class='crumb-mark'>QD</span>
            <span class='crumb-brand'>Quote Desk</span>
            <span class='crumb-sep'>/</span>
            <span class='crumb-here'>Brief</span>
          </div>
          <p class='eyebrow'>Brief</p>
          <h1 class='title'>{{@model.title}}</h1>
          {{#if @model.client}}
            <p class='client'>{{@model.client.name}}</p>
          {{/if}}
          <div class='chips'>
            <span class='chip'><b>{{@model.messageCount}}</b> messages</span>
            <span class='chip'>{{this.senderList}}</span>
            <span class='chip'>{{@model.firstMessageAt}}
              –
              {{@model.lastMessageAt}}</span>
            <span class='chip'>{{this.sourceLabel}}</span>
            <span class='chip'><b>{{@model.unparsedLines}}</b>
              unparsed lines</span>
          </div>
          {{#if this.notAnExport}}
            <p class='warning'>This doesn't look like a WhatsApp export. Export
              the chat from WhatsApp (Export chat &gt; Without media) instead of
              copying from the screen.</p>
          {{/if}}
          {{#if @model.unparsedLines}}
            <p class='warning'>{{@model.unparsedLines}}
              line(s) did not match the chat format and were skipped. Check the
              original chat.</p>
          {{/if}}
        </header>

        <div class='grid'>
          <section class='chat-col'>
            <div class='panel'>
              <h2 class='panel-title'>Conversation</h2>
              <div class='transcript'>
                {{#each this.transcriptRows key='@index' as |row|}}
                  <div class='msg {{row.tone}}'>
                    <strong class='sender'>{{row.sender}}</strong>
                    {{#each row.lines as |text|}}
                      <div class='line'>{{text}}</div>
                    {{/each}}
                  </div>
                {{else}}
                  <p class='empty'>Paste or upload an exported WhatsApp chat to
                    see the conversation here.</p>
                {{/each}}
              </div>
            </div>
            <details class='raw-box'>
              <summary>Original export</summary>
              <div class='raw'>{{@model.chatText}}</div>
            </details>
          </section>

          <aside class='ai-col'>
            <div class='ai-panel'>
              <p class='eyebrow'>AI assistant</p>
              <h2 class='ai-title'>Brief analysis</h2>
              <button
                type='button'
                class='analyze-button
                  {{if this.analyzeTask.isRunning "is-running"}}'
                disabled={{this.cannotAnalyze}}
                {{on 'click' this.startAnalyze}}
              >{{if
                  this.analyzeTask.isRunning
                  'Analyzing...'
                  'Analyze brief with AI'
                }}</button>
              <p class='loaded'>{{this.serviceItems.length}} services loaded</p>
              {{#unless this.serviceItems.length}}
                <p class='hint'>No service items loaded yet</p>
              {{/unless}}
              {{#if @model.analysisError}}
                <p class='warning'>{{@model.analysisError}}</p>
              {{/if}}

              {{#if this.hasAnalysis}}
                {{#if @model.isComplete}}
                  <p class='verdict verdict--ready'>Ready to quote</p>
                {{else}}
                  <p class='verdict verdict--info'>Needs more info from the
                    client</p>
                {{/if}}

                {{#if @model.analysisItems.length}}
                  <h3>Suggested services</h3>
                  <ul class='items'>
                    {{#each @model.analysisItems as |line|}}
                      <li class='item'>
                        <span class='item-top'>
                          <span class='item-name'>{{line.itemName}}</span>
                          <span class='item-qty'>×
                            {{line.qty}}
                            {{line.unit}}</span>
                        </span>
                        {{#if line.reason}}
                          <span class='reason'>{{line.reason}}</span>
                        {{/if}}
                      </li>
                    {{/each}}
                  </ul>
                {{/if}}
                {{#if @model.isComplete}}
                  <button
                    type='button'
                    class='create-button'
                    disabled={{this.cannotCreateQuote}}
                    {{on 'click' this.startCreateQuote}}
                  >{{if
                      this.createQuoteTask.isRunning
                      'Creating quote...'
                      'Create quote from brief'
                    }}</button>
                  <p class='hint'>Creates a draft quote. Prices come from the
                    rate card.</p>
                {{/if}}
                {{#if this.createMessage}}
                  <p class='warning'>{{this.createMessage}}</p>
                {{/if}}
                {{#if @model.missingInfo.length}}
                  <h3>Missing info</h3>
                  <ul class='bullets'>
                    {{#each @model.missingInfo as |text|}}
                      <li>{{text}}</li>
                    {{/each}}
                  </ul>
                {{/if}}
                {{#if @model.clarifyingQuestions.length}}
                  <h3>Questions for the client</h3>
                  <ol class='questions'>
                    {{#each @model.clarifyingQuestions as |text|}}
                      <li>{{text}}</li>
                    {{/each}}
                  </ol>
                {{/if}}
              {{else}}
                <p class='empty'>Run the analysis to see suggested services,
                  missing info and questions for the client.</p>
              {{/if}}

              <p class='note'>The AI only picks services and quantities from the
                rate card. Prices and totals are never set by the AI.</p>
            </div>
          </aside>
        </div>
      </article>
      <style scoped>
        .page {
          min-height: 100%;
          padding: 36px 40px 48px;
          background: #f2ece1;
          color: #1d2433;
          font-family:
            Inter,
            system-ui,
            -apple-system,
            'Segoe UI',
            sans-serif;
          background-image: radial-gradient(
            rgba(29, 36, 51, 0.08) 1px,
            transparent 1px
          );
          background-size: 16px 16px;
        }
        .crumb {
          display: flex;
          align-items: center;
          gap: 8px;
          margin: 0 0 20px;
          padding: 8px 12px;
          border-radius: 4px;
          background: #1d2433;
          color: #fff;
          font-size: 0.8rem;
          text-decoration: none;
        }
        .crumb-mark {
          display: grid;
          place-items: center;
          width: 22px;
          height: 22px;
          border-radius: 6px;
          background: #e7a33e;
          color: #1d2433;
          font-size: 0.65rem;
          font-weight: 900;
        }
        .crumb-brand {
          font-weight: 800;
        }
        .crumb-sep {
          opacity: 0.4;
        }
        .crumb-here {
          opacity: 0.8;
        }
        .head {
          margin-bottom: 24px;
        }
        .eyebrow {
          margin: 0 0 6px;
          font-size: 0.75rem;
          font-weight: 700;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: #b8502a;
        }
        .title {
          font-family:
            'Iowan Old Style', 'Palatino Linotype', Palatino, 'Book Antiqua',
            Georgia, serif;
          margin: 0;
          font-size: 2rem;
          font-weight: 600;
          letter-spacing: -0.01em;
          line-height: 1.2;
        }
        .client {
          margin: 4px 0 0;
          color: #6b6457;
        }
        .chips {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
          margin-top: 14px;
        }
        .chip {
          padding: 4px 10px;
          border: 1px solid #ddd3c1;
          border-radius: 3px;
          background: #fff;
          font-size: 0.8rem;
          color: #6b6457;
        }
        .chip b {
          color: #1d2433;
        }
        .warning {
          margin: 12px 0 0;
          padding: 10px 12px;
          border: 1px solid #e0b400;
          border-radius: 4px;
          background: #fff3c4;
          color: #7a5b00;
        }
        .grid {
          display: grid;
          grid-template-columns: minmax(0, 1fr) 380px;
          gap: 20px;
          align-items: start;
        }
        .panel,
        .ai-panel {
          padding: 18px 20px;
          border: 1px solid #ddd3c1;
          border-radius: 4px;
          background: #fff;
        }
        .panel-title {
          margin: 0 0 12px;
          font-size: 0.8rem;
          font-weight: 700;
          letter-spacing: 0.1em;
          text-transform: uppercase;
          color: #6b6457;
        }
        .transcript {
          display: flex;
          flex-direction: column;
          gap: 8px;
          max-height: 520px;
          overflow-y: auto;
          font-size: 0.9rem;
          line-height: 1.5;
          word-break: break-word;
        }
        .msg {
          max-width: 85%;
          padding: 8px 12px;
          border-radius: 4px;
        }
        .msg .sender {
          display: block;
          margin-bottom: 2px;
          font-size: 0.75rem;
        }
        .tone-0 {
          align-self: flex-start;
          background: #ebe4d6;
          border-top-left-radius: 4px;
        }
        .tone-1 {
          align-self: flex-end;
          background: #f6e3d9;
          border-top-right-radius: 4px;
        }
        .tone-2 {
          align-self: flex-start;
          background: #fff1dc;
        }
        .tone-3 {
          align-self: flex-end;
          background: #f1e6fb;
        }
        .raw-box {
          margin-top: 12px;
          padding: 10px 14px;
          border: 1px solid #ddd3c1;
          border-radius: 4px;
          background: #fff;
          font-size: 0.85rem;
        }
        .raw-box summary {
          cursor: pointer;
          font-weight: 600;
          color: #6b6457;
        }
        .raw {
          max-height: 240px;
          margin-top: 10px;
          overflow-y: auto;
          white-space: pre-line;
          font-size: 0.8rem;
          color: #333;
        }
        .ai-panel {
          position: sticky;
          top: 16px;
        }
        .ai-title {
          font-family:
            'Iowan Old Style', 'Palatino Linotype', Palatino, 'Book Antiqua',
            Georgia, serif;
          margin: 0 0 14px;
          font-size: 1.3rem;
          font-weight: 600;
        }
        .create-button {
          width: 100%;
          margin-top: 8px;
          padding: 12px 16px;
          border: none;
          border-radius: 4px;
          background: #2e6e4f;
          color: #fff;
          font: inherit;
          font-weight: 700;
          cursor: pointer;
        }
        .create-button:disabled {
          background: #d6d3cb;
          color: #6b6f7a;
          cursor: not-allowed;
        }
        .analyze-button {
          width: 100%;
          padding: 12px 16px;
          border: none;
          border-radius: 4px;
          background: #b8502a;
          color: #fff;
          font: inherit;
          font-weight: 700;
          cursor: pointer;
        }
        .analyze-button:disabled {
          background: #d6d3cb;
          color: #6b6f7a;
          cursor: not-allowed;
        }
        .loaded,
        .hint {
          margin: 6px 0 0;
          font-size: 0.8rem;
          color: #6b6457;
          text-align: center;
        }
        .verdict {
          margin: 16px 0 4px;
          padding: 10px 12px;
          border-radius: 4px;
          font-weight: 700;
        }
        .verdict--ready {
          background: #e0ece3;
          color: #2e6e4f;
        }
        .verdict--info {
          background: #fff4d6;
          color: #7a5b00;
        }
        h3 {
          margin: 16px 0 6px;
          font-size: 0.8rem;
          font-weight: 700;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: #6b6457;
        }
        .items {
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .item {
          display: flex;
          flex-direction: column;
          gap: 2px;
          margin-bottom: 8px;
          padding: 10px 12px;
          border-radius: 8px;
          background: #f2ece1;
        }
        .item-top {
          display: flex;
          justify-content: space-between;
          gap: 8px;
        }
        .item-name {
          font-weight: 700;
        }
        .item-qty {
          font-weight: 700;
          color: #b8502a;
          white-space: nowrap;
        }
        .reason {
          font-size: 0.8rem;
          color: #6b6457;
        }
        .bullets,
        .questions {
          margin: 0;
          padding-left: 20px;
          font-size: 0.9rem;
          line-height: 1.5;
        }
        .questions li {
          margin-bottom: 4px;
        }
        .empty {
          margin: 14px 0 0;
          font-size: 0.85rem;
          color: #6b6457;
        }
        .note {
          margin: 16px 0 0;
          padding-top: 12px;
          border-top: 1px dashed #ddd3c1;
          font-size: 0.75rem;
          color: #6b6457;
        }
        /* Motion: kertas & stempel */
        @media (prefers-reduced-motion: no-preference) {
          .head {
            animation: br-rise 550ms cubic-bezier(0.2, 0.7, 0, 1) both;
          }
          .msg {
            animation: br-pop-left 420ms cubic-bezier(0.2, 0.7, 0, 1) both;
          }
          .msg.tone-1,
          .msg.tone-3 {
            animation-name: br-pop-right;
          }
          .msg:nth-child(1) {
            animation-delay: 150ms;
          }
          .msg:nth-child(2) {
            animation-delay: 210ms;
          }
          .msg:nth-child(3) {
            animation-delay: 270ms;
          }
          .msg:nth-child(4) {
            animation-delay: 330ms;
          }
          .msg:nth-child(5) {
            animation-delay: 390ms;
          }
          .msg:nth-child(6) {
            animation-delay: 450ms;
          }
          .msg:nth-child(7) {
            animation-delay: 510ms;
          }
          .msg:nth-child(8) {
            animation-delay: 570ms;
          }
          .msg:nth-child(9) {
            animation-delay: 630ms;
          }
          .msg:nth-child(10) {
            animation-delay: 690ms;
          }
          .msg:nth-child(11) {
            animation-delay: 750ms;
          }
          .msg:nth-child(12) {
            animation-delay: 810ms;
          }
          .ai-panel {
            animation: br-slide-in 650ms cubic-bezier(0.2, 0.7, 0, 1) 200ms both;
          }
          .analyze-button.is-running {
            background-image: repeating-linear-gradient(
              -45deg,
              rgba(255, 255, 255, 0.18) 0 10px,
              transparent 10px 20px
            );
            background-size: 28px 28px;
            animation: br-stripes 0.8s linear infinite;
          }
          .verdict {
            animation: br-stamp 520ms cubic-bezier(0.3, 1.4, 0.5, 1) both;
            transform-origin: left center;
          }
          .item {
            animation: br-rise 450ms cubic-bezier(0.2, 0.7, 0, 1) both;
          }
          .item:nth-child(1) {
            animation-delay: 250ms;
          }
          .item:nth-child(2) {
            animation-delay: 320ms;
          }
          .item:nth-child(3) {
            animation-delay: 390ms;
          }
          .item:nth-child(4) {
            animation-delay: 460ms;
          }
          .item:nth-child(5) {
            animation-delay: 530ms;
          }
          .item:nth-child(6) {
            animation-delay: 600ms;
          }
          .item:nth-child(7) {
            animation-delay: 670ms;
          }
          .item:nth-child(8) {
            animation-delay: 740ms;
          }
          .questions li,
          .bullets li {
            animation: br-fade 400ms ease both;
          }
          @keyframes br-rise {
            from {
              opacity: 0;
              transform: translateY(12px);
            }
            to {
              opacity: 1;
              transform: none;
            }
          }
          @keyframes br-pop-left {
            from {
              opacity: 0;
              transform: translateX(-14px) scale(0.96);
            }
            to {
              opacity: 1;
              transform: none;
            }
          }
          @keyframes br-pop-right {
            from {
              opacity: 0;
              transform: translateX(14px) scale(0.96);
            }
            to {
              opacity: 1;
              transform: none;
            }
          }
          @keyframes br-slide-in {
            from {
              opacity: 0;
              transform: translateX(24px);
            }
            to {
              opacity: 1;
              transform: none;
            }
          }
          @keyframes br-stripes {
            from {
              background-position: 0 0;
            }
            to {
              background-position: 28px 0;
            }
          }
          @keyframes br-stamp {
            0% {
              opacity: 0;
              transform: scale(1.6) rotate(-8deg);
            }
            70% {
              opacity: 1;
              transform: scale(0.96) rotate(-1deg);
            }
            100% {
              opacity: 1;
              transform: none;
            }
          }
          @keyframes br-fade {
            from {
              opacity: 0;
            }
            to {
              opacity: 1;
            }
          }
        }
        @media (max-width: 1000px) {
          .grid {
            grid-template-columns: minmax(0, 1fr);
          }
          .ai-panel {
            position: static;
          }
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof Brief> {
    <template>
      <div class='brief-edit'>
        <section>
          <h3>Title</h3>
          <@fields.title />
        </section>
        <section>
          <h3>Client</h3>
          <@fields.client />
        </section>

        <section>
          <h3>Paste exported chat</h3>
          <p class='hint'>In WhatsApp: open chat &gt; More &gt; Export chat &gt;
            Without media, then paste the .txt content here. Don't copy directly
            from the chat screen, it loses sender names and timestamps.</p>
          <@fields.rawChat />
        </section>

        <section>
          <h3>Or upload a .txt file</h3>
          <p class='hint'>Pasted text takes priority over the file. Clear the
            pasted text to use the file.</p>
          <@fields.chatFile />
        </section>
      </div>
      <style scoped>
        .brief-edit {
          padding: 24px;
        }
        section {
          margin-bottom: 24px;
        }
        h3 {
          margin: 0 0 8px;
          font-size: 0.95rem;
        }
        .hint {
          margin: 0 0 8px;
          font-size: 0.8rem;
          color: #555;
        }
      </style>
    </template>
  };
}
