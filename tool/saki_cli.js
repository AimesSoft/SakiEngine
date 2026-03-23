#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const { ensureToolchain } = require('./toolchain.js');

const repoRoot = path.dirname(__dirname);
const nodeBin = process.execPath;

function runCommand(executable, args, cwd, allowFailure = false) {
  const result = spawnSync(executable, args, {
    cwd,
    env: process.env,
    stdio: 'inherit',
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0 && !allowFailure) {
    throw new Error(`命令失败: ${executable} ${args.join(' ')}`);
  }
  return result.status || 0;
}

function runNodeScript(scriptRelPath, args = [], cwd = repoRoot, allowFailure = false) {
  const scriptAbs = path.join(repoRoot, scriptRelPath);
  return runCommand(nodeBin, [scriptAbs, ...args], cwd, allowFailure);
}

function getPreferredDeviceId() {
  switch (process.platform) {
    case 'win32':
      return 'windows';
    case 'darwin':
      return 'macos';
    case 'linux':
      return 'linux';
    default:
      return 'chrome';
  }
}

function getAvailableDevices(flutterBin) {
  const result = spawnSync(flutterBin, ['devices', '--machine'], {
    cwd: repoRoot,
    env: process.env,
    encoding: 'utf8',
  });
  if (result.error || result.status !== 0) {
    return [];
  }
  try {
    const parsed = JSON.parse(result.stdout || '[]');
    if (!Array.isArray(parsed)) return [];
    return parsed
      .map((item) => (item && typeof item.id === 'string' ? item.id : null))
      .filter(Boolean);
  } catch (_) {
    return [];
  }
}

function chooseDevice(flutterBin) {
  const preferred = getPreferredDeviceId();
  const devices = getAvailableDevices(flutterBin);
  if (devices.includes(preferred)) return preferred;
  if (devices.includes('chrome')) return 'chrome';
  return '';
}

function listGameProjects() {
  const gameRoot = path.join(repoRoot, 'Game');
  if (!fs.existsSync(gameRoot)) return [];
  return fs
    .readdirSync(gameRoot, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .filter((name) => fs.existsSync(path.join(gameRoot, name, 'pubspec.yaml')))
    .sort();
}

function runSakiDirect(targetGame, flutterBin) {
  const gameDir = path.join(repoRoot, 'Game', targetGame);
  const pubspec = path.join(gameDir, 'pubspec.yaml');
  if (!fs.existsSync(pubspec)) {
    console.error(`错误: 指定项目不存在或不是 Flutter 项目: ${targetGame}`);
    console.error('可用项目:');
    for (const name of listGameProjects()) {
      console.error(`  - ${name}`);
    }
    process.exit(1);
  }

  const device = chooseDevice(flutterBin);
  if (!device) {
    console.error(`错误: 未检测到可用运行设备（${getPreferredDeviceId()}/chrome）。`);
    runCommand(flutterBin, ['devices'], repoRoot, true);
    process.exit(1);
  }

  console.log(`使用设备: ${device}`);
  console.log(`直启游戏项目: ${targetGame}`);

  runNodeScript('scripts/launcher-bridge.js', ['prepare-project', '--game', targetGame], repoRoot);
  runCommand(flutterBin, ['pub', 'get'], gameDir);
  runNodeScript(
    'scripts/launcher-bridge.js',
    ['prepare-project', '--game', targetGame, '--generate-icons'],
    repoRoot,
  );

  const code = runCommand(
    flutterBin,
    ['run', '--no-pub', '-d', device, `--dart-define=SAKI_GAME_PATH=${gameDir}`],
    gameDir,
    true,
  );
  process.exit(code);
}

function runSakiLauncher(flutterBin) {
  const device = chooseDevice(flutterBin);
  if (!device) {
    console.error(`错误: 未检测到可用运行设备（${getPreferredDeviceId()}/chrome）。`);
    runCommand(flutterBin, ['devices'], repoRoot, true);
    process.exit(1);
  }
  console.log(`使用设备: ${device}`);
  const launcherDir = path.join(repoRoot, 'Launcher');
  runCommand(flutterBin, ['pub', 'get'], launcherDir);
  const code = runCommand(
    flutterBin,
    ['run', '--no-pub', '-d', device, `--dart-define=SAKI_REPO_ROOT=${repoRoot}`],
    launcherDir,
    true,
  );
  process.exit(code);
}

function usage() {
  console.log(`SakiEngine CLI

Usage:
  node tool/saki_cli.js saki [gameName]
  node tool/saki_cli.js run
  node tool/saki_cli.js build [gameName|platform] [platform]
  node tool/saki_cli.js create
  node tool/saki_cli.js select
`);
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  if (!command || command === 'help' || command === '--help') {
    usage();
    return;
  }

  const { flutterBin } = await ensureToolchain(repoRoot, { preferSystem: true });

  if (command === 'saki') {
    if (args[0]) runSakiDirect(args[0], flutterBin);
    runSakiLauncher(flutterBin);
    return;
  }

  if (command === 'run') {
    process.exit(runNodeScript('run.js', args, repoRoot, true));
  }

  if (command === 'build') {
    process.exit(runNodeScript('scripts/build.js', args, repoRoot, true));
  }

  if (command === 'create') {
    process.exit(runNodeScript('scripts/create-new-project.js', args, repoRoot, true));
  }

  if (command === 'select') {
    process.exit(runNodeScript('scripts/select-game.js', args, repoRoot, true));
  }

  throw new Error(`未知命令: ${command}`);
}

main().catch((error) => {
  console.error(`启动失败: ${error.message}`);
  process.exit(1);
});
