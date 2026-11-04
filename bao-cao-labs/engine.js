// Shared report engine: build a PTIT-formatted .docx from Mau.docx template.
// Keeps cover page + styles + TOC, replaces body content from a content array C.
// Supports PNG and JPEG images. Usage: require('./engine').render(C, {imgDir, out}).
const fs = require('fs');
const path = require('path');
const JSZip = require('jszip');

const ROOT = path.resolve(__dirname, '..');
const TEMPLATE = path.join(ROOT, 'Mẫu.docx');

// ---- content helpers (same DSL as bao-cao-tuan-1) ----
function makeC() {
  const C = [];
  return {
    C,
    h1: t => C.push({ t: 'h1', v: t }),
    h2: t => C.push({ t: 'h2', v: t }),
    h3: t => C.push({ t: 'h3', v: t }),
    p: t => C.push({ t: 'p', v: t }),
    b: (...a) => a.forEach(v => C.push({ t: 'b', v })),
    code: t => C.push({ t: 'code', v: t }),
    img: (f, cap) => C.push({ t: 'img', f, cap }),
    table: (cols, widths, rows) => C.push({ t: 'table', cols, widths, rows }),
  };
}

// ---- XML helpers ----
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const MONO = '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/>';
const run = (t, rpr = '') => `<w:r>${rpr ? `<w:rPr>${rpr}</w:rPr>` : ''}<w:t xml:space="preserve">${esc(t)}</w:t></w:r>`;
const inline = t => t.split(/(`[^`]+`)/).filter(Boolean).map(s =>
  s.startsWith('`') ? run(s.slice(1, -1), MONO + '<w:sz w:val="24"/>') : run(s)).join('');
const para = (style, inner, extra = '') => `<w:p><w:pPr><w:pStyle w:val="${style}"/>${extra}</w:pPr>${inner}</w:p>`;
const NEWPAGE = '<w:pageBreakBefore/>';
const field = (style, instr, ppr = '') =>
  `<w:p><w:pPr><w:pStyle w:val="${style}"/>${ppr}</w:pPr><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve">${instr}</w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r>${run('Nhấn chuột phải, chọn Update Field để cập nhật.')}<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>`;

const TEXT_W_EMU = Math.round((11907 - 1021 - 1418) / 1440 * 914400) - 60000;
function pngSize(buf) { return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) }; }
function jpgSize(buf) {
  let o = 2;
  while (o < buf.length) {
    if (buf[o] !== 0xFF) { o++; continue; }
    const m = buf[o + 1];
    if (m >= 0xC0 && m <= 0xCF && m !== 0xC4 && m !== 0xC8 && m !== 0xCC) {
      return { h: buf.readUInt16BE(o + 5), w: buf.readUInt16BE(o + 7) };
    }
    o += 2 + buf.readUInt16BE(o + 2);
  }
  return { w: 1600, h: 900 };
}
function imgSize(buf, file) {
  if (/\.png$/i.test(file)) return pngSize(buf);
  return jpgSize(buf);
}

const REFS = [
  'Labtainers - Lab Designer User Guide, Naval Postgraduate School (https://github.com/mfthomps/Labtainers).',
  'Aqua Security - Trivy documentation (https://trivy.dev/); Anchore Syft - SBOM (https://github.com/anchore/syft).',
  'OWASP Core Rule Set & Coraza WAF (https://coreruleset.org/, https://coraza.io/).',
  'Kubernetes RBAC & Pod Security Standards (https://kubernetes.io/docs/reference/access-authn-authz/rbac/).',
  'MITRE ATT&CK: T1552 Unsecured Credentials, T1195 Supply Chain, T1078 Valid Accounts, T1611 Escape to Host.',
];

async function render(C, opts) {
  const IMG_DIR = opts.imgDir;
  const OUT = opts.out;
  const zip = await JSZip.loadAsync(fs.readFileSync(TEMPLATE));
  let doc = await zip.file('word/document.xml').async('string');
  let rels = await zip.file('word/_rels/document.xml.rels').async('string');

  const bodyStart = doc.indexOf('<w:body>') + '<w:body>'.length;
  const tocTitle = doc.indexOf('MỤC LỤC</w:t>');
  const cut = doc.lastIndexOf('<w:p ', tocTitle);
  const lastSect = doc.lastIndexOf('<w:sectPr');
  const head = doc.slice(0, cut), tail = doc.slice(lastSect);
  if (!head.includes('<w:sectPr') || cut < bodyStart) throw new Error('Khong tim thay ranh gioi trang bia');

  let rid = 900, docPr = 5000, figs = 0, missing = [];
  const media = [];
  const out = [];
  out.push(para('BTL-H0', run('MỤC LỤC')));
  out.push(field('TOC1', ' TOC \\h \\z \\u \\t "BTL-H1,1,BTL-H2,2,BTL-H3,3,BTL-H0,1" '));
  out.push(para('BTL-H0', run('DANH MỤC CÁC HÌNH VẼ'), NEWPAGE));
  out.push(field('TableofFigures', ' TOC \\f F \\h \\z \\t "BTL-Hinh" \\c ', '<w:tabs><w:tab w:val="right" w:leader="dot" w:pos="9458"/></w:tabs>'));

  for (const c of C) {
    if (c.t === 'h1') out.push(para('BTL-H1', run(c.v), NEWPAGE));
    else if (c.t === 'h2') out.push(para('BTL-H2', run(c.v)));
    else if (c.t === 'h3') out.push(para('BTL-H3', run(c.v)));
    else if (c.t === 'p') out.push(para('BTL-Text', inline(c.v)));
    else if (c.t === 'b') out.push(para('BTL-Bullet1', inline(c.v)));
    else if (c.t === 'code') {
      const lines = c.v.split('\n');
      const inner = lines.map((l, i) => (i ? '<w:r><w:br/></w:r>' : '') + run(l, MONO + '<w:sz w:val="20"/>')).join('');
      out.push(para('BTL-Text', inner, '<w:keepNext/><w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/><w:spacing w:before="60" w:after="120" w:line="240" w:lineRule="auto"/><w:ind w:left="284" w:firstLine="0"/><w:jc w:val="left"/>'));
    } else if (c.t === 'img') {
      const fp = path.join(IMG_DIR, c.f);
      const center = '<w:keepNext/><w:spacing w:before="120" w:after="0"/><w:ind w:firstLine="0"/><w:jc w:val="center"/>';
      if (fs.existsSync(fp)) {
        const buf = fs.readFileSync(fp), { w, h } = imgSize(buf, c.f);
        const cx = TEXT_W_EMU, cy = Math.round(cx * h / w), id = 'rId' + (++rid), n = ++docPr;
        const name = `rpt_${c.f}`;
        media.push({ name, buf, id });
        out.push(para('BTL-Text', `<w:r><w:rPr><w:noProof/></w:rPr><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="${cx}" cy="${cy}"/><wp:effectExtent l="0" t="0" r="0" b="0"/><wp:docPr id="${n}" name="${esc(c.f)}"/><wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="${n}" name="${esc(c.f)}"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="${id}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${cx}" cy="${cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>`, center));
      } else {
        missing.push(c.f);
        out.push(para('BTL-Text', run(`[Chèn ảnh: ${c.f}]`, '<w:color w:val="C00000"/><w:b/>'), center));
      }
      figs++;
      out.push(para('BTL-Hinh', run(c.cap)));
    } else if (c.t === 'table') {
      const total = c.widths.reduce((a, x) => a + x, 0);
      const cell = (txt, w, hdr) => `<w:tc><w:tcPr><w:tcW w:w="${w}" w:type="dxa"/>${hdr ? '<w:shd w:val="clear" w:color="auto" w:fill="D9E2F3"/>' : ''}<w:vAlign w:val="center"/></w:tcPr>${para('BTL-Text', hdr ? run(txt, '<w:b/>') : inline(txt), '<w:spacing w:before="40" w:after="40"/><w:ind w:firstLine="0"/><w:jc w:val="' + (hdr ? 'center' : 'left') + '"/>')}</w:tc>`;
      const row = (r, hdr) => `<w:tr>${r.map((x, i) => cell(x, c.widths[i], hdr)).join('')}</w:tr>`;
      out.push(`<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="${total}" w:type="dxa"/><w:jc w:val="center"/><w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="1" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/></w:tblPr><w:tblGrid>${c.widths.map(x => `<w:gridCol w:w="${x}"/>`).join('')}</w:tblGrid>${row(c.cols, true)}${c.rows.map(r => row(r, false)).join('')}</w:tbl>`);
      out.push(para('BTL-Text', ''));
    }
  }
  out.push(para('BTL-H0', run('TÀI LIỆU THAM KHẢO'), NEWPAGE));
  for (const r of REFS) out.push(para('BTL-NumerRef', run(r), '<w:jc w:val="left"/>'));

  doc = head + out.join('') + tail;

  for (const m of media) {
    zip.file(`word/media/${m.name}`, m.buf);
    rels = rels.replace('</Relationships>', `<Relationship Id="${m.id}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/${m.name}"/></Relationships>`);
  }
  const used = new Set([...doc.matchAll(/r:(?:embed|id|link)="([^"]+)"/g)].map(m => m[1]));
  rels = rels.replace(/<Relationship [^>]*Type="[^"]*\/image"[^>]*\/>/g, rel => {
    const id = rel.match(/Id="([^"]+)"/)[1], tgt = rel.match(/Target="([^"]+)"/)[1];
    if (used.has(id)) return rel;
    zip.remove('word/' + tgt);
    return '';
  });
  zip.file('word/document.xml', doc);
  zip.file('word/_rels/document.xml.rels', rels);
  let ct = await zip.file('[Content_Types].xml').async('string');
  if (!/Extension="png"/i.test(ct)) ct = ct.replace('<Default ', '<Default Extension="png" ContentType="image/png"/><Default ');
  if (!/Extension="jpg"/i.test(ct)) ct = ct.replace('<Default ', '<Default Extension="jpg" ContentType="image/jpeg"/><Default ');
  if (!/Extension="jpeg"/i.test(ct)) ct = ct.replace('<Default ', '<Default Extension="jpeg" ContentType="image/jpeg"/><Default ');
  zip.file('[Content_Types].xml', ct);

  fs.writeFileSync(OUT, await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' }));
  console.log(`OK ${path.basename(OUT)}  hinh: ${figs}, da chen: ${media.length}, thieu: ${missing.length ? missing.join(', ') : 'khong'}`);
}

module.exports = { render, makeC };
