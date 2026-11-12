import { codeRef, realmURL } from '@cardstack/runtime-common';

// Realm tempat data dibaca/disimpan. Card yang punya field `dataRealm`
// (PipelineHome) bisa menunjuk ke workspace data terpisah; kalau kosong,
// atau card-nya tidak punya field itu, pakai realm tempat card itu berada.
// Jadi pemasang app dari katalog otomatis memakai workspace mereka sendiri.
export function dataRealmOf(model: any): string | undefined {
  let configured = String(model?.dataRealm ?? '').trim();
  if (configured)
    return configured.endsWith('/') ? configured : `${configured}/`;
  return model?.[realmURL]?.href;
}

// Query getCards dibuat SEKALI di level modul (seperti contoh resmi di
// query-systems.md). Objek query baru tiap render bisa membuat resource
// memuat ulang terus → tampilan "glitch".
const typeQuery = (path: string, name: string) => ({
  // @ts-expect-error import.meta is host-supported
  filter: { type: codeRef(import.meta.url, path, name) },
});

export const QUERIES = {
  quote: typeQuery('./quote', 'Quote'),
  brief: typeQuery('./brief', 'Brief'),
  client: typeQuery('./client', 'Client'),
  serviceItem: typeQuery('./service-item', 'ServiceItem'),
};

// Semua card satu tipe di realm data card ini (resource: .instances terisi bertahap)
export function cardsOf(component: any, query: object) {
  return component.args.context?.getCards(
    component,
    () => query,
    () => [dataRealmOf(component.args.model)],
    { isLive: true },
  );
}

export function instancesOf(resource: unknown): any[] {
  return [...((resource as any)?.instances ?? [])].filter(Boolean);
}
