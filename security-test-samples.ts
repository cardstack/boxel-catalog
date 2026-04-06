/**
 * Sample file with intentional security vulnerabilities for CodeQL testing.
 * DO NOT use any of this code in production.
 */

// 1. DOM-based XSS via innerHTML
// CodeQL rule: js/xss
function renderUserContent(userInput: string) {
  const div = document.createElement('div');
  div.innerHTML = userInput; // VULNERABILITY: unsanitized user input → XSS
  document.body.appendChild(div);
}

// 2. XSS via document.write
// CodeQL rule: js/xss
function writeToPage(query: string) {
  const params = new URLSearchParams(window.location.search);
  const value = params.get(query);
  document.write('<p>' + value + '</p>'); // VULNERABILITY: URL param written directly to DOM
}

// 3. eval() with user-controlled input
// CodeQL rule: js/code-injection
function runUserExpression(expr: string) {
  const result = eval(expr); // VULNERABILITY: arbitrary code execution
  return result;
}

// 4. Open redirect via user-controlled URL
// CodeQL rule: js/open-redirect
function redirectTo(dest: string) {
  const params = new URLSearchParams(window.location.search);
  const target = params.get(dest);
  window.location.href = target!; // VULNERABILITY: unvalidated redirect
}

// 5. postMessage without origin check
// CodeQL rule: js/postmessage-star-origin  (or missing origin validation)
function listenForMessages() {
  window.addEventListener('message', (event) => {
    // VULNERABILITY: no check on event.origin
    const payload = JSON.parse(event.data);
    document.getElementById('output')!.innerHTML = payload.html;
  });
}

// 6. Prototype pollution via merge
// CodeQL rule: js/prototype-pollution
function mergeObjects(target: Record<string, unknown>, source: Record<string, unknown>) {
  for (const key in source) {
    if (typeof source[key] === 'object') {
      (target as any)[key] = mergeObjects((target as any)[key] ?? {}, source[key] as any);
    } else {
      (target as any)[key] = source[key]; // VULNERABILITY: __proto__ key can pollute prototype
    }
  }
  return target;
}
