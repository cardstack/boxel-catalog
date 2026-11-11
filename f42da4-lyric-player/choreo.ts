// Choreo realm entry. Cards import from this file, never from a hashed build.
import * as build from './builds/choreo-ce91ef7c320e';
export * from './builds/choreo-ce91ef7c320e';
// The build is untyped JS; give its components loose types so templates type-check.
// ponytail: any-typed Reel/Lyric, drop when the shared @cardstack/choreo ships them with types
export const Reel: any = build.Reel;
export const Lyric: any = build.Lyric;
