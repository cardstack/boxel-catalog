export function imageDims(src: string): Promise<{ w: number; h: number }> {
  return new Promise((resolve) => {
    let img = new Image();
    img.onload = () =>
      resolve({ w: img.naturalWidth || 800, h: img.naturalHeight || 600 });
    img.onerror = () => resolve({ w: 800, h: 600 });
    img.src = src;
  });
}

export function loadScriptOnce(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[src='${src}']`)) return resolve();
    let s = document.createElement('script');
    s.src = src;
    s.onload = () => resolve();
    s.onerror = () => reject(new Error('Could not load PDF renderer'));
    document.head.appendChild(s);
  });
}

export function loadImageEl(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    let img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('image decode failed'));
    img.src = src;
  });
}

export function withTimeout<T>(
  p: Promise<T>,
  ms: number,
  label: string,
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    let timer = setTimeout(
      () =>
        reject(
          new Error(
            `${label} timed out after ${Math.round(
              ms / 1000,
            )}s — the AI service didn't respond. Check AI credits / connection and try again.`,
          ),
        ),
      ms,
    );
    p.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (e) => {
        clearTimeout(timer);
        reject(e);
      },
    );
  });
}

export async function gridOverlay(
  dataUrl: string,
  rect: { x: number; y: number; w: number; h: number },
): Promise<string> {
  let img: HTMLImageElement;
  try {
    img = await loadImageEl(dataUrl);
  } catch {
    return dataUrl;
  }
  let nw = img.naturalWidth || 800;
  let nh = img.naturalHeight || 600;
  let MAX = 1400;
  let scale = Math.min(1, MAX / Math.max(nw, nh));
  let w = Math.max(1, Math.round(nw * scale));
  let h = Math.max(1, Math.round(nh * scale));
  let canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  let ctx = canvas.getContext('2d');
  if (!ctx) return dataUrl;
  ctx.drawImage(img, 0, 0, w, h);
  let N = 20;
  ctx.strokeStyle = 'rgba(220,40,40,0.4)';
  ctx.lineWidth = Math.max(1, w / 1100);
  ctx.fillStyle = 'rgba(220,40,40,0.95)';
  let fs = Math.max(10, Math.round(w / 80));
  ctx.font = `bold ${fs}px sans-serif`;
  for (let i = 0; i <= N; i++) {
    let px = (w * i) / N;
    let py = (h * i) / N;
    ctx.beginPath();
    ctx.moveTo(px, 0);
    ctx.lineTo(px, h);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(0, py);
    ctx.lineTo(w, py);
    ctx.stroke();
    ctx.fillText(String(Math.round(rect.x + (rect.w * i) / N)), px + 3, fs + 2);
    ctx.fillText(String(Math.round(rect.y + (rect.h * i) / N)), 3, py + fs + 2);
  }
  return canvas.toDataURL('image/png');
}

export async function renderPdfToPng(file: File): Promise<string> {
  let base = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174';
  await loadScriptOnce(`${base}/pdf.min.js`);
  let pdfjs = (window as any).pdfjsLib;
  if (!pdfjs) throw new Error('PDF renderer unavailable');
  pdfjs.GlobalWorkerOptions.workerSrc = `${base}/pdf.worker.min.js`;
  let data = await file.arrayBuffer();
  let pdf = await pdfjs.getDocument({ data }).promise;
  let page = await pdf.getPage(1);
  let viewport = page.getViewport({ scale: 2 });
  let canvas = document.createElement('canvas');
  canvas.width = viewport.width;
  canvas.height = viewport.height;
  let context = canvas.getContext('2d');
  await page.render({ canvasContext: context, viewport }).promise;
  return canvas.toDataURL('image/png');
}
