import {
  CardDef,
  contains,
  containsMany,
  field,
  linksToMany,
  realmURL,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { findCard, getCard } from '@cardstack/catalog/utils/find-card';
import { linkedIds } from '@cardstack/catalog/utils/linked-id';
import { Asset } from '../asset';
import { AssetCategory } from '../asset-category';
import { Location } from '@cardstack/catalog/cards/events/location';
import {
  RecordIdentifierField,
  mintIdentifier,
} from '@cardstack/catalog/fields/record-identifier/record-identifier-field';
import { parseCsv, headerIndex } from '@cardstack/catalog/utils/csv';

export class ImportAssetRegisterInput extends CardDef {
  @field csvText = contains(StringField, {
    description:
      'Header row + rows. Recognised columns: name, category, location, serialNumber, manufacturer, model, status, criticality, notes.',
  });
  @field categories = linksToMany(() => AssetCategory, {
    description: 'Every AssetCategory the CSV might reference.',
  });
  @field locations = linksToMany(() => Location, {
    description: 'Every Location the CSV might reference.',
  });
  @field identifierPattern = contains(StringField, {
    description: 'e.g. "AST-{yyyy}-{seq4}". Defaults to AST-{yyyy}-{seq4}.',
  });
  @field startSeq = contains(NumberField);
  @field realm = contains(StringField, {
    description:
      'Target realm URL; omit to save beside the first linked category or location.',
  });
}

export class ImportAssetRegisterResult extends CardDef {
  @field createdCount = contains(NumberField);
  @field errorCount = contains(NumberField);
  @field skippedCount = contains(NumberField, {
    description:
      'Rows whose serial number already belongs to an Asset in the realm.',
  });
  @field createdIds = containsMany(StringField);
  @field rowErrors = containsMany(StringField, {
    description: '"row N: message" for every row that could not be imported.',
  });
  @field message = contains(StringField);
}

function findByName<T extends { name?: string | null }>(
  pool: readonly (T | null | undefined)[],
  name: string | undefined,
): T | undefined {
  if (!name?.trim()) return undefined;
  let needle = name.trim().toLowerCase();
  return (
    pool.find((c) => c?.name?.trim().toLowerCase() === needle) ?? undefined
  );
}

/**
 * Bulk Asset creation from a CSV export. Not the generic Import Legacy
 * Data command, which creates Cases and carries the Service Desk modules.
 *
 * Row-level failure isolation: a bad row is reported, not a thrown error
 * that aborts the whole file — matching the CSV rule in utils/csv.ts (a
 * cell that can't be read reports itself, it doesn't shift every date after
 * it).
 */
export default class ImportAssetRegisterCommand extends Command<
  typeof ImportAssetRegisterInput,
  typeof ImportAssetRegisterResult
> {
  static actionVerb = 'Import';
  static displayName = 'Import Asset Register';

  async getInputType() {
    return ImportAssetRegisterInput;
  }

  protected async run(
    input: ImportAssetRegisterInput,
  ): Promise<ImportAssetRegisterResult> {
    if (!input.csvText?.trim()) {
      throw new Error('csvText is required');
    }
    let rows = parseCsv(input.csvText);
    if (rows.length < 2) {
      throw new Error('csvText needs a header row plus at least one data row');
    }
    let idx = headerIndex(rows[0]!);
    let load = <T extends CardDef>(ids: string[]) =>
      Promise.all(ids.map((id) => getCard<T>(this.commandContext, id)));
    let categories = (
      await load<AssetCategory>(linkedIds(input, 'categories'))
    ).filter(Boolean);
    let locations = (
      await load<Location>(linkedIds(input, 'locations'))
    ).filter(Boolean);
    let realm =
      input.realm ||
      ([...categories, ...locations] as any[]).find((c) => c?.[realmURL])?.[
        realmURL
      ]?.href;
    let pattern = input.identifierPattern?.trim() || 'AST-{yyyy}-{seq4}';
    let seq = input.startSeq ?? 1;
    let today = new Date();

    let createdIds: string[] = [];
    let rowErrors: string[] = [];
    let skipped = 0;

    let cell = (row: string[], key: string) =>
      idx[key] != null ? row[idx[key]!]?.trim() : undefined;

    for (let r = 1; r < rows.length; r++) {
      let row = rows[r]!;
      try {
        let name = cell(row, 'name');
        if (!name) {
          throw new Error('missing required "name"');
        }
        let categoryName = cell(row, 'category');
        let category = findByName(categories, categoryName);
        if (categoryName && !category) {
          throw new Error(
            `category "${categoryName}" not found among the loaded categories`,
          );
        }
        let locationName = cell(row, 'location');
        let location = findByName(locations, locationName);
        if (locationName && !location) {
          throw new Error(
            `location "${locationName}" not found among the loaded locations`,
          );
        }

        // A re-run skips the rows an earlier run already imported.
        let serialNumber = cell(row, 'serialnumber');
        if (
          serialNumber &&
          realm &&
          (await findCard(this.commandContext, Asset, { serialNumber }, realm))
        ) {
          skipped++;
          continue;
        }

        let asset = new Asset({
          identifier: new RecordIdentifierField({
            value: mintIdentifier(pattern, seq++, today),
            pattern,
            issuedAt: today,
          }),
          name,
          category,
          location,
          serialNumber,
          manufacturer: cell(row, 'manufacturer'),
          model: cell(row, 'model'),
          status: cell(row, 'status') || 'in-service',
          criticality: cell(row, 'criticality')
            ? { value: cell(row, 'criticality') }
            : undefined,
          notes: cell(row, 'notes'),
        } as any);

        let saved = (await new SaveCardCommand(this.commandContext).execute({
          card: asset,
          realm,
        } as any)) as Asset;
        createdIds.push(saved.id);
      } catch (e) {
        rowErrors.push(
          `row ${r + 1}: ${e instanceof Error ? e.message : String(e)}`,
        );
      }
    }

    return new ImportAssetRegisterResult({
      createdCount: createdIds.length,
      errorCount: rowErrors.length,
      skippedCount: skipped,
      createdIds,
      rowErrors,
      message: `${createdIds.length} asset(s) imported, ${skipped} already present, ${rowErrors.length} row(s) failed.`,
    });
  }
}
