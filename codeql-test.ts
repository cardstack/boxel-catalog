// codeql-validation: test file to verify CodeQL captures js/code-injection — remove before merge
export function testCodeInjection() {
  const result = eval(location.search);
  return result;
}
