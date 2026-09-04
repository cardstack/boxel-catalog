export function arrayBufferToBase64(buffer: ArrayBuffer): string {
  let binary = '';
  let bytes = new Uint8Array(buffer);
  // Chunk to avoid quadratic string concatenation and the call-stack/argument
  // limit of String.fromCharCode.apply on large buffers (floor plan uploads
  // allow up to 25MB).
  let chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(
      null,
      Array.from(bytes.subarray(i, i + chunk)) as unknown as number[],
    );
  }
  return btoa(binary);
}
