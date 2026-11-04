// Choreo realm entry. Cards import from this file, never from a hashed build.
import * as build from './builds/choreo-ce91ef7c320e';
export * from './builds/choreo-ce91ef7c320e';
// The build is untyped JS; give Reel a loose type so templates can use its yield.
// ponytail: any-typed Reel, drop when the shared @cardstack/choreo ships Reel with types
export const Reel: any = build.Reel;
