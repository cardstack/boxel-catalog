import {
  CardDef,
  contains,
  containsMany,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import { CsvFileDef } from '@cardstack/base/csv-file-def';
import NumberField from '@cardstack/base/number';
import TextAreaField from '@cardstack/base/text-area';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { Case } from '@cardstack/catalog/cards/service-desk/case';
import { CASE_STATUSES } from '@cardstack/catalog/cards/service-desk/case';
import {
  isValidIdentifierPattern,
  mintIdentifier,
  RecordIdentifierField,
} from '@cardstack/catalog/fields/record-identifier/record-identifier-field';
import {
  ExternalReferenceField,
  IntegrationReferenceField,
} from '@cardstack/catalog/fields/external-reference/external-reference-field';
import { parseCsvRecords, headerIndex, parseCsvDate } from '../../../utils/csv';
import {
  loaded,
  loadedById,
} from '@cardstack/catalog/cards/service-desk/record-helpers';

export class ImportLegacyDataInput extends CardDef {
  /** The scalable path: the export lives in the realm as a CSV file card, so
      the import has a provenance and can be re-run. */
  @field source = linksTo(() => CsvFileDef, {
    description:
      'A CSV file in the realm (header: subject, status, opened, legacy_id). Preferred over csvText.',
  });
  /** Same file, addressed by URL — what a UI holds after a search or an
      upload. Avoids handing the command a foreign-class instance. */
  @field sourceUrl = contains(StringField, {
    description: 'URL of a CSV file in the realm; alternative to `source`.',
  });
  @field csvText = contains(TextAreaField, {
    description:
      'The legacy export, pasted as CSV text. Expected columns (header row, case-insensitive): subject, status, opened, legacy_id; optional: severity, problem.',
  });
  @field idPattern = contains(StringField, {
    description:
      'Record Identifier pattern for minted ids, e.g. CASE-{yyyy}-{seq4}.',
  });
  @field startSeq = contains(NumberField, {
    description: 'First sequence number to mint. The desk passes its counter.',
  });
  @field systemName = contains(StringField, {
    description:
      'The legacy system, e.g. "Zendesk" — every row keeps its External Reference.',
  });
  @field realm = contains(StringField, {
    description: 'Realm URL to create the cases in.',
  });
}

export class ImportLegacyDataResult extends CardDef {
  @field createdCount = contains(StringField);
  @field failedCount = contains(StringField);
  @field nextSeq = contains(NumberField, {
    description: 'The desk stores this back onto its config counter.',
  });
  @field results = containsMany(StringField, {
    description:
      'One line per row: "ok <id> ← <legacy>" or "row N failed: <why>".',
  });
}

/**
 * Legacy helpdesk export → Case records, honestly.
 *
 * PER-ROW RESULTS: a row whose date is unreadable or whose status is not in
 * the realm's own CASE_STATUSES vocabulary FAILS AND SAYS WHY — never
 * silently skipped, never silently coerced. Dates are calendar days
 * (utils/csv.parseCsvDate), so nothing shifts a day east of UTC. Every
 * created case is minted a Record Identifier in import order and keeps an
 * External Reference back to its legacy id, so "where did this come from" is
 * always answerable.
 */
export default class ImportLegacyDataCommand extends Command<
  typeof ImportLegacyDataInput,
  typeof ImportLegacyDataResult
> {
  static actionVerb = 'Import';
  static displayName = 'Import Legacy Data';

  async getInputType() {
    return ImportLegacyDataInput;
  }

  protected async run(
    input: ImportLegacyDataInput,
  ): Promise<ImportLegacyDataResult> {
    // A realm file wins over pasted text: it is the provenance of record.
    let csvText: string | undefined;
    let sourceName: string | undefined;
    if (input.source || input.sourceUrl) {
      let file = input.source
        ? await loaded(this.commandContext, input.source)
        : await loadedById(this.commandContext, input.sourceUrl);
      csvText = (file?.content as string | undefined)?.trim();
      sourceName = (file?.name as string) ?? file?.title ?? file?.id;
      if (!csvText) {
        throw new Error(
          `${sourceName ?? 'The linked file'} has no CSV content yet — wait for it to index, or paste the rows.`,
        );
      }
    }
    csvText ??= input.csvText?.trim();
    if (!csvText) {
      throw new Error('Link a CSV file (source / sourceUrl) or paste csvText');
    }
    if (!input.realm) {
      throw new Error('realm is required to create the cases');
    }
    // Refuse before the first write: a pattern without {yyyy}/{seqN} would
    // mint the literal text as every case id (seen: 'BAD' × 2).
    if (input.idPattern && !isValidIdentifierPattern(input.idPattern)) {
      throw new Error(
        `idPattern "${input.idPattern}" is invalid — it needs {yyyy} and a {seqN} token, e.g. CASE-{yyyy}-{seq4}.`,
      );
    }
    let rows = parseCsvRecords(csvText);
    let provenance = sourceName ? [`source: ${sourceName}`] : [];
    if (rows.length < 2) {
      throw new Error('CSV needs a header row and at least one data row');
    }
    let idx = headerIndex(rows[0]!.cells);
    for (let col of ['subject', 'status', 'opened', 'legacy_id']) {
      if (idx[col] === undefined) {
        throw new Error(`CSV is missing the "${col}" column`);
      }
    }

    let results: string[] = [...provenance];
    let created = 0;
    let failed = 0;
    let seq = input.startSeq ?? 1;
    for (let n = 1; n < rows.length; n++) {
      let { row: rowNumber, cells: row } = rows[n]!;
      try {
        let subject = row[idx['subject']!]?.trim();
        if (!subject) throw new Error('subject is empty');
        let status = row[idx['status']!]?.trim().toLowerCase();
        if (!status || !CASE_STATUSES.includes(status as any)) {
          throw new Error(
            `status "${status}" is not one of the realm's case statuses (${CASE_STATUSES.join(', ')})`,
          );
        }
        let opened = parseCsvDate(row[idx['opened']!] ?? '');
        let legacyId = row[idx['legacy_id']!]?.trim();
        if (!legacyId) throw new Error('legacy_id is empty');

        let minted = mintIdentifier(input.idPattern, seq);
        let kase = new Case({
          subject,
          status,
          openedOn: opened,
          severity:
            idx['severity'] !== undefined
              ? row[idx['severity']!]?.trim().toLowerCase() || undefined
              : undefined,
          problemStatement:
            idx['problem'] !== undefined
              ? row[idx['problem']!] || undefined
              : undefined,
          caseId: new RecordIdentifierField({
            value: minted,
            pattern: input.idPattern,
            issuedAt: new Date(),
          } as any),
          externalRefs: [
            new ExternalReferenceField({
              system: new IntegrationReferenceField({
                name: input.systemName || 'legacy',
              } as any),
              externalId: legacyId,
              state: status,
              lastSeenAt: new Date(),
            } as any),
          ],
        } as any);
        await new SaveCardCommand(this.commandContext).execute({
          card: kase,
          realm: input.realm,
        } as any);
        seq++;
        created++;
        results.push(`ok ${minted} ← ${legacyId} (${subject})`);
      } catch (e: any) {
        failed++;
        results.push(`row ${rowNumber} failed: ${e?.message ?? e}`);
      }
    }

    return new ImportLegacyDataResult({
      createdCount: String(created),
      failedCount: String(failed),
      nextSeq: seq,
      results,
    });
  }
}
