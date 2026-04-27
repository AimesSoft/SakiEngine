#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const MAGIC = 0x53414b49; // SAKI
const VERSION = 1;

const PACKABLE_EXTENSIONS = new Set([
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.bmp',
  '.webp',
  '.avif',
  '.svg',
  '.mp3',
  '.ogg',
  '.wav',
  '.flac',
  '.m4a',
  '.aac',
  '.mp4',
  '.mov',
  '.avi',
  '.mkv',
  '.webm',
  '.json',
  '.txt',
  '.sks',
  '.ttf',
  '.otf',
]);

const TEXT_EXTENSIONS = new Set(['.json', '.txt', '.sks']);

function normalizeRelPath(relPath) {
  return relPath.split(path.sep).join('/');
}

function shouldPack(relativePath) {
  const normalized = normalizeRelPath(relativePath);
  if (normalized === 'game.sakipak') {
    return false;
  }
  if (normalized === 'default_game.txt') {
    return true;
  }
  if (
    !(
      normalized.startsWith('Assets/') ||
      normalized.startsWith('GameScript/') ||
      normalized.startsWith('GameScript_')
    )
  ) {
    return false;
  }
  if (normalized.endsWith('/.DS_Store') || normalized.endsWith('.DS_Store')) {
    return false;
  }
  const ext = path.extname(normalized).toLowerCase();
  return PACKABLE_EXTENSIONS.has(ext);
}

function collectFiles(gameDir) {
  const files = [];
  function walk(current) {
    const entries = fs.readdirSync(current, { withFileTypes: true });
    entries.sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        walk(fullPath);
      } else if (entry.isFile()) {
        const rel = normalizeRelPath(path.relative(gameDir, fullPath));
        if (shouldPack(rel)) {
          files.push({ fullPath, relPath: rel });
        }
      }
    }
  }
  walk(gameDir);
  return files;
}

function writePack(gameDir, outPath) {
  const files = collectFiles(gameDir);
  if (files.length === 0) {
    throw new Error('No assets collected for SakiPack.');
  }

  const fd = fs.openSync(outPath, 'w');
  try {
    const header = Buffer.alloc(20);
    header.writeUInt32BE(MAGIC, 0);
    header.writeUInt32BE(VERSION, 4);
    header.writeBigUInt64BE(BigInt(0), 8); // index offset placeholder
    header.writeUInt32BE(0, 16); // index length placeholder
    fs.writeSync(fd, header);

    let currentOffset = 20;
    const entries = [];
    for (const file of files) {
      const bytes = fs.readFileSync(file.fullPath);
      const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
      fs.writeSync(fd, bytes);
      const ext = path.extname(file.relPath).toLowerCase();
      entries.push({
        path: file.relPath,
        offset: currentOffset,
        length: bytes.length,
        text: TEXT_EXTENSIONS.has(ext),
        sha256,
      });
      currentOffset += bytes.length;
    }

    const indexOffset = currentOffset;
    const indexBytes = Buffer.from(
      JSON.stringify(
        {
          version: '1',
          created_at: new Date().toISOString(),
          file_count: entries.length,
          entries,
        },
        null,
        0,
      ),
      'utf8',
    );
    fs.writeSync(fd, indexBytes);

    const finalHeader = Buffer.alloc(20);
    finalHeader.writeUInt32BE(MAGIC, 0);
    finalHeader.writeUInt32BE(VERSION, 4);
    finalHeader.writeBigUInt64BE(BigInt(indexOffset), 8);
    finalHeader.writeUInt32BE(indexBytes.length, 16);
    fs.writeSync(fd, finalHeader, 0, finalHeader.length, 0);

    return {
      fileCount: entries.length,
      bytes: 20 + entries.reduce((n, e) => n + e.length, 0) + indexBytes.length,
    };
  } finally {
    fs.closeSync(fd);
  }
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function main() {
  const args = process.argv.slice(2);
  const gameDirArg = args[0];
  const outArg = args[1];
  if (!gameDirArg || !outArg) {
    throw new Error('Usage: node scripts/build_saki_pack.js <game_dir> <output_file>');
  }

  const gameDir = path.resolve(gameDirArg);
  const outPath = path.resolve(outArg);
  ensureDir(path.dirname(outPath));

  const result = writePack(gameDir, outPath);
  process.stdout.write(
    `[SakiPack] generated ${outPath} (${result.fileCount} files, ${result.bytes} bytes)\n`,
  );
}

main();
