/**
 * 资源处理工具模块（项目级）
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

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

function readDefaultGame(projectRoot) {
    const defaultGameFile = path.join(projectRoot, 'default_game.txt');
    if (!fs.existsSync(defaultGameFile)) {
        return null;
    }
    try {
        const content = fs.readFileSync(defaultGameFile, 'utf8').trim();
        return content || null;
    } catch (_) {
        return null;
    }
}

function validateGameDir(projectRoot, gameName) {
    const gameDir = path.join(projectRoot, 'Game', gameName);
    if (fs.existsSync(gameDir) && fs.statSync(gameDir).isDirectory()) {
        return gameDir;
    }
    return null;
}

function readGameConfig(gameDir) {
    const configFile = path.join(gameDir, 'game_config.txt');
    if (!fs.existsSync(configFile)) {
        return null;
    }
    try {
        const lines = fs
            .readFileSync(configFile, 'utf8')
            .split(/\r?\n/)
            .map((line) => line.trim())
            .filter(Boolean);
        if (lines.length >= 2) {
            return {
                appName: lines[0],
                bundleId: lines[1],
            };
        }
    } catch (_) {
        return null;
    }
    return null;
}

function writeDefaultGame(projectRoot, gameName) {
    const defaultGameFile = path.join(projectRoot, 'default_game.txt');
    fs.writeFileSync(defaultGameFile, `${gameName}\n`);
}

function getGameDirectories(projectRoot) {
    const gameBaseDir = path.join(projectRoot, 'Game');
    if (!fs.existsSync(gameBaseDir)) {
        return [];
    }
    try {
        return fs
            .readdirSync(gameBaseDir, { withFileTypes: true })
            .filter((entry) => entry.isDirectory())
            .map((entry) => entry.name)
            .sort();
    } catch (_) {
        return [];
    }
}

function setAppIdentity(projectDir, appName, bundleId) {
    colorLog(`正在同步应用信息: ${appName} (${bundleId})`, 'yellow');
    const binaryName = String(appName)
        .replace(/[^A-Za-z0-9]+/g, '_')
        .replace(/^_+|_+$/g, '') || 'saki_game';
    colorLog(`正在同步产物名称: ${binaryName}`, 'yellow');

    try {
        const androidManifest = path.join(projectDir, 'android', 'app', 'src', 'main', 'AndroidManifest.xml');
        if (fs.existsSync(androidManifest)) {
            let content = fs.readFileSync(androidManifest, 'utf8');
            content = content.replace(/android:label="[^"]*"/, `android:label="${appName}"`);
            fs.writeFileSync(androidManifest, content);
        }

        const androidGradle = path.join(projectDir, 'android', 'app', 'build.gradle.kts');
        if (fs.existsSync(androidGradle)) {
            let content = fs.readFileSync(androidGradle, 'utf8');
            content = content.replace(/applicationId = "[^"]*"/, `applicationId = "${bundleId}"`);
            fs.writeFileSync(androidGradle, content);
        }

        const iosInfoPlist = path.join(projectDir, 'ios', 'Runner', 'Info.plist');
        if (fs.existsSync(iosInfoPlist)) {
            let content = fs.readFileSync(iosInfoPlist, 'utf8');
            content = content.replace(
                /(<key>CFBundleDisplayName<\/key>\s*<string>)[^<]*(<\/string>)/s,
                `$1${appName}$2`
            );
            content = content.replace(
                /(<key>CFBundleName<\/key>\s*<string>)[^<]*(<\/string>)/s,
                `$1${appName}$2`
            );
            fs.writeFileSync(iosInfoPlist, content);
        }

        const iosPbxproj = path.join(projectDir, 'ios', 'Runner.xcodeproj', 'project.pbxproj');
        if (fs.existsSync(iosPbxproj)) {
            const lines = fs.readFileSync(iosPbxproj, 'utf8').split(/\r?\n/);
            const updated = lines.map((line) => {
                if (!line.includes('PRODUCT_BUNDLE_IDENTIFIER = ')) {
                    return line;
                }
                if (line.includes('.RunnerTests;')) {
                    return line.replace(/PRODUCT_BUNDLE_IDENTIFIER = [^;]*;/, `PRODUCT_BUNDLE_IDENTIFIER = ${bundleId}.RunnerTests;`);
                }
                return line.replace(/PRODUCT_BUNDLE_IDENTIFIER = [^;]*;/, `PRODUCT_BUNDLE_IDENTIFIER = ${bundleId};`);
            });
            fs.writeFileSync(iosPbxproj, updated.join('\n'));
        }

        const macosAppInfo = path.join(projectDir, 'macos', 'Runner', 'Configs', 'AppInfo.xcconfig');
        if (fs.existsSync(macosAppInfo)) {
            let content = fs.readFileSync(macosAppInfo, 'utf8');
            content = content.replace(/^PRODUCT_BUNDLE_IDENTIFIER = .*$/m, `PRODUCT_BUNDLE_IDENTIFIER = ${bundleId}`);
            content = content.replace(/^PRODUCT_NAME = .*$/m, `PRODUCT_NAME = ${binaryName}`);
            fs.writeFileSync(macosAppInfo, content);
        }

        const linuxCmake = path.join(projectDir, 'linux', 'CMakeLists.txt');
        if (fs.existsSync(linuxCmake)) {
            let content = fs.readFileSync(linuxCmake, 'utf8');
            content = content.replace(/set\(APPLICATION_ID "[^"]*"\)/, `set(APPLICATION_ID "${bundleId}")`);
            content = content.replace(/set\(BINARY_NAME "[^"]*"\)/, `set(BINARY_NAME "${binaryName}")`);
            fs.writeFileSync(linuxCmake, content);
        }

        const linuxApplication = path.join(projectDir, 'linux', 'runner', 'my_application.cc');
        if (fs.existsSync(linuxApplication)) {
            let content = fs.readFileSync(linuxApplication, 'utf8');
            content = content.replace(/gtk_header_bar_set_title\(header_bar, "[^"]*"\);/, `gtk_header_bar_set_title(header_bar, "${appName}");`);
            content = content.replace(/gtk_window_set_title\(window, "[^"]*"\);/, `gtk_window_set_title(window, "${appName}");`);
            fs.writeFileSync(linuxApplication, content);
        }

        const windowsCmake = path.join(projectDir, 'windows', 'CMakeLists.txt');
        if (fs.existsSync(windowsCmake)) {
            let content = fs.readFileSync(windowsCmake, 'utf8');
            content = content.replace(/^project\([^)]+ LANGUAGES CXX\)/m, `project(${binaryName} LANGUAGES CXX)`);
            content = content.replace(/^set\(BINARY_NAME "[^"]*"\)/m, `set(BINARY_NAME "${binaryName}")`);
            fs.writeFileSync(windowsCmake, content);
        }

        const windowsMain = path.join(projectDir, 'windows', 'runner', 'main.cpp');
        if (fs.existsSync(windowsMain)) {
            let content = fs.readFileSync(windowsMain, 'utf8');
            content = content.replace(/window\.Create\(L"[^"]*"/, `window.Create(L"${appName}"`);
            fs.writeFileSync(windowsMain, content);
        }

        const windowsRunnerRc = path.join(projectDir, 'windows', 'runner', 'Runner.rc');
        if (fs.existsSync(windowsRunnerRc)) {
            const companyName = bundleId.split('.').slice(0, 2).join('.') || bundleId;
            let content = fs.readFileSync(windowsRunnerRc, 'utf8');
            content = content.replace(/VALUE "CompanyName", "[^"]*"/, `VALUE "CompanyName", "${companyName}"`);
            content = content.replace(/VALUE "FileDescription", "[^"]*"/, `VALUE "FileDescription", "${appName}"`);
            content = content.replace(/VALUE "ProductName", "[^"]*"/, `VALUE "ProductName", "${appName}"`);
            content = content.replace(/VALUE "InternalName", "[^"]*"\s+"\\0"/, `VALUE "InternalName", "${binaryName}" "\\0"`);
            content = content.replace(/VALUE "OriginalFilename", "[^"]*"\s+"\\0"/, `VALUE "OriginalFilename", "${binaryName}.exe" "\\0"`);
            fs.writeFileSync(windowsRunnerRc, content);
        }

        return true;
    } catch (error) {
        colorLog(`设置应用身份信息失败: ${error.message}`, 'red');
        return false;
    }
}

function ensureProjectIcon(projectDir, projectRoot) {
    const projectIconPath = path.join(projectDir, 'icon.png');
    if (fs.existsSync(projectIconPath)) {
        colorLog(`使用项目图标: ${projectIconPath}`, 'green');
        return true;
    }

    const rootIconPath = path.join(projectRoot, 'icon.png');
    if (fs.existsSync(rootIconPath)) {
        fs.copyFileSync(rootIconPath, projectIconPath);
        colorLog('项目无 icon.png，已复制根目录图标', 'yellow');
        return true;
    }

    const engineIconPath = path.join(projectRoot, 'Engine', 'icon.png');
    if (fs.existsSync(engineIconPath)) {
        fs.copyFileSync(engineIconPath, projectIconPath);
        colorLog('项目无 icon.png，已复制 Engine/icon.png', 'yellow');
        return true;
    }

    colorLog('警告: 未找到 icon.png，跳过图标同步', 'yellow');
    return false;
}

function ensureWebIconConfig(pubspecPath) {
    if (!fs.existsSync(pubspecPath)) {
        return false;
    }

    const content = fs.readFileSync(pubspecPath, 'utf8');
    const lines = content.split(/\r?\n/);

    const launcherStart = lines.findIndex((line) => /^flutter_launcher_icons:\s*$/.test(line));
    if (launcherStart < 0) {
        return false;
    }

    let launcherEnd = lines.length - 1;
    for (let i = launcherStart + 1; i < lines.length; i += 1) {
        if (/^\S/.test(lines[i])) {
            launcherEnd = i - 1;
            break;
        }
    }

    const hasWeb = lines
        .slice(launcherStart + 1, launcherEnd + 1)
        .some((line) => /^  web:\s*$/.test(line));

    if (hasWeb) {
        return false;
    }

    const webBlock = [
        '  web:',
        '    generate: true',
        '    image_path: "icon.png"',
        '    background_color: "#ffffff"',
        '    theme_color: "#ffffff"',
    ];

    let insertAt = launcherEnd + 1;
    for (let i = launcherStart + 1; i <= launcherEnd; i += 1) {
        if (/^  windows:\s*$/.test(lines[i]) || /^  macos:\s*$/.test(lines[i])) {
            insertAt = i;
            break;
        }
    }

    lines.splice(insertAt, 0, ...webBlock);
    fs.writeFileSync(pubspecPath, `${lines.join('\n')}\n`);
    colorLog('已自动补充 flutter_launcher_icons.web 配置', 'yellow');
    return true;
}

function normalizePubspecAssetEntry(entry) {
    const trimmed = entry.trim();
    if (!trimmed) {
        return '';
    }
    if (
        (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith('\'') && trimmed.endsWith('\''))
    ) {
        return trimmed.slice(1, -1).trim();
    }
    return trimmed;
}

function normalizeAssetPath(entry) {
    return entry.replace(/\\/g, '/').replace(/^\.\//, '').replace(/\/{2,}/g, '/').trim();
}

function readPubspecAssetEntries(projectDir) {
    const pubspecPath = path.join(projectDir, 'pubspec.yaml');
    if (!fs.existsSync(pubspecPath)) {
        return [];
    }

    const lines = fs.readFileSync(pubspecPath, 'utf8').split(/\r?\n/);
    const entries = [];
    let inFlutter = false;
    let inAssets = false;

    for (const line of lines) {
        if (/^flutter:\s*$/.test(line)) {
            inFlutter = true;
            inAssets = false;
            continue;
        }

        if (inFlutter && /^\S/.test(line)) {
            inFlutter = false;
            inAssets = false;
        }
        if (!inFlutter) {
            continue;
        }

        if (/^  assets:\s*$/.test(line)) {
            inAssets = true;
            continue;
        }

        if (inAssets && /^  [^\s-]/.test(line)) {
            inAssets = false;
        }
        if (!inAssets) {
            continue;
        }

        const match = line.match(/^\s{4}-\s+(.+)$/);
        if (!match) {
            continue;
        }

        const rawEntry = match[1].replace(/\s+#.*$/, '');
        const entry = normalizePubspecAssetEntry(rawEntry);
        if (entry) {
            entries.push(entry);
        }
    }

    return entries;
}

function findPubspecAssetsBlock(lines) {
    let inFlutter = false;

    for (let i = 0; i < lines.length; i += 1) {
        const line = lines[i];

        if (/^flutter:\s*$/.test(line)) {
            inFlutter = true;
            continue;
        }

        if (inFlutter && /^\S/.test(line)) {
            inFlutter = false;
        }
        if (!inFlutter) {
            continue;
        }

        if (!/^  assets:\s*$/.test(line)) {
            continue;
        }

        let end = i;
        while (end + 1 < lines.length) {
            const next = lines[end + 1];
            if (/^\s{4}-\s+/.test(next) || /^\s*$/.test(next)) {
                end += 1;
                continue;
            }
            break;
        }

        return { start: i, end };
    }

    return null;
}

function collectDirectoryAssetEntries(relativeRoot, absoluteRoot) {
    if (!fs.existsSync(absoluteRoot)) {
        return [];
    }
    try {
        if (!fs.statSync(absoluteRoot).isDirectory()) {
            return [];
        }
    } catch (_) {
        return [];
    }

    const entries = [];

    const walk = (currentAbs, relativeSuffix) => {
        const joined = relativeSuffix ? `${relativeRoot}/${relativeSuffix}` : relativeRoot;
        const normalized = normalizeAssetPath(joined).replace(/\/+$/, '');
        entries.push(`${normalized}/`);

        let children = [];
        try {
            children = fs.readdirSync(currentAbs, { withFileTypes: true });
        } catch (_) {
            return;
        }

        const childDirs = children
            .filter((entry) => entry.isDirectory() && !entry.name.startsWith('.'))
            .map((entry) => entry.name)
            .sort((a, b) => a.localeCompare(b));

        for (const dirName of childDirs) {
            const childAbs = path.join(currentAbs, dirName);
            const childSuffix = relativeSuffix ? `${relativeSuffix}/${dirName}` : dirName;
            walk(childAbs, childSuffix);
        }
    };

    walk(absoluteRoot, '');
    return entries;
}

function collectGameScriptAssetEntries(projectDir) {
    let dirEntries = [];
    try {
        dirEntries = fs.readdirSync(projectDir, { withFileTypes: true });
    } catch (_) {
        return [];
    }

    const scriptRoots = dirEntries
        .filter((entry) => entry.isDirectory())
        .map((entry) => entry.name)
        .filter((name) => name === 'GameScript' || name.startsWith('GameScript_'))
        .sort((a, b) => a.localeCompare(b));

    const results = [];
    for (const dirName of scriptRoots) {
        const absoluteRoot = path.join(projectDir, dirName);
        results.push(...collectDirectoryAssetEntries(dirName, absoluteRoot));
    }
    return results;
}

function buildAutoPubspecAssetEntries(projectDir) {
    const entries = [];

    const defaultGamePath = path.join(projectDir, 'default_game.txt');
    if (fs.existsSync(defaultGamePath)) {
        entries.push('default_game.txt');
    }

    entries.push(...collectDirectoryAssetEntries('Assets', path.join(projectDir, 'Assets')));
    entries.push(...collectGameScriptAssetEntries(projectDir));

    const existingEntries = readPubspecAssetEntries(projectDir);
    for (const rawEntry of existingEntries) {
        const entry = normalizeAssetPath(rawEntry);
        if (!entry) {
            continue;
        }

        if (entry === 'default_game.txt') {
            continue;
        }
        if (/^Assets(?:\/|$)/.test(entry)) {
            continue;
        }
        if (/^GameScript(?:\/|_|$)/.test(entry)) {
            continue;
        }

        if (entry.startsWith('packages/')) {
            entries.push(entry);
            continue;
        }

        const fullPath = path.join(projectDir, entry.replace(/\/+$/, ''));
        if (!fs.existsSync(fullPath)) {
            continue;
        }
        entries.push(entry);
    }

    const uniqueEntries = [];
    const seen = new Set();
    for (const rawEntry of entries) {
        const normalized = normalizeAssetPath(rawEntry);
        if (!normalized || seen.has(normalized)) {
            continue;
        }
        seen.add(normalized);
        uniqueEntries.push(normalized);
    }

    return uniqueEntries;
}

function syncPubspecAssets(projectDir) {
    const pubspecPath = path.join(projectDir, 'pubspec.yaml');
    if (!fs.existsSync(pubspecPath)) {
        colorLog('错误: 找不到 pubspec.yaml，无法同步 flutter.assets', 'red');
        return { ok: false, changed: false, entryCount: 0 };
    }

    try {
        const raw = fs.readFileSync(pubspecPath, 'utf8');
        const lines = raw.split(/\r?\n/);
        if (lines.length > 0 && lines[lines.length - 1] === '') {
            lines.pop();
        }
        const assetsBlock = findPubspecAssetsBlock(lines);
        if (!assetsBlock) {
            colorLog('错误: pubspec.yaml 中未找到 flutter/assets 段，无法自动同步', 'red');
            return { ok: false, changed: false, entryCount: 0 };
        }

        const entries = buildAutoPubspecAssetEntries(projectDir);
        const generatedBlock = ['  assets:', ...entries.map((entry) => `    - ${entry}`)];
        const newLines = [
            ...lines.slice(0, assetsBlock.start),
            ...generatedBlock,
            ...lines.slice(assetsBlock.end + 1),
        ];
        const nextRaw = `${newLines.join('\n')}\n`;
        const rawNormalized = raw.endsWith('\n') ? raw : `${raw}\n`;
        const changed = rawNormalized !== nextRaw;

        if (changed) {
            fs.writeFileSync(pubspecPath, nextRaw);
            colorLog(`已自动同步 pubspec.yaml 的 flutter.assets（${entries.length} 项）`, 'green');
        }

        return { ok: true, changed, entryCount: entries.length };
    } catch (error) {
        colorLog(`自动同步 flutter.assets 失败: ${error.message}`, 'red');
        return { ok: false, changed: false, entryCount: 0 };
    }
}

function findMissingPubspecAssets(projectDir) {
    const entries = readPubspecAssetEntries(projectDir);
    const missing = [];

    for (const entry of entries) {
        if (entry.startsWith('packages/')) {
            continue;
        }

        const normalizedEntry = entry.replace(/\\/g, '/').replace(/^\.\//, '');
        const fullPath = path.join(projectDir, normalizedEntry);

        if (!fs.existsSync(fullPath)) {
            missing.push(normalizedEntry);
            continue;
        }

        if (normalizedEntry.endsWith('/')) {
            try {
                if (!fs.statSync(fullPath).isDirectory()) {
                    missing.push(normalizedEntry);
                }
            } catch (_) {
                missing.push(normalizedEntry);
            }
        }
    }

    return missing;
}

function ensurePubspecAssetsExist(projectDir) {
    const missingBeforeSync = findMissingPubspecAssets(projectDir);
    if (missingBeforeSync.length > 0) {
        colorLog(`检测到 pubspec.yaml 中有 ${missingBeforeSync.length} 个不存在的资源声明，正在自动同步 flutter.assets...`, 'yellow');
    }

    const syncResult = syncPubspecAssets(projectDir);
    if (!syncResult.ok) {
        return false;
    }

    const missing = findMissingPubspecAssets(projectDir);
    if (missing.length === 0) {
        if (missingBeforeSync.length > 0) {
            colorLog('无效资源声明已自动修复。', 'green');
        }
        return true;
    }

    colorLog(`检测到 pubspec.yaml 中有 ${missing.length} 个不存在的资源声明:`, 'red');
    const preview = missing.slice(0, 20);
    for (const entry of preview) {
        colorLog(`  - ${entry}`, 'red');
    }
    if (missing.length > preview.length) {
        colorLog(`  ... 其余 ${missing.length - preview.length} 项已省略`, 'red');
    }
    colorLog('自动同步后仍存在无效声明，请检查 pubspec.yaml 的 flutter.assets。', 'yellow');
    return false;
}

function generateAppIcons(projectDir) {
    const pubspecPath = path.join(projectDir, 'pubspec.yaml');
    const iconPath = path.join(projectDir, 'icon.png');

    if (!fs.existsSync(iconPath)) {
        colorLog('跳过图标生成: 未找到 icon.png', 'yellow');
        return true;
    }
    if (!fs.existsSync(pubspecPath)) {
        return true;
    }

    const pubspec = fs.readFileSync(pubspecPath, 'utf8');
    if (!pubspec.includes('flutter_launcher_icons:')) {
        colorLog('跳过图标生成: pubspec 未配置 flutter_launcher_icons', 'yellow');
        return true;
    }

    try {
        ensureWebIconConfig(pubspecPath);
        colorLog('正在生成应用图标...', 'yellow');
        execSync('flutter pub run flutter_launcher_icons:main', {
            cwd: projectDir,
            stdio: 'inherit',
        });
        return true;
    } catch (error) {
        colorLog(`图标生成失败，继续执行: ${error.message}`, 'yellow');
        return false;
    }
}

function readWindowsBinaryName(projectDir) {
    const windowsCmakePath = path.join(projectDir, 'windows', 'CMakeLists.txt');
    if (!fs.existsSync(windowsCmakePath)) {
        return null;
    }
    const content = fs.readFileSync(windowsCmakePath, 'utf8');
    const match = content.match(/set\(BINARY_NAME\s+"([^"]+)"\)/);
    if (!match || !match[1]) {
        return null;
    }
    return match[1].trim();
}

function fixWindowsInstallPrefixCache(projectDir) {
    const cachePath = path.join(projectDir, 'build', 'windows', 'x64', 'CMakeCache.txt');
    if (!fs.existsSync(cachePath)) {
        return false;
    }

    const lines = fs.readFileSync(cachePath, 'utf8').split(/\r?\n/);
    const installPrefixLineIndex = lines.findIndex((line) => line.startsWith('CMAKE_INSTALL_PREFIX:PATH='));
    if (installPrefixLineIndex < 0) {
        return false;
    }

    const currentLine = lines[installPrefixLineIndex];
    const currentValue = currentLine.slice('CMAKE_INSTALL_PREFIX:PATH='.length);
    if (!/program files/i.test(currentValue)) {
        return false;
    }

    const binaryName = readWindowsBinaryName(projectDir);
    if (!binaryName) {
        return false;
    }

    const desiredPrefix = `$<TARGET_FILE_DIR:${binaryName}>`;
    const desiredLine = `CMAKE_INSTALL_PREFIX:PATH=${desiredPrefix}`;
    if (currentLine === desiredLine) {
        return false;
    }

    lines[installPrefixLineIndex] = desiredLine;
    fs.writeFileSync(cachePath, `${lines.join('\n')}\n`);
    colorLog(`修复 Windows CMake 安装前缀缓存: ${currentValue} -> ${desiredPrefix}`, 'yellow');
    return true;
}

module.exports = {
    readDefaultGame,
    validateGameDir,
    readGameConfig,
    setAppIdentity,
    ensureProjectIcon,
    ensurePubspecAssetsExist,
    fixWindowsInstallPrefixCache,
    generateAppIcons,
    writeDefaultGame,
    getGameDirectories,
    colorLog,
};
