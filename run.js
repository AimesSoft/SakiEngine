#!/usr/bin/env node

const path = require('path');
const { execSync } = require('child_process');
const readline = require('readline');

const platformUtils = require('./scripts/platform-utils.js');
const assetUtils = require('./scripts/asset-utils.js');

const colors = {
  reset: '\x1b[0m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m'
};

const colorLog = (message, color = 'reset') => {
  console.log(`${colors[color]}${message}${colors.reset}`);
};

const PROJECT_ROOT = __dirname;
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

const askQuestion = (question) =>
  new Promise((resolve) => rl.question(question, resolve));

async function handleGameSelection() {
  const currentGame = assetUtils.readDefaultGame(PROJECT_ROOT);

  if (currentGame) {
    colorLog(`当前默认游戏: ${currentGame}`, 'blue');
    console.log();
    colorLog('请选择操作:', 'yellow');
    colorLog('  1. 继续使用当前游戏', 'blue');
    colorLog('  2. 选择其他游戏', 'blue');
    colorLog('  3. 创建新游戏项目', 'blue');
    console.log();

    const choice = (await askQuestion('请选择 (1-3, 默认为1): ')).trim();
    if (choice === '2') {
      const selectGame = require('./scripts/select-game.js');
      await selectGame.selectGame();
    } else if (choice === '3') {
      const createProject = require('./scripts/create-new-project.js');
      await createProject.createNewProject();
    }
    return;
  }

  const selectGame = require('./scripts/select-game.js');
  await selectGame.selectGame();
}

async function main() {
  try {
    colorLog('=== SakiEngine 项目启动器（项目级 Flutter App） ===', 'blue');
    console.log();

    const platform = platformUtils.detectPlatform();
    const platformName = platformUtils.getPlatformDisplayName(platform);

    if (!platformUtils.checkPlatformSupport(platform)) {
      colorLog(`错误: 当前平台 ${platformName} 不支持或缺少 Flutter`, 'red');
      process.exit(1);
    }

    await handleGameSelection();

    const gameName = assetUtils.readDefaultGame(PROJECT_ROOT);
    if (!gameName) {
      colorLog('错误: 无法读取游戏项目名称', 'red');
      process.exit(1);
    }

    const gameDir = assetUtils.validateGameDir(PROJECT_ROOT, gameName);
    if (!gameDir) {
      colorLog(`错误: 游戏目录不存在: ${path.join(PROJECT_ROOT, 'Game', gameName)}`, 'red');
      process.exit(1);
    }

    const pubspecPath = path.join(gameDir, 'pubspec.yaml');
    if (!require('fs').existsSync(pubspecPath)) {
      colorLog(`错误: ${gameDir} 不是 Flutter 项目（缺少 pubspec.yaml）`, 'red');
      process.exit(1);
    }

    console.log();
    colorLog(`启动游戏项目: ${gameName}`, 'green');
    colorLog(`项目路径: ${gameDir}`, 'blue');
    console.log();

    colorLog('正在读取游戏配置...', 'yellow');
    const gameConfig = assetUtils.readGameConfig(gameDir);
    if (gameConfig) {
      if (!assetUtils.setAppIdentity(gameDir, gameConfig.appName, gameConfig.bundleId)) {
        colorLog('警告: 应用身份同步失败，继续启动', 'yellow');
      }
    } else {
      colorLog('未找到有效 game_config.txt，跳过应用身份同步', 'yellow');
    }
    assetUtils.ensureProjectIcon(gameDir, PROJECT_ROOT);

    colorLog('请选择运行平台:', 'yellow');
    colorLog(`  1. ${platformName} (当前系统平台)`, 'blue');
    colorLog('  2. Chrome (Web调试模式)', 'blue');
    console.log();

    const choice = (await askQuestion('请选择 (1-2, 默认为1): ')).trim();
    const runTarget = choice === '2' ? 'chrome' : platform;

    process.chdir(gameDir);
    colorLog('正在获取依赖...', 'yellow');
    execSync('flutter pub get', { stdio: 'inherit' });
    assetUtils.generateAppIcons(gameDir);

    const gameDefine = `--dart-define=SAKI_GAME_PATH="${gameDir}"`;
    if (runTarget === 'chrome') {
      execSync(`flutter run -d chrome ${gameDefine}`, { stdio: 'inherit' });
    } else {
      execSync(`flutter run -d ${runTarget} ${gameDefine}`, { stdio: 'inherit' });
    }
  } finally {
    rl.close();
  }
}

if (require.main === module) {
  main().catch((error) => {
    colorLog(`启动失败: ${error.message}`, 'red');
    process.exit(1);
  });
}

module.exports = { main };
