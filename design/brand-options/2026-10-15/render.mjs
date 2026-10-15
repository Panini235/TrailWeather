import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const sharp = require(process.env.TRAILWEATHER_SHARP_PATH || 'sharp');
const dir = path.dirname(new URL(import.meta.url).pathname);
const concepts = [
  {id:'a-shanqing', letter:'A', name:'山晴', subtitle:'徒步天气 · 推荐', bg:'#123F36', accent:'#FFC75E',
   mark:`<circle cx="741" cy="280" r="96" fill="#FFC75E"/>
   <path d="M141 748 415 330Q438 294 462 330L622 577 710 447Q733 413 755 449L892 670Q916 708 881 737L850 765H155Q131 765 141 748Z" fill="#F5F4E9"/>
   <path d="m428 352 64 95-65-24-59 34Z" fill="#AACBBC"/>
   <path d="M513 893c-6-78 165-96 158-165-5-49-92-60-110-103-13-31 12-61 29-81" fill="none" stroke="#123F36" stroke-width="60" stroke-linecap="round"/>`},
  {id:'b-shanxing', letter:'B', name:'山行天气', subtitle:'直白清晰 · 天气入口', bg:'#246AE3', accent:'#FFDB76',
   mark:`<circle cx="708" cy="287" r="112" fill="#FFDB76"/>
   <path d="M274 411c-4-65 48-117 111-117 43 0 78 19 100 52 22-13 46-19 72-15 56 8 94 54 94 109 44 2 78 35 78 77 0 46-38 78-84 78H270c-54 0-95-37-95-85 0-50 43-95 99-99Z" fill="#F7FBFF"/>
   <path d="m182 785 233-274q18-23 38 0l113 142 91-99q19-20 36 3l160 228Z" fill="#D9EBFF"/>
   <path d="m434 537 60 75-57-15-45 17Z" fill="#246AE3"/>
   <path d="M436 844q-10-57 74-94t34-80" fill="none" stroke="#246AE3" stroke-width="49" stroke-linecap="round"/>`},
  {id:'c-qingtu', letter:'C', name:'晴途', subtitle:'沿途天气 · 路线感', bg:'#DFF0E6', accent:'#F8B650',
   mark:`<circle cx="708" cy="278" r="91" fill="#F8B650"/>
   <path d="M156 656 352 346Q373 313 394 345l155 235 108-163q21-33 44 0l168 239v182H156Z" fill="#207263"/>
   <path d="M168 705q213-95 368-8 152 85 334-36v177H168Z" fill="#15594E"/>
   <path d="M512 864c-5-99 183-125 177-198-5-65-214-57-220-113-3-36 43-61 77-79" fill="none" stroke="#F3F8EE" stroke-width="70" stroke-linecap="round"/>`},
  {id:'d-guanshan', letter:'D', name:'观山天气', subtitle:'山地观察 · 温暖户外', bg:'#F3EAD8', accent:'#E39441',
   mark:`<circle cx="512" cy="350" r="164" fill="#E39441"/>
   <path d="m132 742 278-358q20-25 40 0l142 175 103-119q21-23 42 2l164 186v150H132Z" fill="#384D42"/>
   <path d="m427 408 63 80-65-21-57 28Z" fill="#F3EAD8"/>
   <path d="M144 748q169-149 353-61 139 67 395-52v161H144Z" fill="#779078"/>
   <path d="M188 817q163-112 285-50t364-47" fill="none" stroke="#F3EAD8" stroke-width="35" stroke-linecap="round"/>`},
  {id:'e-shanhou', letter:'E', name:'山候', subtitle:'山地气象 · 简洁标识', bg:'#25324B', accent:'#F0B78E',
   mark:`<circle cx="752" cy="282" r="82" fill="#F0B78E"/>
   <path d="m169 735 285-378q48-63 96 0l285 378" fill="none" stroke="#F4F2E9" stroke-width="57" stroke-linejoin="round" stroke-linecap="round"/>
   <path d="m281 738 186-242q34-44 68 0l185 242M401 739l83-106q18-23 36 0l82 106" fill="none" stroke="#A9C4CA" stroke-width="43" stroke-linejoin="round" stroke-linecap="round"/>`},
  {id:'f-yantu', letter:'F', name:'沿途天气', subtitle:'日常到山野 · 轻快', bg:'#0F8393', accent:'#FFD175',
   mark:`<circle cx="694" cy="295" r="97" fill="#FFD175"/>
   <path d="M235 489c0-81 61-145 139-145 49 0 89 22 114 61 24-13 50-15 74-10 51 9 87 52 90 103h44c52 0 91 38 91 87 0 50-41 90-93 90H266c-62 0-110-43-110-98 0-45 31-79 79-88Z" fill="#F3F7EF"/>
   <path d="m196 794 190-234q17-22 35 0l115 143 85-99q17-20 35 0l157 190Z" fill="#B5DEE1"/>
   <path d="M458 849c-9-61 154-71 148-129-5-41-94-43-114-76" fill="none" stroke="#0F8393" stroke-width="53" stroke-linecap="round"/>`},
];
const svg = (c) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024"><rect width="1024" height="1024" fill="${c.bg}"/>${c.mark}</svg>`;
for (const c of concepts) {
  await fs.writeFile(path.join(dir,c.id+'.svg'),svg(c));
  await sharp(Buffer.from(svg(c))).flatten({background:c.bg}).png().toFile(path.join(dir,c.id+'-1024.png'));
  await sharp(Buffer.from(svg(c))).resize(64,64).png().toFile(path.join(dir,c.id+'-64.png'));
}
const width=1440, height=1220;
let board=`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><rect width="100%" height="100%" fill="#F5F4EF"/><text x="72" y="77" font-family="PingFang SC, sans-serif" font-weight="600" font-size="36" fill="#223A32">一眼看懂：山、天气、沿途</text><text x="74" y="115" font-family="PingFang SC, sans-serif" font-size="19" fill="#68766D">图标与名称候选 · iOS 优先 / 兼顾 Android · 2026.10.15</text>`;
const composites=[];
for (let i=0;i<concepts.length;i++) {
  const c=concepts[i], col=i%3, row=Math.floor(i/3), x=72+col*440, y=160+row*500;
  board+=`<rect x="${x}" y="${y}" width="416" height="470" rx="24" fill="#FFFFFF"/><text x="${x+28}" y="${y+38}" font-family="sans-serif" font-weight="700" font-size="20" fill="#5D7165">${c.letter}</text><text x="${x+28}" y="${y+391}" font-family="PingFang SC, sans-serif" font-weight="600" font-size="28" fill="#203B31">${c.name}</text><text x="${x+28}" y="${y+425}" font-family="PingFang SC, sans-serif" font-size="18" fill="#68796E">${c.subtitle}</text>`;
  const mask=Buffer.from('<svg width="270" height="270"><rect width="270" height="270" rx="61" fill="white"/></svg>');
  const icon=await sharp(Buffer.from(svg(c))).resize(270,270).composite([{input:mask,blend:'dest-in'}]).png().toBuffer();
  composites.push({input:icon,left:x+73,top:y+64});
  const smallMask=Buffer.from('<svg width="48" height="48"><rect width="48" height="48" rx="11" fill="white"/></svg>');
  const small=await sharp(Buffer.from(svg(c))).resize(48,48).composite([{input:smallMask,blend:'dest-in'}]).png().toBuffer();
  composites.push({input:small,left:x+336,top:y+373});
}
board+='<text x="74" y="1196" font-family="PingFang SC, sans-serif" font-size="16" fill="#6F7D73">均为原创矢量方案；右下角为小尺寸预览。名称尚未完成商标与应用商店重名核验。</text></svg>';
await sharp(Buffer.from(board)).composite(composites).png().toFile(path.join(dir,'options-board.png'));
await fs.writeFile(path.join(dir,'concepts.json'),JSON.stringify(concepts.map(({mark,...meta})=>meta),null,2)+'\n');
console.log('Created 6 SVG originals, 12 PNG icons, and options-board.png');
