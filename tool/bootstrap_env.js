#!/usr/bin/env node

const path = require('path');
const { ensureToolchain } = require('./toolchain.js');

function parseArgs(argv) {
  const out = { format: 'shell', repoRoot: path.dirname(__dirname) };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--format' && argv[i + 1]) {
      out.format = argv[i + 1];
      i += 1;
      continue;
    }
    if (token === '--repo-root' && argv[i + 1]) {
      out.repoRoot = argv[i + 1];
      i += 1;
    }
  }
  return out;
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const { flutterBin, nodeBin } = await ensureToolchain(args.repoRoot, { preferSystem: true });

  if (args.format === 'bat') {
    process.stdout.write(`set "SAKI_FLUTTER_BIN=${flutterBin}"\n`);
    process.stdout.write(`set "SAKI_NODE_BIN=${nodeBin}"\n`);
    process.stdout.write('set "SAKI_TOOLCHAIN_READY=1"\n');
    process.stdout.write(`set "PATH=${process.env.PATH || ''}"\n`);
    return;
  }

  process.stdout.write(`export SAKI_FLUTTER_BIN=${shellQuote(flutterBin)}\n`);
  process.stdout.write(`export SAKI_NODE_BIN=${shellQuote(nodeBin)}\n`);
  process.stdout.write('export SAKI_TOOLCHAIN_READY=1\n');
  process.stdout.write(`export PATH=${shellQuote(process.env.PATH || '')}\n`);
}

main().catch((error) => {
  process.stderr.write(`bootstrap_env.js 失败: ${error.message}\n`);
  process.exit(1);
});
