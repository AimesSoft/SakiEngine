#!/usr/bin/env node

const path = require('path');

const assetUtils = require('./asset-utils.js');
const createProjectUtils = require('./create-new-project.js');

function parseArgs(argv) {
    const result = { _: [] };
    for (let i = 0; i < argv.length; i += 1) {
        const token = argv[i];
        if (!token.startsWith('--')) {
            result._.push(token);
            continue;
        }

        const key = token.slice(2);
        const next = argv[i + 1];
        if (!next || next.startsWith('--')) {
            result[key] = true;
            continue;
        }

        result[key] = next;
        i += 1;
    }
    return result;
}

function usage() {
    console.log(`
SakiEngine Launcher Bridge

Usage:
  node scripts/launcher-bridge.js prepare-project --game <name> [--generate-icons]
  node scripts/launcher-bridge.js create-project --name <name> --bundle <bundleId> [--color <hex>] [--set-default]
`);
}

async function handlePrepareProject(args) {
    const gameName = args.game;
    if (!gameName || typeof gameName !== 'string') {
        throw new Error('缺少参数 --game');
    }

    const projectRoot = path.dirname(__dirname);
    const gameDir = assetUtils.validateGameDir(projectRoot, gameName);
    if (!gameDir) {
        throw new Error(`游戏目录不存在: ${gameName}`);
    }

    const gameConfig = assetUtils.readGameConfig(gameDir);
    if (gameConfig) {
        const ok = assetUtils.setAppIdentity(gameDir, gameConfig.appName, gameConfig.bundleId);
        if (!ok) {
            throw new Error('同步应用身份失败');
        }
    } else {
        assetUtils.colorLog('未找到有效 game_config.txt，跳过应用身份同步', 'yellow');
    }

    assetUtils.ensureProjectIcon(gameDir, projectRoot);
    assetUtils.fixWindowsInstallPrefixCache(gameDir);

    if (args['generate-icons']) {
        assetUtils.generateAppIcons(gameDir);
    }
}

async function handleCreateProject(args) {
    const name = args.name;
    const bundle = args.bundle;
    const color = args.color || '137B8B';
    const setDefault = Boolean(args['set-default']);

    if (!name || typeof name !== 'string') {
        throw new Error('缺少参数 --name');
    }
    if (!bundle || typeof bundle !== 'string') {
        throw new Error('缺少参数 --bundle');
    }

    await createProjectUtils.createNewProjectNonInteractive({
        projectName: name,
        bundleId: bundle,
        primaryColor: color,
        setDefault,
    });
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    const command = args._[0];

    if (!command || command === 'help' || command === '--help') {
        usage();
        return;
    }

    if (command === 'prepare-project') {
        await handlePrepareProject(args);
        return;
    }
    if (command === 'create-project') {
        await handleCreateProject(args);
        return;
    }

    throw new Error(`未知命令: ${command}`);
}

main().catch((error) => {
    assetUtils.colorLog(`launcher-bridge 失败: ${error.message}`, 'red');
    process.exit(1);
});

