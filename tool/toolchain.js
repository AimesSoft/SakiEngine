const crypto = require('crypto');
const fs = require('fs');
const https = require('https');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

function detectHostOS() {
  switch (process.platform) {
    case 'darwin':
      return 'macos';
    case 'linux':
      return 'linux';
    case 'win32':
      return 'windows';
    default:
      return 'unknown';
  }
}

function detectHostArch() {
  switch (os.arch()) {
    case 'x64':
      return 'x64';
    case 'arm64':
      return 'arm64';
    default:
      return 'unknown';
  }
}

function commandPath(command) {
  const whichCmd = process.platform === 'win32' ? 'where' : 'which';
  const result = spawnSync(whichCmd, [command], { encoding: 'utf8' });
  if (result.status !== 0) {
    return null;
  }
  const line = (result.stdout || '')
    .split(/\r?\n/)
    .map((v) => v.trim())
    .find(Boolean);
  return line || null;
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function fetchBuffer(url) {
  return new Promise((resolve, reject) => {
    const request = https.get(url, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        resolve(fetchBuffer(res.headers.location));
        return;
      }
      if (res.statusCode !== 200) {
        reject(new Error(`HTTP ${res.statusCode} for ${url}`));
        return;
      }
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    });
    request.on('error', reject);
  });
}

async function downloadFile(url, outputPath) {
  const data = await fetchBuffer(url);
  ensureDir(path.dirname(outputPath));
  fs.writeFileSync(outputPath, data);
}

function sha256File(filePath) {
  const hash = crypto.createHash('sha256');
  const fd = fs.openSync(filePath, 'r');
  const buffer = Buffer.allocUnsafe(1024 * 1024);
  try {
    while (true) {
      const bytes = fs.readSync(fd, buffer, 0, buffer.length, null);
      if (bytes <= 0) break;
      hash.update(buffer.subarray(0, bytes));
    }
  } finally {
    fs.closeSync(fd);
  }
  return hash.digest('hex');
}

function extractArchive(archivePath, destination) {
  ensureDir(destination);
  const archiveLower = archivePath.toLowerCase();
  if (archiveLower.endsWith('.zip')) {
    if (process.platform === 'win32') {
      const ps = spawnSync(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          `Expand-Archive -Path '${archivePath.replace(/'/g, "''")}' -DestinationPath '${destination.replace(/'/g, "''")}' -Force`,
        ],
        { stdio: 'inherit' },
      );
      if (ps.status !== 0) {
        throw new Error(`Expand-Archive failed for ${archivePath}`);
      }
      return;
    }
    const unzip = spawnSync('unzip', ['-q', archivePath, '-d', destination], {
      stdio: 'inherit',
    });
    if (unzip.status !== 0) {
      throw new Error(`unzip failed for ${archivePath}`);
    }
    return;
  }

  const tar = spawnSync('tar', ['-xf', archivePath, '-C', destination], {
    stdio: 'inherit',
  });
  if (tar.status !== 0) {
    throw new Error(`tar extract failed for ${archivePath}`);
  }
}

function readFlutterReleaseInfo(metadata, hostOS, hostArch) {
  const stableHash = metadata.current_release?.stable;
  if (!stableHash) {
    throw new Error('Invalid Flutter metadata: missing stable hash');
  }
  const releases = Array.isArray(metadata.releases) ? metadata.releases : [];
  const stableRelease = releases.find((r) => r.hash === stableHash);
  if (!stableRelease) {
    throw new Error('Invalid Flutter metadata: missing stable release');
  }

  let target = stableRelease;
  if (hostOS === 'macos') {
    const stableVersion = stableRelease.version;
    const stableSameVersion = releases.filter(
      (r) => r.channel === 'stable' && r.version === stableVersion,
    );
    const archKeyword = hostArch === 'arm64' ? 'arm64' : 'x64';
    const matched = stableSameVersion.find((r) =>
      String(r.archive || '').includes(archKeyword),
    );
    if (matched) {
      target = matched;
    }
  }

  const baseUrl = String(metadata.base_url || '').replace(/\/+$/, '');
  const archive = target.archive;
  const version = target.version || 'unknown';
  const sha256 = target.sha256 || '';
  if (!baseUrl || !archive) {
    throw new Error('Invalid Flutter metadata: missing archive/base_url');
  }
  return {
    version,
    archive,
    sha256,
    url: `${baseUrl}/${archive}`,
  };
}

async function ensureLocalFlutter(repoRoot, hostOS, hostArch) {
  const metadataUrlMap = {
    linux: 'https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json',
    macos: 'https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json',
    windows: 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json',
  };
  const metadataUrl = metadataUrlMap[hostOS];
  if (!metadataUrl) {
    throw new Error(`Unsupported OS for Flutter bootstrap: ${hostOS}`);
  }

  const toolchainRoot = path.join(repoRoot, '.saki_toolchain');
  const cacheDir = path.join(repoRoot, 'tool', 'toolchain_cache', 'flutter');
  const marker = path.join(toolchainRoot, 'flutter', '.current_path');
  ensureDir(path.dirname(marker));
  ensureDir(cacheDir);

  if (fs.existsSync(marker)) {
    const markerRoot = fs.readFileSync(marker, 'utf8').trim();
    const flutterBin = path.join(
      markerRoot,
      'bin',
      process.platform === 'win32' ? 'flutter.bat' : 'flutter',
    );
    if (fs.existsSync(flutterBin)) {
      return flutterBin;
    }
  }

  const metadata = JSON.parse((await fetchBuffer(metadataUrl)).toString('utf8'));
  const release = readFlutterReleaseInfo(metadata, hostOS, hostArch);
  const archivePath = path.join(cacheDir, release.archive);

  if (fs.existsSync(archivePath) && release.sha256) {
    const got = sha256File(archivePath);
    if (got !== release.sha256) {
      fs.rmSync(archivePath, { force: true });
    }
  }

  if (!fs.existsSync(archivePath)) {
    console.log(`正在下载 Flutter SDK: ${release.version}`);
    await downloadFile(release.url, archivePath);
  }

  if (release.sha256) {
    const got = sha256File(archivePath);
    if (got !== release.sha256) {
      throw new Error(`Flutter archive checksum mismatch: ${release.archive}`);
    }
  }

  const installDir = path.join(
    toolchainRoot,
    'flutter',
    `flutter-${release.version}-${hostOS}-${hostArch}`,
  );
  let flutterRoot = path.join(installDir, 'flutter');
  let flutterBin = path.join(
    flutterRoot,
    'bin',
    process.platform === 'win32' ? 'flutter.bat' : 'flutter',
  );

  if (!fs.existsSync(flutterBin)) {
    fs.rmSync(installDir, { recursive: true, force: true });
    ensureDir(installDir);
    extractArchive(archivePath, installDir);
    if (!fs.existsSync(flutterBin)) {
      const firstDir = fs
        .readdirSync(installDir, { withFileTypes: true })
        .find((d) => d.isDirectory());
      if (firstDir) {
        flutterRoot = path.join(installDir, firstDir.name);
        flutterBin = path.join(
          flutterRoot,
          'bin',
          process.platform === 'win32' ? 'flutter.bat' : 'flutter',
        );
      }
    }
  }

  if (!fs.existsSync(flutterBin)) {
    throw new Error('Flutter SDK extraction succeeded but flutter executable not found');
  }

  fs.writeFileSync(marker, `${flutterRoot}\n`);
  return flutterBin;
}

function prependPath(dir, delimiter) {
  const current = process.env.PATH || '';
  const entries = current.split(delimiter).filter(Boolean);
  if (!entries.includes(dir)) {
    process.env.PATH = `${dir}${delimiter}${current}`;
  }
}

async function ensureToolchain(repoRoot, options = {}) {
  const hostOS = detectHostOS();
  const hostArch = detectHostArch();
  if (hostOS === 'unknown' || hostArch === 'unknown') {
    throw new Error(`Unsupported host: os=${hostOS} arch=${hostArch}`);
  }

  const preferSystem = options.preferSystem !== false;
  const forceLocal = process.env.SAKI_FORCE_LOCAL_TOOLCHAIN === '1';
  const useSystemFlutter = preferSystem && !forceLocal;

  const systemFlutter = useSystemFlutter ? commandPath('flutter') : null;
  const flutterBin = systemFlutter || (await ensureLocalFlutter(repoRoot, hostOS, hostArch));
  const nodeBin = process.execPath;

  const delimiter = process.platform === 'win32' ? ';' : ':';
  prependPath(path.dirname(nodeBin), delimiter);
  prependPath(path.dirname(flutterBin), delimiter);

  process.env.SAKI_FLUTTER_BIN = flutterBin;
  process.env.SAKI_NODE_BIN = nodeBin;
  process.env.SAKI_TOOLCHAIN_READY = '1';

  return {
    flutterBin,
    nodeBin,
    hostOS,
    hostArch,
  };
}

module.exports = {
  ensureToolchain,
  detectHostOS,
  detectHostArch,
};
