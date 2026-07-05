// Shell-out helper for dynamic gates (npx boxel …). Static gates never use this.
import { spawn } from 'node:child_process';

export function runCli(args, { timeoutMs = 120_000, cwd } = {}) {
  return new Promise((resolve) => {
    const child = spawn('npx', args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => child.kill('SIGKILL'), timeoutMs);
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ code, stdout, stderr });
    });
    child.on('error', (err) => {
      clearTimeout(timer);
      resolve({ code: -1, stdout, stderr: String(err) });
    });
  });
}
