// The contact sheet the refine pass looks at: the reference photo beside the
// current render from several angles, packed into one image so the model can
// compare them in a single glance.

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    let img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('could not load comparison image'));
    img.src = src;
  });
}

// packs the reference beside one or more labeled render angles into a
// single sheet — the model reviews exactly one image per round, but sees the
// build from every side (3D errors hide from single angles)
export async function composeComparison(
  referenceDataUrl: string,
  renderDataUrls: string | string[],
  opts?: { firstIsReferenceAngle?: boolean },
): Promise<string> {
  let renders = Array.isArray(renderDataUrls)
    ? renderDataUrls
    : [renderDataUrls];
  let images = await Promise.all([referenceDataUrl, ...renders].map(loadImage));
  const H = renders.length > 1 ? 384 : 512;
  const LABEL = 22;
  const GAP = 6;
  let angleLabels = opts?.firstIsReferenceAngle
    ? ['RENDER @ REF ANGLE', 'RENDER FRONT', 'RENDER SIDE', 'RENDER 3/4']
    : ['RENDER FRONT', 'RENDER SIDE', 'RENDER 3/4'];
  let labels = [
    'REFERENCE',
    ...(renders.length > 1 ? angleLabels.slice(0, renders.length) : ['RENDER']),
  ];
  let widths = images.map((img) =>
    Math.max(1, Math.round((img.width / img.height) * H)),
  );
  let canvas = document.createElement('canvas');
  canvas.width = widths.reduce((a, b) => a + b, 0) + GAP * (images.length - 1);
  canvas.height = H + LABEL;
  let ctx = canvas.getContext('2d')!;
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  let x = 0;
  for (let i = 0; i < images.length; i++) {
    ctx.fillStyle = '#111111';
    ctx.font = '700 13px Arial';
    ctx.textBaseline = 'top';
    ctx.fillText(labels[i] ?? '', x + 4, 4);
    ctx.drawImage(images[i], x, LABEL, widths[i], H);
    x += widths[i] + GAP;
  }
  return canvas.toDataURL('image/jpeg', 0.85);
}
