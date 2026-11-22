import { Command } from '@cardstack/runtime-common';
import { CurlConverterInput } from './curl-converter-input';
import { CurlConverterResult } from './curl-converter-result';
function shellTokens(source: string): string[] {
  const tokens: string[] = [];
  let current = '';
  let quote = '';
  let escaped = false;
  let started = false;
  for (let i = 0; i < source.length; i++) {
    const ch = source[i];
    if (escaped) {
      current += ch;
      escaped = false;
      started = true;
      continue;
    }
    if (ch === String.fromCharCode(92) && quote !== "'") {
      escaped = true;
      started = true;
      continue;
    }
    if (quote) {
      if (ch === quote) quote = '';
      else current += ch;
      started = true;
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      started = true;
      continue;
    }
    if (/\s/.test(ch)) {
      if (started) {
        tokens.push(current);
        current = '';
        started = false;
      }
      continue;
    }
    current += ch;
    started = true;
  }
  if (escaped || quote)
    throw new Error('The cURL command has an unfinished quote or escape.');
  if (started) tokens.push(current);
  return tokens;
}
export class CurlConverterCommand extends Command<
  typeof CurlConverterInput,
  typeof CurlConverterResult
> {
  static actionVerb = 'Convert';
  static displayName = 'Convert cURL to Fetch';
  async getInputType() {
    return CurlConverterInput;
  }
  protected async run(input: CurlConverterInput): Promise<CurlConverterResult> {
    const tokens = shellTokens((input.command ?? '').trim());
    if (tokens[0] === 'curl') tokens.shift();
    if (!tokens.length) throw new Error('Paste a cURL command.');
    let url = '';
    let method = '';
    const data: string[] = [];
    const headers: Record<string, string> = {};
    let getDataInQuery = false;
    let failOnHttpError = false;
    const valueFlags = new Set([
      '-X',
      '--request',
      '-H',
      '--header',
      '-d',
      '--data',
      '--data-raw',
      '--url',
    ]);
    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i];
      if (valueFlags.has(token)) {
        const value = tokens[++i];
        if (value === undefined)
          throw new Error('Missing value after ' + token + '.');
        if (token === '-X' || token === '--request')
          method = value.toUpperCase();
        else if (token === '-H' || token === '--header') {
          const split = value.indexOf(':');
          if (split < 1)
            throw new Error('Headers must use the Name: value format.');
          const existingName = Object.keys(headers).find(
            (name) =>
              name.toLowerCase() === value.slice(0, split).trim().toLowerCase(),
          );
          headers[existingName ?? value.slice(0, split).trim()] = value
            .slice(split + 1)
            .trim();
        } else if (token === '--url') url = value;
        else data.push(value);
      } else if (token === '-I' || token === '--head') method = 'HEAD';
      else if (token === '-G' || token === '--get') getDataInQuery = true;
      else if (
        token === '-f' ||
        token === '--fail' ||
        token === '--fail-with-body'
      )
        failOnHttpError = true;
      else if (
        token === '--compressed' ||
        token === '-s' ||
        token === '-S' ||
        token === '-L' ||
        token === '--location'
      ) {
        // Fetch follows redirects and handles content decompression by default; -s/-S affect only cURL's display.
        continue;
      } else if (token.startsWith('-')) {
        throw new Error(
          'Unsupported cURL option: ' +
            token +
            '. Remove it or convert that option manually.',
        );
      } else if (!url) url = token;
      else throw new Error('This converter handles one URL per cURL command.');
    }
    if (!url) throw new Error('No URL found in the cURL command.');
    let destination: URL;
    try {
      destination = new URL(url);
    } catch {
      throw new Error('The cURL URL must be a complete http or https URL.');
    }
    if (destination.protocol !== 'http:' && destination.protocol !== 'https:')
      throw new Error('Only http and https URLs can be converted.');
    const hasData = data.length > 0;
    const verb = method || (hasData && !getDataInQuery ? 'POST' : 'GET');
    if (hasData && !getDataInQuery && (verb === 'GET' || verb === 'HEAD'))
      throw new Error(
        'This cURL command combines a GET/HEAD method with a request body. Use -G to put -d values in the query string.',
      );
    if (getDataInQuery && (verb === 'HEAD' || (method && method !== 'GET')))
      throw new Error(
        '-G can only be used with GET. Remove -G or change the request method.',
      );
    const hasContentType = Object.keys(headers).some(
      (name) => name.toLowerCase() === 'content-type',
    );
    if (
      hasData &&
      !getDataInQuery &&
      verb !== 'GET' &&
      verb !== 'HEAD' &&
      !hasContentType
    )
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    const lines = [
      'const url = new URL(' + JSON.stringify(destination.toString()) + ');',
    ];
    if (getDataInQuery && hasData) {
      lines.push(
        'const queryParams = new URLSearchParams(' +
          JSON.stringify(data.join('&')) +
          ');',
        'queryParams.forEach((value, key) => url.searchParams.append(key, value));',
      );
    }
    lines.push(
      '',
      'const response = await fetch(url.toString(), {',
      '  method: ' + JSON.stringify(verb) + ',',
    );
    if (Object.keys(headers).length)
      lines.push(
        '  headers: ' +
          JSON.stringify(headers, null, 2)
            .split(String.fromCharCode(10))
            .join(String.fromCharCode(10) + '  ') +
          ',',
      );
    if (hasData && !getDataInQuery && verb !== 'GET' && verb !== 'HEAD')
      lines.push('  body: ' + JSON.stringify(data.join('&')) + ',');
    lines.push('});');
    if (failOnHttpError)
      lines.push(
        '',
        'if (!response.ok) {',
        "  throw new Error('Request failed with HTTP ' + response.status);",
        '}',
      );
    lines.push('', 'const result = await response.text();');
    return new CurlConverterResult({
      output: lines.join(String.fromCharCode(10)),
    });
  }
}
