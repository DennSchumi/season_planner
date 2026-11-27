// Clientseitiger Bild- & PDF-Optimierungs-Helper für Season Planner Web
(function () {
  let pdfJsLoadPromise = null;

  function ensurePdfJs() {
    const workerUrl = new URL('pdfjs/pdf.worker.min.js', document.baseURI).href;
    if (window.pdfjsLib) {
      window.pdfjsLib.GlobalWorkerOptions.workerSrc = workerUrl;
      return Promise.resolve(window.pdfjsLib);
    }
    if (pdfJsLoadPromise) return pdfJsLoadPromise;
    pdfJsLoadPromise = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = new URL('pdfjs/pdf.min.js', document.baseURI).href;
      script.async = true;
      script.onload = () => {
        if (window.pdfjsLib) {
          window.pdfjsLib.GlobalWorkerOptions.workerSrc = workerUrl;
          resolve(window.pdfjsLib);
        } else {
          reject(new Error('pdfjsLib nicht verfügbar'));
        }
      };
      script.onerror = () => reject(new Error('pdf.min.js konnte nicht geladen werden'));
      document.head.appendChild(script);
    });
    return pdfJsLoadPromise;
  }

  function loadImageFromBlob(blob) {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(blob);
      const img = new Image();
      img.onload = () => {
        URL.revokeObjectURL(url);
        resolve(img);
      };
      img.onerror = (err) => {
        URL.revokeObjectURL(url);
        reject(err || new Error('Bild konnte nicht dekodiert werden'));
      };
      img.src = url;
    });
  }

  function canvasToUint8Array(canvas, mime, quality) {
    return new Promise((resolve, reject) => {
      canvas.toBlob(
        async (blob) => {
          if (!blob) {
            reject(new Error('Canvas-Export fehlgeschlagen'));
            return;
          }
          const buf = await blob.arrayBuffer();
          resolve(new Uint8Array(buf));
        },
        mime,
        quality
      );
    });
  }

  /**
   * Skaliert und komprimiert ein Bild clientseitig über ein Offscreen-/HTML-Canvas.
   * @param {Uint8Array} bytes
   * @param {string} mimeType
   * @param {number} maxDimension
   * @param {number} quality (0.1 .. 1.0)
   * @param {boolean} outputPng
   * @returns {Promise<Uint8Array>}
   */
  window.spOptimizeImage = async function (
    bytes,
    mimeType,
    maxDimension,
    quality,
    outputPng
  ) {
    const blob = new Blob([bytes], { type: mimeType || 'image/jpeg' });
    const img = await loadImageFromBlob(blob);
    const srcW = img.naturalWidth || img.width;
    const srcH = img.naturalHeight || img.height;
    if (!srcW || !srcH) return bytes;

    const maxSide = Math.max(srcW, srcH);
    const scale = maxSide > maxDimension ? maxDimension / maxSide : 1.0;
    const dstW = Math.max(1, Math.round(srcW * scale));
    const dstH = Math.max(1, Math.round(srcH * scale));

    const canvas = document.createElement('canvas');
    canvas.width = dstW;
    canvas.height = dstH;
    const ctx = canvas.getContext('2d');
    if (!ctx) return bytes;

    if (!outputPng) {
      ctx.fillStyle = '#FFFFFF';
      ctx.fillRect(0, 0, dstW, dstH);
    }
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(img, 0, 0, dstW, dstH);

    const outMime = outputPng ? 'image/png' : 'image/jpeg';
    return await canvasToUint8Array(canvas, outMime, quality);
  };

  /**
   * Rendert alle Seiten eines großen PDFs per PDF.js in kompakte JPEG-Seiten.
   * @param {Uint8Array} bytes
   * @param {number} maxDimension (px für die längste Seite, z. B. 1650 ≈ 150 DPI A4)
   * @param {number} quality (0.1 .. 1.0)
   * @param {number} maxPages
   * @returns {Promise<Array<{widthPt: number, heightPt: number, bytes: Uint8Array}>>}
   */
  window.spRenderPdfPagesToJpeg = async function (
    bytes,
    maxDimension,
    quality,
    maxPages
  ) {
    const pdfjsLib = await ensurePdfJs();
    const copy = new Uint8Array(bytes);
    const loadingTask = pdfjsLib.getDocument({ data: copy });
    const pdf = await loadingTask.promise;
    const count = Math.min(pdf.numPages, maxPages || 40);
    const results = [];

    try {
      for (let i = 1; i <= count; i++) {
        const page = await pdf.getPage(i);
        const baseViewport = page.getViewport({ scale: 1.0 });
        const widthPt = baseViewport.width;
        const heightPt = baseViewport.height;
        const maxPt = Math.max(widthPt, heightPt);
        const scale = Math.min(2.2, Math.max(0.5, maxDimension / maxPt));
        const viewport = page.getViewport({ scale });

        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(viewport.width));
        canvas.height = Math.max(1, Math.round(viewport.height));
        const ctx = canvas.getContext('2d', { alpha: false });
        ctx.fillStyle = '#FFFFFF';
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        await page.render({ canvasContext: ctx, viewport }).promise;
        const jpegBytes = await canvasToUint8Array(canvas, 'image/jpeg', quality);
        results.push({
          widthPt,
          heightPt,
          bytes: jpegBytes,
        });

        canvas.width = 0;
        canvas.height = 0;
        page.cleanup();
      }
    } finally {
      await pdf.destroy();
    }

    return results;
  };
})();
