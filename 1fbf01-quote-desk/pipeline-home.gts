import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import { QUERIES, cardsOf, instancesOf, dataRealmOf } from './pipeline-link';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';
// GUESS: jalur import mengikuti boxel-catalog/commands/duplicate.gts
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Quote } from './quote';
import { Client, STAGE_LABELS, formatFollowUp } from './client';
import { ServiceItem } from './service-item';
import { Brief } from './brief';

const rupiah = (n: number | null | undefined) =>
  `Rp ${new Intl.NumberFormat('id-ID').format(n ?? 0)}`;

// Aturan hitung dipakai bersama oleh field computed dan papan di isolated
const isDraft = (q: any) => (q.status || 'draft') === 'draft';
const isSent = (q: any) => q.status === 'sent';
const isAccepted = (q: any) => q.status === 'accepted';
const awaitsApproval = (q: any) =>
  q.requiresApproval && (q.approvalDecision || 'pending') === 'pending';

// Slot linksToMany bisa undefined selama loading / link rusak
const loaded = (home: PipelineHome) =>
  (home.quotes ?? []).filter(Boolean) as Quote[];

const sumTotal = (quotes: any[]) =>
  quotes.reduce((sum, q) => sum + (q.total ?? 0), 0);

// Sama dengan warna badge di quote.gts (hanya membaca, logika approval tidak diubah)
const approvalTone = (q: any) => {
  if (!q.requiresApproval) return 'neutral';
  if (q.approvalDecision === 'approved') return 'green';
  if (q.approvalDecision === 'rejected') return 'red';
  return 'yellow';
};

function matching<T>(
  items: T[],
  query: string,
  fields: (item: T) => unknown[],
) {
  let q = query.trim().toLowerCase();
  if (!q) return items;
  return items.filter((item) =>
    fields(item).some((v) =>
      String(v ?? '')
        .toLowerCase()
        .includes(q),
    ),
  );
}

// Helper template sederhana (plain function helper)
const eqKind = (a: unknown, b: unknown) => a === b;

// Status tujuan yang boleh untuk sebuah quote. Draft selalu boleh;
// Sent/Accepted hanya kalau canSend (tidak butuh approval, atau sudah approved).
export function canMoveTo(q: any, status: string) {
  if (status === 'draft') return true;
  return Boolean(q?.canSend);
}

const COLUMNS = [
  { key: 'draft', label: 'Draft', test: isDraft },
  { key: 'sent', label: 'Sent', test: isSent },
  { key: 'accepted', label: 'Accepted', test: isAccepted },
];

export class PipelineHome extends CardDef {
  static displayName = 'Pipeline Home';
  static prefersWideFormat = true;

  @field title = contains(StringField);
  // Opsional: URL workspace data terpisah. Kosong = pakai workspace card ini.
  @field dataRealm = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: PipelineHome) {
      return (
        this.cardInfo?.name?.trim() ||
        this.title?.trim() ||
        `Untitled ${this.constructor.displayName}`
      );
    },
  });

  @field quotes = linksToMany(() => Quote);
  @field clients = linksToMany(() => Client);
  @field serviceItems = linksToMany(() => ServiceItem);

  @field quoteCount = contains(NumberField, {
    computeVia: function (this: PipelineHome) {
      return loaded(this).length;
    },
  });

  @field draftCount = contains(NumberField, {
    computeVia: function (this: PipelineHome) {
      return loaded(this).filter(isDraft).length;
    },
  });

  @field sentCount = contains(NumberField, {
    computeVia: function (this: PipelineHome) {
      return loaded(this).filter(isSent).length;
    },
  });

  @field acceptedCount = contains(NumberField, {
    computeVia: function (this: PipelineHome) {
      return loaded(this).filter(isAccepted).length;
    },
  });

  @field awaitingApprovalCount = contains(NumberField, {
    computeVia: function (this: PipelineHome) {
      return loaded(this).filter(awaitsApproval).length;
    },
  });

  @field sentValue = contains(NumberField, {
    computeVia: function (this: PipelineHome) {
      return sumTotal(loaded(this).filter(isSent));
    },
  });

  @field acceptedValue = contains(NumberField, {
    computeVia: function (this: PipelineHome) {
      return sumTotal(loaded(this).filter(isAccepted));
    },
  });

  static isolated = class Isolated extends Component<typeof PipelineHome> {
    // Semua card di realm ini lewat getCards, query konstan dari pipeline-link
    quotesResource = cardsOf(this, QUERIES.quote);
    briefsResource = cardsOf(this, QUERIES.brief);
    servicesResource = cardsOf(this, QUERIES.serviceItem);
    clientsResource = cardsOf(this, QUERIES.client);

    get allQuotes() {
      return instancesOf(this.quotesResource);
    }

    get stats() {
      let quotes = this.allQuotes;
      let sent = quotes.filter(isSent);
      let accepted = quotes.filter(isAccepted);
      return {
        awaiting: quotes.filter(awaitsApproval).length,
        draft: quotes.filter(isDraft).length,
        sent: sent.length,
        sentValue: rupiah(sumTotal(sent)),
        accepted: accepted.length,
        acceptedValue: rupiah(sumTotal(accepted)),
      };
    }

    get columns() {
      let quotes = this.allQuotes;
      return COLUMNS.map((col) => {
        let items = quotes.filter(col.test);
        return {
          key: col.key,
          label: col.label,
          count: items.length,
          totalLabel: rupiah(sumTotal(items)),
          items: items.map((q) => ({
            id: q.id,
            card: q,
            title: q.title || 'Untitled quote',
            clientName: q.client?.name ?? '',
            totalLabel: rupiah(q.total),
            approvalLabel: q.approvalLabel ?? '',
            tone: approvalTone(q),
          })),
        };
      });
    }

    get briefs() {
      return instancesOf(this.briefsResource)
        .map((b) => {
          let analyzed =
            b.isComplete ||
            b.analysisItems?.length ||
            b.missingInfo?.length ||
            b.clarifyingQuestions?.length;
          return {
            id: b.id,
            card: b,
            title: b.title || 'Untitled brief',
            clientName: b.client?.name ?? '',
            messages: b.messageCount ?? 0,
            status: b.isComplete
              ? 'Ready to quote'
              : analyzed
                ? 'Needs info'
                : 'Not analyzed',
            tone: b.isComplete ? 'green' : analyzed ? 'yellow' : 'neutral',
          };
        })
        .sort((a, b) => a.title.localeCompare(b.title));
    }

    // Prospect dulu (untuk follow-up), lalu Active, Past, tanpa stage
    get clients() {
      let order: Record<string, number> = { prospect: 0, active: 1, past: 2 };
      let quotes = this.allQuotes;
      return instancesOf(this.clientsResource)
        .filter((c) => c.name)
        .map((c) => ({
          id: c.id,
          card: c,
          name: c.name,
          company: c.company ?? '',
          followUp: formatFollowUp(c.nextFollowUp),
          stageLabel: STAGE_LABELS[c.stage ?? ''] ?? 'No stage',
          tone:
            c.stage === 'prospect'
              ? 'yellow'
              : c.stage === 'active'
                ? 'green'
                : 'neutral',
          rank: order[c.stage ?? ''] ?? 3,
          quoteCount: quotes.filter((q) => q.client?.id && q.client.id === c.id)
            .length,
        }))
        .sort((a, b) => a.rank - b.rank || a.name.localeCompare(b.name));
    }

    get services() {
      return instancesOf(this.servicesResource)
        .filter((s) => s.name)
        .sort((a, b) => String(a.name).localeCompare(String(b.name)));
    }

    // Search: teks dicocokkan tanpa membedakan huruf besar/kecil
    @tracked briefQuery = '';
    @tracked clientQuery = '';
    @tracked serviceQuery = '';

    setBriefQuery = (e: Event) => {
      this.briefQuery = (e.target as HTMLInputElement).value;
    };
    setClientQuery = (e: Event) => {
      this.clientQuery = (e.target as HTMLInputElement).value;
    };
    setServiceQuery = (e: Event) => {
      this.serviceQuery = (e.target as HTMLInputElement).value;
    };

    get shownBriefs() {
      return matching(this.briefs, this.briefQuery, (b) => [
        b.title,
        b.clientName,
      ]);
    }

    get shownClients() {
      return matching(this.clients, this.clientQuery, (c) => [
        c.name,
        c.company,
        c.stageLabel,
      ]);
    }

    get shownServices() {
      return matching(this.services, this.serviceQuery, (s) => [
        s.name,
        s.unit,
      ]);
    }

    // Buat card baru lalu buka di mode edit (SaveCardCommand dikonfirmasi Justin;
    // GUESS: viewCard(card, 'edit') dari delegated-rendering.md)
    @tracked creating = '';
    @tracked createError = '';

    create = async (kind: 'brief' | 'quote' | 'client' | 'service') => {
      if (this.creating) return;
      let cx = this.args.context?.toolContext;
      let realm = dataRealmOf(this.args.model);
      if (!cx) {
        this.createError = 'Missing command context.';
        return;
      }
      this.creating = kind;
      this.createError = '';
      try {
        let card: any =
          kind === 'brief'
            ? new Brief({ title: 'New brief' } as any)
            : kind === 'quote'
              ? new Quote({
                  title: 'New quote',
                  status: 'draft',
                  discountPercent: 0,
                } as any)
              : kind === 'client'
                ? new Client({ name: 'New client', stage: 'prospect' } as any)
                : new ServiceItem({ name: 'New service' } as any);
        let saved = await new SaveCardCommand(cx).execute({
          card,
          realm,
        } as any);
        (this.args as any).viewCard?.(saved ?? card, 'edit');
      } catch (e: any) {
        this.createError = `Could not create the card: ${String(e?.message ?? e).slice(0, 160)}`;
      } finally {
        this.creating = '';
      }
    };

    // Drag & drop status. Simpan perubahan status dengan SaveCardCommand
    // (pola update card yang sudah ada: organize-sensitive-stub-pair).
    @tracked draggingId = '';
    @tracked overKey = '';
    // Toast: muncul di pojok, hilang sendiri setelah beberapa detik
    @tracked toastTitle = '';
    @tracked toastText = '';
    @tracked toastTone: 'warn' | 'error' = 'warn';
    private toastTimer: ReturnType<typeof setTimeout> | undefined;

    showToast(tone: 'warn' | 'error', title: string, text: string) {
      this.toastTone = tone;
      this.toastTitle = title;
      this.toastText = text;
      clearTimeout(this.toastTimer);
      this.toastTimer = setTimeout(() => (this.toastTitle = ''), 4000);
    }

    closeToast = () => {
      clearTimeout(this.toastTimer);
      this.toastTitle = '';
    };

    approvalToast(q: any, key: string) {
      this.showToast(
        'warn',
        'Owner approval needed',
        `"${q?.title || 'This quote'}" is awaiting owner approval. Approve it before moving it to ${key === 'accepted' ? 'Accepted' : 'Sent'}.`,
      );
    }

    willDestroy() {
      super.willDestroy();
      clearTimeout(this.toastTimer);
    }
    private dragged: any = null;

    dragStart = (card: any, event: DragEvent) => {
      this.dragged = card;
      this.draggingId = card?.id ?? '';
      event.dataTransfer?.setData('text/plain', card?.id ?? '');
      if (event.dataTransfer) event.dataTransfer.effectAllowed = 'move';
    };

    dragEnd = () => {
      this.dragged = null;
      this.draggingId = '';
      this.overKey = '';
    };

    dragOver = (key: string, event: DragEvent) => {
      if (!this.dragged) return;
      event.preventDefault(); // wajib supaya drop diizinkan
      let allowed = canMoveTo(this.dragged, key);
      if (event.dataTransfer) {
        event.dataTransfer.dropEffect = allowed ? 'move' : 'none';
      }
      // sekali per masuk ke kolom terlarang, bukan tiap event dragover
      if (this.overKey !== key && !allowed)
        this.approvalToast(this.dragged, key);
      this.overKey = key;
    };

    dragLeave = (key: string) => {
      if (this.overKey === key) this.overKey = '';
    };

    drop = async (key: string, event: DragEvent) => {
      event.preventDefault();
      let q = this.dragged;
      this.dragEnd();
      if (!q || (q.status || 'draft') === key) return;
      if (!canMoveTo(q, key)) {
        this.approvalToast(q, key);
        return;
      }
      let previous = q.status;
      q.status = key; // papan langsung pindah (optimistic)
      try {
        let cx = this.args.context?.toolContext;
        if (!cx) throw new Error('Missing command context');
        await new SaveCardCommand(cx).execute({
          card: q,
          realm: dataRealmOf(this.args.model),
        } as any);
      } catch (e: any) {
        q.status = previous;
        this.showToast(
          'error',
          'Could not move the quote',
          String(e?.message ?? e).slice(0, 160),
        );
      }
    };

    // kelas kolom saat sebuah kartu diseret di atasnya
    columnState = (key: string) => {
      if (!this.draggingId || this.overKey !== key) return '';
      return canMoveTo(this.dragged, key) ? 'is-over' : 'is-blocked';
    };

    open = (card: any) => {
      (this.args as any).viewCard?.(card, 'isolated');
    };

    <template>
      <article class='qd'>
        <div class='hero'>
          <header class='qd-head'>
            <p class='eyebrow'><span class='logo'>QD</span> Quote Desk</p>
            <h1 class='qd-title'>{{if
                @model.title
                @model.title
                'Quote Desk'
              }}</h1>
            <p class='tagline'>Messy client briefs → ready-to-send quotes.
              Prices always come from the rate card, never from the AI.</p>
            <div class='actions'>
              <button
                type='button'
                class='action action--primary'
                disabled={{this.creating}}
                {{on 'click' (fn this.create 'brief')}}
              >
                {{if (eqKind this.creating 'brief') 'Creating…' '+ New brief'}}
              </button>
              <button
                type='button'
                class='action'
                disabled={{this.creating}}
                {{on 'click' (fn this.create 'quote')}}
              >
                {{if (eqKind this.creating 'quote') 'Creating…' '+ Quote'}}
              </button>
              <button
                type='button'
                class='action'
                disabled={{this.creating}}
                {{on 'click' (fn this.create 'client')}}
              >
                {{if (eqKind this.creating 'client') 'Creating…' '+ Client'}}
              </button>
              <button
                type='button'
                class='action'
                disabled={{this.creating}}
                {{on 'click' (fn this.create 'service')}}
              >
                {{if (eqKind this.creating 'service') 'Creating…' '+ Service'}}
              </button>
            </div>
            {{#if this.createError}}
              <p class='create-error'>{{this.createError}}</p>
            {{/if}}
          </header>

          <section class='stats'>
            <div class='stat stat--alert'>
              <span class='stat-label'>Awaiting approval</span>
              <span class='stat-value'>{{this.stats.awaiting}}</span>
              <span class='stat-sub'>discount &gt; 10% or total &gt; Rp 10 jt</span>
            </div>
            <div class='stat'>
              <span class='stat-label'>Draft</span>
              <span class='stat-value'>{{this.stats.draft}}</span>
              <span class='stat-sub'>being prepared</span>
            </div>
            <div class='stat'>
              <span class='stat-label'>Sent</span>
              <span class='stat-value'>{{this.stats.sent}}</span>
              <span class='stat-sub'>{{this.stats.sentValue}}</span>
            </div>
            <div class='stat stat--win'>
              <span class='stat-label'>Accepted</span>
              <span class='stat-value'>{{this.stats.accepted}}</span>
              <span class='stat-sub'>{{this.stats.acceptedValue}}</span>
            </div>
          </section>
        </div>

        <div class='layout'>
          <div class='main'>
            <section class='board' aria-label='Quote pipeline'>
              {{#each this.columns key='key' as |col|}}
                <div
                  class='col col--{{col.key}} {{this.columnState col.key}}'
                  {{on 'dragover' (fn this.dragOver col.key)}}
                  {{on 'dragleave' (fn this.dragLeave col.key)}}
                  {{on 'drop' (fn this.drop col.key)}}
                >
                  <div class='col-head'>
                    <span class='col-label'>{{col.label}}</span>
                    <span class='col-count'>{{col.count}}</span>
                  </div>
                  <p class='col-total'>{{col.totalLabel}}</p>
                  {{#each col.items key='id' as |q|}}
                    <button
                      type='button'
                      class='qcard
                        {{if (eqKind this.draggingId q.id) "is-dragging"}}'
                      draggable='true'
                      {{on 'dragstart' (fn this.dragStart q.card)}}
                      {{on 'dragend' this.dragEnd}}
                      {{on 'click' (fn this.open q.card)}}
                    >
                      <span class='qcard-title'>{{q.title}}</span>
                      {{#if q.clientName}}
                        <span class='qcard-client'>{{q.clientName}}</span>
                      {{/if}}
                      <span class='qcard-row'>
                        <span
                          class='badge badge--{{q.tone}}'
                        >{{q.approvalLabel}}</span>
                        <span class='qcard-total'>{{q.totalLabel}}</span>
                      </span>
                    </button>
                  {{else}}
                    <p class='empty'>No quotes</p>
                  {{/each}}
                </div>
              {{/each}}
            </section>

            <section class='panel rate'>
              <div class='panel-head'>
                <h2 class='panel-title'>Rate card</h2>
                <input
                  type='search'
                  class='search'
                  placeholder='Search services'
                  aria-label='Search rate card'
                  value={{this.serviceQuery}}
                  {{on 'input' this.setServiceQuery}}
                />
              </div>
              <div class='rate-grid'>
                {{#each this.shownServices key='id' as |s|}}
                  <button
                    type='button'
                    class='rate-item'
                    {{on 'click' (fn this.open s)}}
                  >
                    <span class='row-title'>{{s.name}}</span>
                    <span class='row-price'>{{s.priceLabel}}</span>
                  </button>
                {{else}}
                  <p class='empty'>{{if
                      this.serviceQuery
                      'No matching services'
                      'No service items yet'
                    }}</p>
                {{/each}}
              </div>
            </section>
          </div>

          <aside class='side'>
            <section class='panel'>
              <div class='panel-head'>
                <h2 class='panel-title'>Briefs</h2>
                <input
                  type='search'
                  class='search'
                  placeholder='Search briefs'
                  aria-label='Search briefs'
                  value={{this.briefQuery}}
                  {{on 'input' this.setBriefQuery}}
                />
              </div>
              {{#each this.shownBriefs key='id' as |b|}}
                <button
                  type='button'
                  class='row'
                  {{on 'click' (fn this.open b.card)}}
                >
                  <span class='row-main'>
                    <span class='row-title'>{{b.title}}</span>
                    <span class='row-meta'>{{b.clientName}}
                      ·
                      {{b.messages}}
                      messages</span>
                  </span>
                  <span class='badge badge--{{b.tone}}'>{{b.status}}</span>
                </button>
              {{else}}
                <p class='empty'>{{if
                    this.briefQuery
                    'No matching briefs'
                    'No briefs yet'
                  }}</p>
              {{/each}}
            </section>

            <section class='panel'>
              <div class='panel-head'>
                <h2 class='panel-title'>Clients</h2>
                <input
                  type='search'
                  class='search'
                  placeholder='Search clients'
                  aria-label='Search clients'
                  value={{this.clientQuery}}
                  {{on 'input' this.setClientQuery}}
                />
              </div>
              {{#each this.shownClients key='id' as |c|}}
                <button
                  type='button'
                  class='row'
                  {{on 'click' (fn this.open c.card)}}
                >
                  <span class='row-main'>
                    <span class='row-title'>{{c.name}}</span>
                    <span class='row-meta'>{{c.company}}
                      ·
                      {{c.quoteCount}}
                      quotes</span>
                    {{#if c.followUp}}
                      <span class='row-follow'>Follow up {{c.followUp}}</span>
                    {{/if}}
                  </span>
                  <span class='badge badge--{{c.tone}}'>{{c.stageLabel}}</span>
                </button>
              {{else}}
                <p class='empty'>{{if
                    this.clientQuery
                    'No matching clients'
                    'No clients yet'
                  }}</p>
              {{/each}}
            </section>

          </aside>
        </div>
        {{#if this.toastTitle}}
          <div
            class='toast toast--{{this.toastTone}}'
            role='status'
            aria-live='polite'
          >
            <span class='toast-icon' aria-hidden='true'>!</span>
            <div class='toast-body'>
              <strong class='toast-title'>{{this.toastTitle}}</strong>
              <p class='toast-text'>{{this.toastText}}</p>
            </div>
            <button
              type='button'
              class='toast-close'
              aria-label='Dismiss'
              {{on 'click' this.closeToast}}
            >×</button>
          </div>
        {{/if}}
      </article>
      <style scoped>
        .qd {
          --ink: #1d2433;
          --muted: #6b6457;
          --paper: #f2ece1;
          --line: #ddd3c1;
          --accent: #b8502a;
          --alert: #b7791f;
          --alert-bg: #fff4d6;
          --win: #2e6e4f;
          --win-bg: #e0ece3;
          min-height: 100%;
          padding: 40px 48px 56px;
          background: var(--paper);
          color: var(--ink);
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
        .qd-head {
          margin-bottom: 28px;
        }
        .eyebrow {
          margin: 0 0 6px;
          font-size: 0.75rem;
          font-weight: 700;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--accent);
        }
        .qd-title {
          font-family:
            'Iowan Old Style', 'Palatino Linotype', Palatino, 'Book Antiqua',
            Georgia, serif;
          margin: 0;
          font-size: 2.4rem;
          font-weight: 600;
          letter-spacing: -0.01em;
          line-height: 1.15;
        }
        .tagline {
          margin: 8px 0 0;
          max-width: 640px;
          color: var(--muted);
        }
        .stats {
          display: grid;
          grid-template-columns: repeat(4, minmax(0, 1fr));
          gap: 14px;
          margin-bottom: 28px;
        }
        .stat {
          display: flex;
          flex-direction: column;
          gap: 2px;
          padding: 16px 18px;
          border: 1px solid var(--line);
          border-radius: 4px;
          background: #fff;
        }
        .stat--alert {
          border-color: #f0d48a;
          background: var(--alert-bg);
        }
        .stat--win {
          border-color: #b9e3c7;
          background: var(--win-bg);
        }
        .stat-label {
          font-size: 0.8rem;
          font-weight: 600;
          color: var(--muted);
        }
        .stat-value {
          font-family:
            'Iowan Old Style', 'Palatino Linotype', Palatino, 'Book Antiqua',
            Georgia, serif;
          font-size: 2rem;
          font-weight: 600;
          line-height: 1.2;
        }
        .stat--alert .stat-value {
          color: var(--alert);
        }
        .stat--win .stat-value {
          color: var(--win);
        }
        .stat-sub {
          font-size: 0.8rem;
          color: var(--muted);
        }
        .layout {
          display: grid;
          grid-template-columns: minmax(0, 1fr) 320px;
          gap: 20px;
          align-items: start;
        }
        .main {
          display: flex;
          flex-direction: column;
          gap: 20px;
          min-width: 0;
        }
        .rate-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
          gap: 10px;
        }
        .rate-item {
          display: flex;
          flex-direction: column;
          gap: 2px;
          padding: 12px 14px;
          border: 1px solid var(--line);
          border-radius: 4px;
          background: #fff;
          color: inherit;
          font: inherit;
          text-align: left;
          cursor: pointer;
        }
        .rate-item:hover {
          border-color: var(--accent);
        }
        .board {
          display: grid;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          gap: 14px;
        }
        .col.is-over {
          outline: 2px dashed var(--accent);
          outline-offset: -4px;
        }
        .col.is-blocked {
          outline: 2px dashed #b3261e;
          outline-offset: -4px;
          background: #f6dcd6;
        }
        .qcard[draggable='true'] {
          cursor: grab;
        }
        .qcard.is-dragging {
          opacity: 0.45;
        }
        .toast {
          position: fixed;
          right: 24px;
          bottom: 24px;
          z-index: 20;
          display: flex;
          align-items: flex-start;
          gap: 12px;
          max-width: 360px;
          padding: 14px 16px;
          border-radius: 4px;
          background: #1d2433;
          color: #fff;
          box-shadow: 0 12px 28px rgba(29, 36, 51, 0.28);
        }
        .toast-icon {
          flex: none;
          display: grid;
          place-items: center;
          width: 24px;
          height: 24px;
          border-radius: 50%;
          background: #e7a33e;
          color: #1d2433;
          font-weight: 900;
        }
        .toast--error .toast-icon {
          background: #e0563d;
          color: #fff;
        }
        .toast-body {
          min-width: 0;
        }
        .toast-title {
          display: block;
          margin-bottom: 2px;
          font-size: 0.9rem;
        }
        .toast-text {
          margin: 0;
          font-size: 0.82rem;
          line-height: 1.45;
          color: rgba(255, 255, 255, 0.78);
        }
        .toast-close {
          flex: none;
          margin-left: 4px;
          padding: 0 4px;
          border: none;
          background: none;
          color: rgba(255, 255, 255, 0.7);
          font: inherit;
          font-size: 1.1rem;
          line-height: 1;
          cursor: pointer;
        }
        .toast-close:hover {
          color: #fff;
        }
        @media (prefers-reduced-motion: no-preference) {
          .toast {
            animation: qd-toast-in 320ms cubic-bezier(0.2, 0.7, 0, 1) both;
          }
          @keyframes qd-toast-in {
            from {
              opacity: 0;
              transform: translateY(16px);
            }
            to {
              opacity: 1;
              transform: none;
            }
          }
        }
        .col {
          padding: 14px;
          border-radius: 4px;
          background: #e8dfcf;
        }
        .col-label::before {
          content: '';
          display: inline-block;
          width: 8px;
          height: 8px;
          margin-right: 8px;
          border-radius: 50%;
          background: var(--muted);
          vertical-align: middle;
        }
        .col--sent .col-label::before {
          background: var(--accent);
        }
        .col--accepted .col-label::before {
          background: var(--win);
        }
        .col-head {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }
        .col-label {
          font-weight: 700;
        }
        .col-count {
          min-width: 24px;
          padding: 1px 8px;
          border-radius: 3px;
          background: #fff;
          font-size: 0.8rem;
          font-weight: 700;
          text-align: center;
        }
        .col-total {
          margin: 2px 0 12px;
          font-size: 0.8rem;
          color: var(--muted);
        }
        .qcard {
          display: flex;
          flex-direction: column;
          gap: 4px;
          width: 100%;
          margin-bottom: 10px;
          padding: 12px;
          border: 1px solid var(--line);
          border-radius: 4px;
          background: #fff;
          color: inherit;
          font: inherit;
          text-align: left;
          cursor: pointer;
        }
        .qcard:hover,
        .row:hover {
          border-color: var(--accent);
        }
        .qcard-title {
          font-weight: 700;
          line-height: 1.3;
        }
        .qcard-client {
          font-size: 0.85rem;
          color: var(--muted);
        }
        .qcard-row {
          display: flex;
          justify-content: space-between;
          align-items: center;
          gap: 8px;
          margin-top: 6px;
        }
        .qcard-total {
          font-weight: 700;
          white-space: nowrap;
        }
        .badge {
          padding: 2px 8px;
          border-radius: 3px;
          font-size: 0.7rem;
          font-weight: 600;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .badge--neutral {
          background: #e8e1d3;
          color: #4a4f5c;
        }
        .badge--yellow {
          background: var(--alert-bg);
          color: #7a5b00;
        }
        .badge--green {
          background: var(--win-bg);
          color: var(--win);
        }
        .badge--red {
          background: #fde2e2;
          color: #a11d1d;
        }
        .side {
          display: flex;
          flex-direction: column;
          gap: 14px;
        }
        .panel {
          padding: 16px;
          border: 1px solid var(--line);
          border-radius: 4px;
          background: #fff;
        }
        .panel-head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 10px;
          margin-bottom: 10px;
        }
        .panel-head .panel-title {
          margin: 0;
        }
        .search {
          width: 150px;
          min-width: 0;
          padding: 6px 10px;
          border: 1px solid var(--line);
          border-radius: 4px;
          background: var(--paper);
          color: var(--ink);
          font: inherit;
          font-size: 0.8rem;
        }
        .search:focus {
          outline: 2px solid var(--accent);
          outline-offset: 1px;
          background: #fff;
        }
        .panel-title {
          margin: 0 0 10px;
          font-size: 0.8rem;
          font-weight: 700;
          letter-spacing: 0.1em;
          text-transform: uppercase;
          color: var(--muted);
        }
        /* Badge di bawah judul supaya tidak terpotong di panel sempit */
        .row {
          display: flex;
          flex-direction: column;
          align-items: flex-start;
          gap: 6px;
          width: 100%;
          padding: 9px 10px;
          border: 1px solid transparent;
          border-radius: 8px;
          background: none;
          color: inherit;
          font: inherit;
          text-align: left;
          cursor: pointer;
        }
        .row .badge {
          max-width: 100%;
          overflow: visible;
          white-space: normal;
        }
        .row-main {
          display: flex;
          flex-direction: column;
          min-width: 0;
        }
        .row-title {
          font-weight: 600;
          font-size: 0.9rem;
        }
        .row-meta,
        .row-price {
          font-size: 0.8rem;
          color: var(--muted);
          white-space: nowrap;
        }
        .row-follow {
          font-size: 0.75rem;
          font-weight: 600;
          color: #7a5b00;
        }
        .empty {
          margin: 4px 0;
          font-size: 0.85rem;
          color: var(--muted);
        }
        /* Hero: band navy + aksen amber, identitas Quote Desk */
        .hero {
          margin-bottom: 24px;
          padding: 32px 32px 28px;
          border-radius: 4px;
          background: #1d2433;
          color: #fff;
        }
        .hero .eyebrow {
          display: flex;
          align-items: center;
          gap: 8px;
          color: #e7a33e;
        }
        .logo {
          display: grid;
          place-items: center;
          width: 26px;
          height: 26px;
          border-radius: 7px;
          background: #e7a33e;
          color: #1d2433;
          font-size: 0.7rem;
          font-weight: 900;
          letter-spacing: 0;
        }
        .hero .qd-title {
          color: #fff;
        }
        .actions {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
          margin-top: 18px;
        }
        .action {
          padding: 8px 14px;
          border: 1px solid rgba(255, 255, 255, 0.35);
          border-radius: 4px;
          background: transparent;
          color: #fff;
          font: inherit;
          font-size: 0.85rem;
          font-weight: 700;
          cursor: pointer;
        }
        .action:hover:not(:disabled) {
          border-color: #fff;
          background: rgba(255, 255, 255, 0.08);
        }
        .action--primary {
          border-color: #e7a33e;
          background: #e7a33e;
          color: #1d2433;
        }
        .action--primary:hover:not(:disabled) {
          border-color: #f0b65a;
          background: #f0b65a;
        }
        .action:disabled {
          opacity: 0.6;
          cursor: wait;
        }
        .create-error {
          margin: 10px 0 0;
          color: #ffd4c2;
          font-size: 0.85rem;
        }
        .hero .tagline {
          color: rgba(255, 255, 255, 0.72);
        }
        .hero .stats {
          margin-bottom: 0;
        }
        .hero .stat {
          border-color: rgba(255, 255, 255, 0.12);
          background: rgba(255, 255, 255, 0.07);
        }
        .hero .stat-label,
        .hero .stat-sub {
          color: rgba(255, 255, 255, 0.7);
        }
        .hero .stat-value {
          color: #fff;
        }
        .hero .stat--alert {
          border-color: #e7a33e;
          background: rgba(255, 181, 71, 0.16);
        }
        .hero .stat--alert .stat-value {
          color: #e7a33e;
        }
        .hero .stat--win {
          border-color: rgba(110, 231, 160, 0.5);
          background: rgba(110, 231, 160, 0.12);
        }
        .hero .stat--win .stat-value {
          color: #6ee7a0;
        }
        .col-head {
          padding-bottom: 6px;
        }
        /* Motion: kertas & stempel */
        @media (prefers-reduced-motion: no-preference) {
          .hero {
            animation: qd-drop 650ms cubic-bezier(0.2, 0.7, 0, 1) both;
          }
          .logo {
            animation: qd-spin-in 900ms cubic-bezier(0.2, 0.7, 0, 1) 150ms both;
          }
          .stat {
            animation: qd-rise 600ms cubic-bezier(0.2, 0.7, 0, 1) both;
          }
          .stat:nth-child(1) {
            animation-delay: 200ms;
          }
          .stat:nth-child(2) {
            animation-delay: 280ms;
          }
          .stat:nth-child(3) {
            animation-delay: 360ms;
          }
          .stat:nth-child(4) {
            animation-delay: 440ms;
          }
          .col {
            animation: qd-rise 600ms cubic-bezier(0.2, 0.7, 0, 1) both;
          }
          .col:nth-child(1) {
            animation-delay: 350ms;
          }
          .col:nth-child(2) {
            animation-delay: 440ms;
          }
          .col:nth-child(3) {
            animation-delay: 530ms;
          }
          .qcard {
            transition:
              transform 180ms ease,
              box-shadow 180ms ease;
          }
          .qcard:hover {
            transform: translateY(-3px) rotate(-0.4deg);
            box-shadow: 0 8px 18px rgba(29, 36, 51, 0.12);
          }
          .rate-item {
            transition: transform 180ms ease;
          }
          .rate-item:hover {
            transform: rotate(-1deg) translateY(-2px);
          }
          .panel {
            animation: qd-rise 600ms cubic-bezier(0.2, 0.7, 0, 1) 450ms both;
          }
          @keyframes qd-drop {
            from {
              opacity: 0;
              transform: translateY(-14px);
            }
            to {
              opacity: 1;
              transform: none;
            }
          }
          @keyframes qd-rise {
            from {
              opacity: 0;
              transform: translateY(14px);
            }
            to {
              opacity: 1;
              transform: none;
            }
          }
          @keyframes qd-spin-in {
            from {
              opacity: 0;
              transform: rotate(-90deg) scale(0.4);
            }
            to {
              opacity: 1;
              transform: none;
            }
          }
          @keyframes qd-fade {
            from {
              opacity: 0;
            }
            to {
              opacity: 1;
            }
          }
        }
        @media (max-width: 1100px) {
          .layout {
            grid-template-columns: minmax(0, 1fr);
          }
        }
        @media (max-width: 760px) {
          .qd {
            padding: 24px 16px;
          }
          .stats,
          .board {
            grid-template-columns: minmax(0, 1fr);
          }
        }
      </style>
    </template>
  };

  // Tile pin di Home: angka dari field computed (quote yang ditautkan)
  static fitted = class Fitted extends Component<typeof PipelineHome> {
    quotesResource = cardsOf(this, QUERIES.quote);

    get counts() {
      let quotes = instancesOf(this.quotesResource);
      return {
        awaiting: quotes.filter(awaitsApproval).length,
        sent: quotes.filter(isSent).length,
        accepted: quotes.filter(isAccepted).length,
      };
    }

    <template>
      <div class='fit'>
        <div class='fit-head'>
          <span class='fit-eyebrow'>Quote Desk</span>
          <span class='fit-title'>{{if
              @model.title
              @model.title
              'Pipeline'
            }}</span>
        </div>
        <div class='fit-stats'>
          <span class='fit-stat fit-stat--alert'><b>{{this.counts.awaiting}}</b>
            awaiting approval</span>
          <span class='fit-stat'><b>{{this.counts.sent}}</b> sent</span>
          <span class='fit-stat fit-stat--win'><b>{{this.counts.accepted}}</b>
            accepted</span>
        </div>
      </div>
      <style scoped>
        .fit {
          display: grid;
          grid-template-rows: auto minmax(0, 1fr);
          gap: 10px;
          height: 100%;
          min-height: 0;
          padding: 14px 16px;
          overflow: hidden;
          background: #f2ece1;
          color: #1d2433;
          font-family:
            Inter,
            system-ui,
            -apple-system,
            'Segoe UI',
            sans-serif;
        }
        .fit-head {
          display: flex;
          flex-direction: column;
          min-width: 0;
        }
        .fit-eyebrow {
          font-size: 0.65rem;
          font-weight: 700;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: #b8502a;
        }
        .fit-title {
          font-size: 1.1rem;
          font-weight: 800;
          line-height: 1.2;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .fit-stats {
          display: flex;
          flex-direction: column;
          gap: 6px;
          min-height: 0;
          overflow: hidden;
        }
        .fit-stat {
          font-size: 0.85rem;
          color: #6b6457;
        }
        .fit-stat b {
          margin-right: 4px;
          font-size: 1.1rem;
          color: #1d2433;
        }
        .fit-stat--alert b {
          color: #b7791f;
        }
        .fit-stat--win b {
          color: #2e6e4f;
        }
        @container fitted-card (max-height: 105px) {
          .fit {
            grid-template-rows: auto;
            padding: 8px 10px;
          }
          .fit-stats {
            display: none;
          }
        }
      </style>
    </template>
  };
}
