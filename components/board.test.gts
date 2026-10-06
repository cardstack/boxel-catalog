import { module, test } from 'qunit';
import { settled, triggerKeyEvent } from '@ember/test-helpers';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { renderComponent } from '@cardstack/host/tests/helpers/render-component';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { CardDef, contains, field } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';

import { Board, type BoardColumn } from './board';

class Ticket extends CardDef {
  @field name = contains(StringField);
  @field status = contains(StringField);
}

const COLUMNS: BoardColumn[] = [
  { key: 'todo', label: 'To do' },
  { key: 'doing', label: 'Doing' },
];

const statusOf = (item: CardDef) => (item as Ticket).status;
const nameOf = (item: CardDef) => (item as Ticket).name;

async function moveRight(index: number) {
  let card = `[data-card-index="${index}"]`;
  await triggerKeyEvent(card, 'keydown', ' ');
  await triggerKeyEvent(card, 'keydown', 'ArrowRight');
  await triggerKeyEvent(card, 'keydown', ' ');
}

function columnOf(name: string) {
  return document
    .querySelector(`[data-ticket="${name}"]`)
    ?.closest('[data-kanban-column]')
    ?.getAttribute('data-kanban-column');
}

export function runTests() {
  module('Rendering | catalog Board', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    test('a card whose column is not on the board is not drawn', async function (assert) {
      const items = [
        new Ticket({ name: 'A', status: 'todo' }),
        new Ticket({ name: 'B', status: 'archived' }),
      ];
      await renderComponent(
        <template>
          <Board
            @items={{items}}
            @columns={{COLUMNS}}
            @columnKeyFor={{statusOf}}
          >
            <:card as |item|><span data-ticket={{nameOf item}}>{{nameOf
                  item
                }}</span></:card>
          </Board>
        </template>,
      );
      assert.strictEqual(columnOf('A'), 'todo');
      assert.dom('[data-ticket="B"]').doesNotExist();
    });

    test('an empty board shows the empty message instead of columns', async function (assert) {
      const items: CardDef[] = [];
      await renderComponent(
        <template>
          <Board
            @items={{items}}
            @columns={{COLUMNS}}
            @columnKeyFor={{statusOf}}
            @emptyMessage='No tickets yet'
          />
        </template>,
      );
      assert.dom('[data-test-pretui-board]').doesNotExist();
      assert.dom('.board').containsText('No tickets yet');
    });

    test('a moved card stays in its new column while the save is pending', async function (assert) {
      const items = [new Ticket({ name: 'A', status: 'todo' })];
      const save = { resolve: () => {} };
      const onMove = () =>
        new Promise<void>((resolve) => {
          save.resolve = resolve;
        });
      await renderComponent(
        <template>
          <Board
            @items={{items}}
            @columns={{COLUMNS}}
            @columnKeyFor={{statusOf}}
            @onMove={{onMove}}
          >
            <:card as |item|><span data-ticket={{nameOf item}}>{{nameOf
                  item
                }}</span></:card>
          </Board>
        </template>,
      );
      let drop = moveRight(0);
      await new Promise((r) => setTimeout(r, 50));
      assert.strictEqual(
        columnOf('A'),
        'doing',
        'the card holds where it was dropped',
      );
      assert.dom('.board.saving').exists('the board shows the save in flight');
      items[0].status = 'doing';
      save.resolve();
      await drop;
      await new Promise((r) => setTimeout(r, 0));
      await settled();
      assert.strictEqual(columnOf('A'), 'doing', 'the saved column agrees');
      assert.dom('.board.saving').doesNotExist();
    });

    test('a refused move sends the card back', async function (assert) {
      const items = [new Ticket({ name: 'A', status: 'todo' })];
      const moves: string[] = [];
      const onMove = (_item: CardDef, key: string) => {
        moves.push(key);
        return false;
      };
      await renderComponent(
        <template>
          <Board
            @items={{items}}
            @columns={{COLUMNS}}
            @columnKeyFor={{statusOf}}
            @onMove={{onMove}}
          >
            <:card as |item|><span data-ticket={{nameOf item}}>{{nameOf
                  item
                }}</span></:card>
          </Board>
        </template>,
      );
      await moveRight(0);
      assert.deepEqual(moves, ['doing'], 'onMove was asked');
      assert.strictEqual(
        columnOf('A'),
        'todo',
        'the card is back in its column',
      );
    });

    test('a failed save sends the card back', async function (assert) {
      const items = [new Ticket({ name: 'A', status: 'todo' })];
      const onMove = () => Promise.reject(new Error('write failed'));
      await renderComponent(
        <template>
          <Board
            @items={{items}}
            @columns={{COLUMNS}}
            @columnKeyFor={{statusOf}}
            @onMove={{onMove}}
          >
            <:card as |item|><span data-ticket={{nameOf item}}>{{nameOf
                  item
                }}</span></:card>
          </Board>
        </template>,
      );
      await moveRight(0);
      assert.strictEqual(columnOf('A'), 'todo');
    });

    test('a column wipLimit reaches the plane', async function (assert) {
      const items = [
        new Ticket({ name: 'A', status: 'todo' }),
        new Ticket({ name: 'B', status: 'todo' }),
      ];
      const columns: BoardColumn[] = [
        { key: 'todo', label: 'To do', wipLimit: 1 },
        { key: 'doing', label: 'Doing' },
      ];
      await renderComponent(
        <template>
          <Board
            @items={{items}}
            @columns={{columns}}
            @columnKeyFor={{statusOf}}
          />
        </template>,
      );
      assert
        .dom('[data-kanban-column="todo"]')
        .hasAttribute(
          'data-test-column-is-over-wip',
          '',
          'two cards over a limit of one',
        );
      assert
        .dom('[data-kanban-column="doing"]')
        .doesNotHaveAttribute('data-test-column-is-over-wip');
    });
  });
}
