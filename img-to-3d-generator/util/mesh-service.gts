// Image-to-mesh service client (Meshy) — the "mesh generation" half of the
// hybrid pipeline. All calls go through the Boxel request-forward proxy so
// the API key stays server-side; the realm server must have
// https://api.meshy.ai/ registered in its proxy_endpoints allowlist (header
// auth). When the endpoint is not allowlisted the first call fails fast and
// the pipeline falls back to procedural freeform (blob / capsule chains).

import SendRequestViaProxyCommand from '@cardstack/boxel-host/tools/send-request-via-proxy';

export const MESHY_BASE = 'https://api.meshy.ai/openapi/v1';

async function proxyJson(
  commandContext: any,
  url: string,
  method: 'GET' | 'POST',
  body?: unknown,
): Promise<any> {
  let { response } = await new SendRequestViaProxyCommand(
    commandContext,
  ).execute({
    url,
    method,
    headers: { 'Content-Type': 'application/json' },
    ...(body !== undefined ? { requestBody: JSON.stringify(body) } : {}),
  } as any);
  if (!response.ok) {
    let detail = (await response.text()).slice(0, 160);
    throw new Error(`mesh service ${response.status}: ${detail}`);
  }
  return response.json();
}

// creates an image-to-3d task and polls it to completion; returns the URL of
// the generated .glb on the service's CDN (caller downloads + persists it)
export async function generateMeshFromImage(
  commandContext: any,
  imageDataUrl: string,
  onLog?: (line: string) => void,
  opts?: { pollIntervalMs?: number; timeoutMs?: number },
): Promise<string> {
  let created = await proxyJson(
    commandContext,
    `${MESHY_BASE}/image-to-3d`,
    'POST',
    {
      image_url: imageDataUrl,
      should_texture: true,
      enable_pbr: true,
    },
  );
  let taskId = created?.result;
  if (!taskId) throw new Error('mesh service did not return a task id');
  onLog?.(`> mesh task ${String(taskId).slice(0, 8)}… queued`);

  let interval = opts?.pollIntervalMs ?? 8000;
  let deadline = Date.now() + (opts?.timeoutMs ?? 5 * 60 * 1000);
  let lastProgress = -1;
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, interval));
    let task = await proxyJson(
      commandContext,
      `${MESHY_BASE}/image-to-3d/${taskId}`,
      'GET',
    );
    let status = task?.status;
    if (typeof task?.progress === 'number' && task.progress !== lastProgress) {
      lastProgress = task.progress;
      onLog?.(`> mesh generation ${task.progress}%`);
    }
    if (status === 'SUCCEEDED') {
      let glb = task?.model_urls?.glb;
      if (!glb) throw new Error('mesh task succeeded but returned no glb url');
      return glb;
    }
    if (status === 'FAILED' || status === 'CANCELED') {
      throw new Error(
        `mesh task ${String(status).toLowerCase()}: ${
          task?.task_error?.message ?? 'no detail'
        }`,
      );
    }
  }
  throw new Error('mesh task timed out');
}
