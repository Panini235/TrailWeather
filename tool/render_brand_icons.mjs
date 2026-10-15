// Optional asset authoring tool. CI uses the committed PNGs and Python stdlib.
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const sharp = require(process.env.TRAILWEATHER_SHARP_PATH || 'sharp');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const brand = path.join(root, 'assets/branding');
const source = await fs.readFile(path.join(brand, 'app-icon.svg'));
const output = async (relative, size) => {
  const target = path.join(brand, 'platforms', relative);
  await fs.mkdir(path.dirname(target), { recursive: true });
  await sharp(source).resize(size, size).flatten({ background: '#F3EAD8' }).png().toFile(target);
};
for (const [density, size] of Object.entries({mdpi:48,hdpi:72,xhdpi:96,xxhdpi:144,xxxhdpi:192})) {
  await output(`android/mipmap-${density}/ic_launcher.png`, size);
}
const contents = JSON.parse(await fs.readFile(path.join(brand, 'platforms/ios/AppIcon.appiconset/Contents.json'), 'utf8'));
const generated = new Set();
for (const image of contents.images) {
  if (generated.has(image.filename)) continue;
  generated.add(image.filename);
  const size = Number(image.size.split('x')[0]) * Number(image.scale.slice(0,-1));
  await output(`ios/AppIcon.appiconset/${image.filename}`, size);
}
for (const [name, size] of Object.entries({'icons/Icon-192.png':192,'icons/Icon-512.png':512,'icons/apple-touch-icon.png':180,'favicon.png':64})) {
  await output(`web/${name}`,size);
}
console.log(`Generated Android, ${generated.size} iOS, and Web icons from selected D artwork.`);
