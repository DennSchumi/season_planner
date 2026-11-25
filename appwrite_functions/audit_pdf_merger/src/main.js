import { Client, Storage } from 'node-appwrite';
import { PDFDocument, StandardFonts, rgb } from 'pdf-lib';

function sanitizeWinAnsi(str) {
  return String(str || '')
    .replace(/[\r\n\t]+/g, ' ')
    .replace(/–|—/g, '-')
    .replace(/„|“|”/g, '"')
    .replace(/‚|‘|’/g, "'")
    .replace(/[^\x20-\xFF]/g, '?');
}

function isPdfBuffer(buf) {
  if (!buf || buf.length < 5) return false;
  return (
    buf[0] === 0x25 && // %
    buf[1] === 0x50 && // P
    buf[2] === 0x44 && // D
    buf[3] === 0x46 && // F
    buf[4] === 0x2d    // -
  );
}

function isPngBuffer(buf) {
  if (!buf || buf.length < 8) return false;
  return (
    buf[0] === 0x89 &&
    buf[1] === 0x50 &&
    buf[2] === 0x4e &&
    buf[3] === 0x47
  );
}

function isJpgBuffer(buf) {
  if (!buf || buf.length < 3) return false;
  return buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff;
}

export default async ({ req, res, error }) => {
  try {
    const payload =
      typeof req.body === 'string'
        ? JSON.parse(req.body || '{}')
        : (req.body || {});

    const basePdfBase64 = payload.basePdfBase64 || '';
    const attachments = Array.isArray(payload.attachments)
      ? payload.attachments
      : [];

    if (!basePdfBase64) {
      return res.json({ ok: false, error: 'basePdfBase64 fehlt.' }, 400);
    }

    const apiKey =
      req.headers?.['x-appwrite-key'] || process.env.APPWRITE_API_KEY || '';
    const client = new Client()
      .setEndpoint(
        process.env.APPWRITE_FUNCTION_API_ENDPOINT ||
          'https://appwrite.tragegurt.com/v1'
      )
      .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID || 'tragegurt')
      .setKey(apiKey);

    const storage = new Storage(client);

    const baseBytes = Buffer.from(basePdfBase64, 'base64');
    const mergedPdf = await PDFDocument.load(baseBytes);
    const fontBold = await mergedPdf.embedFont(StandardFonts.HelveticaBold);
    const fontRegular = await mergedPdf.embedFont(StandardFonts.Helvetica);

    const A4_W = 595.28;
    const A4_H = 841.89;
    const accent = rgb(0.357, 0.239, 0.961);
    const darkInk = rgb(0.07, 0.08, 0.10);
    const muted = rgb(0.42, 0.45, 0.50);
    const lineCol = rgb(0.86, 0.87, 0.89);

    let attachedCount = 0;
    const warnings = [];

    for (const group of attachments) {
      const appendixNumber = group.appendixNumber ?? '';
      const memberName = sanitizeWinAnsi(group.memberName || 'Mitarbeiter');
      const files = Array.isArray(group.files) ? group.files : [];
      if (files.length === 0) continue;

      // Deck-/Trennseite pro Person (Anhang X)
      const divider = mergedPdf.addPage([A4_W, A4_H]);
      divider.drawRectangle({
        x: 40,
        y: A4_H - 135,
        width: A4_W - 80,
        height: 75,
        color: rgb(0.933, 0.918, 0.996),
        borderColor: accent,
        borderWidth: 1,
      });
      divider.drawText(sanitizeWinAnsi(`ANHANG ${appendixNumber}`), {
        x: 56,
        y: A4_H - 86,
        size: 11,
        font: fontBold,
        color: accent,
      });
      divider.drawText(memberName, {
        x: 56,
        y: A4_H - 114,
        size: 20,
        font: fontBold,
        color: darkInk,
      });
      divider.drawText(
        sanitizeWinAnsi(
          `Nachweise (${files.length} ${files.length === 1 ? 'Dokument' : 'Dokumente'})`
        ),
        {
          x: 42,
          y: A4_H - 168,
          size: 12,
          font: fontBold,
          color: darkInk,
        }
      );

      let listY = A4_H - 194;
      for (let i = 0; i < files.length; i++) {
        const f = files[i];
        const expText = f.expiresAt ? ` (gültig bis ${f.expiresAt})` : '';
        const label = sanitizeWinAnsi(
          `${i + 1}. ${f.documentType || 'Nachweis'}${f.title && f.title !== f.documentType ? ' - ' + f.title : ''}${expText}`
        );
        divider.drawText(label, {
          x: 50,
          y: listY,
          size: 10.5,
          font: fontRegular,
          color: darkInk,
        });
        listY -= 18;
        if (listY < 60) break;
      }

      for (const f of files) {
        const bucketId = f.bucketId || 'qualification_documents';
        const fileId = f.fileId || '';
        const docLabel = sanitizeWinAnsi(
          `Anhang ${appendixNumber} - ${memberName} - ${f.documentType || 'Nachweis'}${f.expiresAt ? ' (gültig bis ' + f.expiresAt + ')' : ''}`
        );
        if (!fileId) continue;

        try {
          const raw = await storage.getFileView({ bucketId, fileId });
          const buf = Buffer.from(raw);

          if (isPdfBuffer(buf)) {
            const srcDoc = await PDFDocument.load(buf, {
              ignoreEncryption: true,
            });
            const pageIndices = srcDoc.getPageIndices();
            const copiedPages = await mergedPdf.copyPages(srcDoc, pageIndices);
            for (const p of copiedPages) {
              const { width, height } = p.getSize();
              // Dezente Anhangs-Kopfzeile oben auf jeder eingebundenen PDF-Seite
              p.drawText(docLabel.slice(0, 95), {
                x: 24,
                y: height - 16,
                size: 8,
                font: fontBold,
                color: muted,
              });
              mergedPdf.addPage(p);
            }
            attachedCount++;
          } else if (isPngBuffer(buf) || isJpgBuffer(buf)) {
            const img = isPngBuffer(buf)
              ? await mergedPdf.embedPng(buf)
              : await mergedPdf.embedJpg(buf);

            const page = mergedPdf.addPage([A4_W, A4_H]);
            page.drawText(docLabel.slice(0, 95), {
              x: 36,
              y: A4_H - 36,
              size: 10,
              font: fontBold,
              color: accent,
            });
            page.drawLine({
              start: { x: 36, y: A4_H - 44 },
              end: { x: A4_W - 36, y: A4_H - 44 },
              thickness: 0.7,
              color: lineCol,
            });

            const maxW = A4_W - 72;
            const maxH = A4_H - 92;
            const scale = Math.min(maxW / img.width, maxH / img.height, 1);
            const drawW = img.width * scale;
            const drawH = img.height * scale;
            const drawX = (A4_W - drawW) / 2;
            const drawY = A4_H - 56 - drawH;

            page.drawImage(img, {
              x: drawX,
              y: drawY,
              width: drawW,
              height: drawH,
            });
            attachedCount++;
          } else {
            warnings.push(
              `${memberName} (${f.documentType || f.fileName}): Nicht unterstütztes Dateiformat.`
            );
          }
        } catch (fileErr) {
          warnings.push(
            `${memberName} (${f.documentType || f.fileName}): Konnte nicht eingebettet werden.`
          );
          error(`Attachment ${fileId} error: ${String(fileErr)}`);
        }
      }
    }

    const outBytes = await mergedPdf.save();
    return res.json({
      ok: true,
      pdfBase64: Buffer.from(outBytes).toString('base64'),
      attachedCount,
      warnings,
    });
  } catch (e) {
    error(String(e));
    return res.json(
      { ok: false, error: `PDF-Zusammenführung fehlgeschlagen: ${String(e)}` },
      500
    );
  }
};
