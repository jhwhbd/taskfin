// gen-splash.cjs — 批量生成 ezBookkeeping 42 个设备启动图（TaskFIN 品牌）
//
// 设计规范（沿用上游）：
//   - 纯白背景 (#FFFFFF)
//   - 居中放置 TaskFIN logo（SVG 矢量源）
//   - logo 下方显示 "TaskFIN" 文字（#999999，OpenSans）
//   - logo 尺寸 = 短边 × 18%
//   - 文字尺寸 = logo 尺寸 × 22%
//
// 用法：NODE_PATH=<workspace>/node_modules node scripts/gen-splash.cjs
// 前提：branding/taskfin.svg 存在；node_modules 含 @resvg/resvg-js + opentype.js

const fs   = require('fs');
const path = require('path');
const { Resvg } = require('@resvg/resvg-js');
const opentype = require('opentype.js');

const ROOT    = path.resolve(__dirname, '..');
const SRC_DIR = path.join(ROOT, 'vendor', 'ezbookkeeping', 'public', 'img', 'splash_screens');
const LOGO_SVG = path.join(ROOT, 'branding', 'taskfin.svg');
const FONT    = path.join(ROOT, 'branding', 'fonts', 'OpenSans-SemiBold.ttf');

const BG_COLOR     = '#FFFFFF';
const TEXT_COLOR   = '#999999';
const LOGO_RATIO   = 0.18;   // logo 占短边的比例
const TEXT_RATIO   = 0.22;   // 文字高度占 logo 高度的比例
const GAP_RATIO    = 0.30;   // 文字与 logo 的间距占 logo 高度的比例

// ---------- 加载字体 ----------
const font = opentype.parse(fs.readFileSync(FONT));

// ---------- 读取原始文件名列表（保持精确命名） ----------
const files = fs.readdirSync(SRC_DIR).filter(f => f.endsWith('.png')).sort();
console.log(`[splash] 共 ${files.length} 个启动图待生成`);

// ---------- 对每个分辨率构建 SVG 并渲染 ----------
let ok = 0, fail = 0;

for (const fname of files) {
  try {
    // 从现有文件取尺寸（保证与上游完全一致）
    const origBuf = fs.readFileSync(path.join(SRC_DIR, fname));
    // 快速解析 PNG 头取宽高（避免依赖 image-size 解析大图）
    const dims = pngDimensions(origBuf);
    if (!dims) { console.warn(`[WARN] 无法解析 ${fname} 尺寸，跳过`); fail++; continue; }
    const { w, h } = dims;

    const shortSide = Math.min(w, h);
    const logoPx   = Math.round(shortSide * LOGO_RATIO);
    const textPx   = Math.round(logoPx * TEXT_RATIO);
    const gapPx    = Math.round(logoPx * GAP_RATIO);

    // 构建 launch-screen SVG
    const svg = buildLaunchSvg(w, h, logoPx, textPx, gapPx);

    // resvg 渲染
    const resvg = new Resvg(svg, {
      fitTo: { mode: 'width', value: w },   // 已是精确像素
      font: { loadSystemFonts: false },
    });
    const pngData = resvg.render().asPng();

    // 覆盖原文件
    fs.writeFileSync(path.join(SRC_DIR, fname), pngData);
    ok++;
  } catch (e) {
    console.error(`[ERR] ${fname}: ${e.message}`);
    fail++;
  }
}

console.log(`\n[splash] 完成：${ok} 成功 / ${fail} 失败`);

// ========== 内部函数 ==========

function buildLaunchSvg(W, H, logoSize, textSize, gap) {
  // logo 居中
  const logoX = (W - logoSize) / 2;
  const logoY = (H - logoSize - gap - textSize) / 2;  // 整体(logo+文字)垂直居中

  // 文字居中（用 opentype 测量实际宽度）
  const textPath = font.getPath('TaskFIN', 0, 0, textSize);
  const tBb = textPath.getBoundingBox();
  const textW = tBb.x2 - tBb.x1;
  const textX = (W - textW) / 2 - tBb.x1;
  const textY = logoY + logoSize + gap + textSize * 0.78;  // baseline 调整

  // 转 path d 字符串（用 <g transform> 避免数值问题）
  const txLogo = logoX - (tBb === undefined ? 0 : 0);  // logo 直接用 <image> 或内联 svg
  // 实际上我们直接嵌入 taskfin.svg 的内容并缩放
  const logoSvgContent = fs.readFileSync(LOGO_SVG, 'utf8')
    .replace(/<svg[^>]*>/, '')
    .replace(/<\/svg>\s*$/, '');

  // 文字路径转 d
  const textD = textPath.toPathData(3);

  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">`,
    `  <rect width="${W}" height="${H}" fill="${BG_COLOR}"/>`,
    `  <!-- logo -->`,
    `  <g transform="translate(${logoX},${logoY}) scale(${logoSize/512})">`,
    logoSvgContent,
    `  </g>`,
    `  <!-- label -->`,
    `  <path d="${textD}" fill="${TEXT_COLOR}" transform="translate(${textX},${textY})"/>`,
    `</svg>`
  ].join('\n');
}

// ---------- 最小化 PNG 尺寸解析（读 IHDR，不依赖库） ----------
function pngDimensions(buf) {
  // PNG signature: 8 bytes, then IHDR chunk
  if (buf.length < 24 || buf[0] !== 0x89) return null;
  if (buf.toString('ascii', 1, 4) !== 'PNG') return null;
  // find IHDR (should be first chunk after signature)
  const len = buf.readUInt32BE(8);
  const type = buf.toString('ascii', 12, 16);
  if (type !== 'IHDR') return null;
  const w = buf.readUInt32BE(16);
  const h = buf.readUInt32BE(20);
  return { w, h };
}
