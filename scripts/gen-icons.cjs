#!/usr/bin/env node
/**
 * gen-icons.cjs — 用开源字体把 "T-FIN" 生成全套品牌图标。
 *
 * 流程：
 *   1. opentype.js 把文字转成矢量路径（最终 SVG 不含字体，零版权风险）。
 *   2. @resvg/resvg-js 把路径 SVG 栅格化成各尺寸 PNG。
 *   3. png-to-ico 合成多尺寸 favicon.ico。
 *   4. 把产物铺到 vendored 的 Vikunja / ezBookkeeping 前端目录（对应「从源码构建」部署）。
 *
 * 字体：branding/fonts/OpenSans-SemiBold.ttf（Apache 2.0，已随仓库提供）。
 * 颜色：紫色 #6C5CE7。
 *
 * 重新运行：node scripts/gen-icons.cjs
 */
const fs = require('fs');
const path = require('path');
const opentype = require('opentype.js');
const { Resvg } = require('@resvg/resvg-js');
const pngToIco = require('png-to-ico').default || require('png-to-ico');

const ROOT = path.resolve(__dirname, '..');
const FONT = path.join(ROOT, 'branding', 'fonts', 'OpenSans-SemiBold.ttf');
const TEXT = 'T-FIN';
const COLOR = '#6C5CE7';
const CANVAS = 512;

// 加载字体（opentype.js 新 API：parse 同步读取的 buffer）
const font = opentype.parse(fs.readFileSync(FONT));

// ---------- 1. 文字 -> 路径 SVG ----------
function buildSvg(fill, fit /* 0..1, 内容占画布比例 */, noFill) {
  void font; // 已在模块级加载
  let size = 300;
  let p = font.getPath(TEXT, 0, 0, size);
  let bb = p.getBoundingBox();
  const bw = bb.x2 - bb.x1;
  const bh = bb.y2 - bb.y1;
  const targetW = CANVAS * (fit || 1) - 40 * (fit || 1); // 两侧留白
  const scale = targetW / bw;
  size = size * scale;
  p = font.getPath(TEXT, 0, 0, size);
  bb = p.getBoundingBox();
  const tx = (CANVAS - (bb.x2 - bb.x1)) / 2 - bb.x1;
  const ty = (CANVAS - (bb.y2 - bb.y1)) / 2 - bb.y1;
  const d = p.toPathData(3);
  const fillAttr = noFill ? '' : ` fill="${fill}"`;
  // 用 <g transform> 平移，避免依赖 Path.transform
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${CANVAS} ${CANVAS}" width="${CANVAS}" height="${CANVAS}"><g transform="translate(${tx.toFixed(2)},${ty.toFixed(2)})"><path d="${d}"${fillAttr}/></g></svg>`;
}

const svgColor = buildSvg(COLOR, 1.0);          // 标准彩色版（内容占满，两侧留白）
const svgMono = buildSvg('#000000', 1.0);  // safari-pinned：纯黑单色（Safari 固定标签蒙版需实体填充，避免空白）
const svgMask = buildSvg(COLOR, 0.8);            // maskable：内容收进中央 80% 安全区

fs.mkdirSync(path.join(ROOT, 'branding'), { recursive: true });
fs.writeFileSync(path.join(ROOT, 'branding', 'taskfin.svg'), svgColor);
fs.writeFileSync(path.join(ROOT, 'branding', 'taskfin-mono.svg'), svgMono);
console.log('[svg] branding/taskfin.svg / taskfin-mono.svg 已生成');

// ---------- 2. 栅格化 ----------
function raster(svg, size) {
  const r = new Resvg(svg, { fitTo: { mode: 'width', value: size } });
  return r.render().asPng();
}
const SIZES = [16, 32, 48, 60, 64, 76, 96, 120, 128, 144, 150, 152, 180, 192, 256, 512];
const buildDir = path.join(ROOT, 'branding', 'build');
fs.mkdirSync(buildDir, { recursive: true });
const png = {}; // size -> buffer
for (const s of SIZES) png[s] = raster(svgColor, s);
const pngMask = raster(svgMask, 512);
const pngMono = raster(svgMono, 96);
for (const s of SIZES) fs.writeFileSync(path.join(buildDir, `tf-${s}.png`), png[s]);
fs.writeFileSync(path.join(buildDir, 'tf-maskable-512.png'), pngMask);
fs.writeFileSync(path.join(buildDir, 'tf-badge-mono-96.png'), pngMono);
console.log(`[png] ${SIZES.length} 个尺寸 + maskable + badge 已生成至 branding/build/`);

// ---------- 3. favicon.ico ----------
(async () => {
const icoSizes = [16, 32, 48, 64, 128, 256];
const icoBuf = await pngToIco(icoSizes.map((s) => png[s]));
fs.writeFileSync(path.join(buildDir, 'tf-favicon.ico'), icoBuf);
console.log('[ico] branding/build/tf-favicon.ico 已生成');

// ---------- 4. 铺到 vendored 前端目录 ----------
const V = path.join(ROOT, 'vendor');
const targets = [
  // [源 buffer, 目标相对 vendor 的路径]
  [icoBuf, 'vikunja/frontend/public/favicon.ico'],
  [png[16], 'vikunja/frontend/public/images/icons/favicon-16x16.png'],
  [png[32], 'vikunja/frontend/public/images/icons/favicon-32x32.png'],
  [png[32], 'vikunja/frontend/public/images/icons/favicon-tracking-32x32.png'],
  [png[60], 'vikunja/frontend/public/images/icons/apple-touch-icon-60x60.png'],
  [png[76], 'vikunja/frontend/public/images/icons/apple-touch-icon-76x76.png'],
  [png[96], 'vikunja/frontend/public/images/icons/badge-monochrome.png'],
  [png[120], 'vikunja/frontend/public/images/icons/apple-touch-icon-120x120.png'],
  [png[144], 'vikunja/frontend/public/images/icons/msapplication-icon-144x144.png'],
  [png[150], 'vikunja/frontend/public/images/icons/mstile-150x150.png'],
  [png[152], 'vikunja/frontend/public/images/icons/apple-touch-icon-152x152.png'],
  [png[180], 'vikunja/frontend/public/images/icons/apple-touch-icon-180x180.png'],
  [png[180], 'vikunja/frontend/public/images/icons/apple-touch-icon.png'],
  [png[192], 'vikunja/frontend/public/images/icons/android-chrome-192x192.png'],
  [pngMask, 'vikunja/frontend/public/images/icons/icon-maskable.png'],
  [png[512], 'vikunja/frontend/public/images/icons/android-chrome-512x512.png'],
  [svgMono, 'vikunja/frontend/public/images/icons/safari-pinned-tab.svg'],
  [svgColor, 'vikunja/frontend/src/assets/logo-full.svg'],
  [svgColor, 'vikunja/frontend/src/assets/logo-full-pride.svg'],
  [svgColor, 'vikunja/frontend/src/assets/logo.svg'],

  [icoBuf, 'ezbookkeeping/public/favicon.ico'],
  [png[256], 'ezbookkeeping/public/favicon.png'],
  [png[180], 'ezbookkeeping/public/touchicon.png'],
  [png[192], 'ezbookkeeping/public/img/ezbookkeeping-192.png'],
  [png[512], 'ezbookkeeping/public/img/ezbookkeeping-512.png'],
];
let placed = 0;
for (const [buf, rel] of targets) {
  const dst = path.join(V, rel);
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.writeFileSync(dst, buf);
  placed++;
}
console.log(`[apply] 已铺 ${placed} 个文件到 vendor/（Vikunja + ezBookkeeping）`);

// splash_screens（42 个设备启动图）为设备分辨率全屏图，需逐尺寸映射，留作手动/可选步骤，未自动生成。
console.log('\n完成。提示：ezBookkeeping 的 public/img/splash_screens/（42 个设备启动图）未自动生成，需要时单独处理。');
})();
