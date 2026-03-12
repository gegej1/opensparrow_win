/**
 * ClawBot (openclaw) Local Management UI Backend
 * Node.js ESM HTTP server - no npm dependencies, uses only built-in modules.
 * Port default: 18899, auto-increments if busy.
 */

import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import os from 'node:os'

// ---------------------------------------------------------------------------
// Path setup
// ---------------------------------------------------------------------------

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const PACK_ROOT = path.resolve(__dirname, '..')          // usb-pack/
const OC_ENTRY  = path.join(PACK_ROOT, 'runtime/openclaw/openclaw.mjs')
const PROFILE   = process.env.OPENCLAW_PROFILE ?? 'usb-portable'
const PROFILE_DIR = path.join(os.homedir(), `.openclaw-${PROFILE}`)
const CONFIG_FILE = path.join(PROFILE_DIR, 'openclaw.json')
const WORKSPACE_DIR = path.join(PROFILE_DIR, 'workspace')
const PUBLIC_DIR  = path.join(__dirname, 'public')

const SKILLS_SRC = path.join(PACK_ROOT, 'skills', 'superpowers')
const SKILL_TARGETS = [
  path.join(os.homedir(), '.claude', 'skills', 'superpowers'),
  path.join(os.homedir(), '.codex', 'skills', 'superpowers'),
]

const DEFAULT_PORT = 19000
const GATEWAY_PORT = 18889
const AUTO_OPEN_BROWSER = !['0', 'false', 'no', 'off'].includes(
  String(process.env.OPENSPARROW_AUTO_OPEN ?? '').trim().toLowerCase()
)

const OC_TIMEOUT = {
  DEFAULT: 120000,
  STATUS: 10000,
  CONFIG_SET: 20000,
  MODEL_SET: 20000,
  DAEMON_STOP: 20000,
  DAEMON_UNINSTALL: 20000,
  DAEMON_INSTALL: 45000,
  DAEMON_RESTART: 80000,
  PLUGIN_INSTALL: 180000,
  UNINSTALL_FULL: 90000,
}

function resolveBundledNodeBinary() {
  const candidates = process.platform === 'win32'
    ? [
        path.join(PACK_ROOT, 'runtime/node/node.exe'),
        path.join(PACK_ROOT, 'runtime/node/bin/node.exe'),
        path.join(PACK_ROOT, 'runtime/node/bin/node'),
      ]
    : [
        path.join(PACK_ROOT, 'runtime/node/bin/node'),
        path.join(PACK_ROOT, 'runtime/node/node'),
        path.join(PACK_ROOT, 'runtime/node/node.exe'),
      ]

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate
  }
  return candidates[0]
}

const NODE_BIN = resolveBundledNodeBinary()

// ---------------------------------------------------------------------------
// Utility: run an oc command via the bundled Node binary
// ---------------------------------------------------------------------------

/**
 * Execute an openclaw command.
 * @param {string[]} args  Arguments passed after `openclaw.mjs --profile $PROFILE`
 * @param {{timeoutMs?: number, opName?: string}} [options]
 * @returns {Promise<{stdout: string, stderr: string, code: number}>}
 */
async function runOc(args, options = {}) {
  return new Promise((resolve) => {
    const timeoutMs = Number.isFinite(options?.timeoutMs) && options.timeoutMs > 0
      ? options.timeoutMs
      : OC_TIMEOUT.DEFAULT
    const opName = typeof options?.opName === 'string' && options.opName.trim()
      ? options.opName.trim()
      : `openclaw ${args.join(' ')}`
    let timedOut = false
    let settled = false

    const done = (result) => {
      if (settled) return
      settled = true
      if (timeoutId) clearTimeout(timeoutId)
      resolve(result)
    }

    const proc = spawn(
      NODE_BIN,
      [OC_ENTRY, '--profile', PROFILE, ...args],
      {
        env: { ...process.env, CI: process.env.CI ?? '1' },
        stdio: ['ignore', 'pipe', 'pipe'],
      }
    )

    let stdout = ''
    let stderr = ''

    proc.stdout.on('data', (chunk) => { stdout += chunk.toString() })
    proc.stderr.on('data', (chunk) => { stderr += chunk.toString() })

    const timeoutId = setTimeout(() => {
      timedOut = true
      try {
        proc.kill('SIGTERM')
      } catch {}
      setTimeout(() => {
        try {
          proc.kill('SIGKILL')
        } catch {}
      }, 1500).unref()
    }, timeoutMs)

    proc.on('close', (code) => {
      if (timedOut) {
        const timeoutMsg = `Command timed out after ${timeoutMs}ms: ${opName}`
        const mergedErr = stderr ? `${stderr}\n${timeoutMsg}` : timeoutMsg
        done({ stdout, stderr: mergedErr, code: 124 })
        return
      }
      done({ stdout, stderr, code: code ?? 0 })
    })

    proc.on('error', (err) => {
      const mergedErr = [stderr, err.message].filter(Boolean).join('\n')
      done({ stdout, stderr: mergedErr, code: 1 })
    })
  })
}

// ---------------------------------------------------------------------------
// Utility: port availability
// ---------------------------------------------------------------------------

/**
 * Check whether a TCP port is already in use on localhost.
 * @param {number} port
 * @returns {Promise<boolean>}
 */
async function isPortBusy(port) {
  const hosts = ['127.0.0.1', '::1']
  for (const host of hosts) {
    if (await isPortBusyOnHost(port, host)) return true
  }
  return false
}

/**
 * Check whether a TCP port is in use on a specific host.
 * @param {number} port
 * @param {string} host
 * @returns {Promise<boolean>}
 */
async function isPortBusyOnHost(port, host) {
  return new Promise((resolve) => {
    const server = http.createServer()
    server.listen(port, host, () => {
      server.close(() => resolve(false))
    })
    server.on('error', (err) => {
      if (err?.code === 'EADDRINUSE' || err?.code === 'EACCES') {
        resolve(true)
        return
      }
      // e.g. EADDRNOTAVAIL / EAFNOSUPPORT: treat as non-busy for this host.
      resolve(false)
    })
  })
}

/**
 * Find the first available port starting from `start`.
 * @param {number} start
 * @returns {Promise<number>}
 */
async function findPort(start) {
  let port = start
  while (await isPortBusy(port)) {
    port++
  }
  return port
}

/**
 * Strip ANSI escape sequences from text.
 * @param {string} text
 * @returns {string}
 */
function stripAnsi(text) {
  return String(text ?? '').replace(/\x1b\[[0-9;]*m/g, '')
}

/**
 * Build a compact error summary from openclaw command result.
 * @param {{stdout?: string, stderr?: string, code?: number}} result
 * @param {string} [fallback]
 * @returns {string}
 */
function summarizeOcIssue(result, fallback = 'unknown error') {
  const stderr = stripAnsi(result?.stderr).trim()
  if (stderr) return stderr
  const stdout = stripAnsi(result?.stdout).trim()
  if (stdout) return stdout
  if (Number.isFinite(result?.code)) return `exit code ${result.code}`
  return fallback
}

/**
 * Normalize user-provided OpenAI-compatible base URL.
 * - Host-only input -> append /v1
 * - Endpoint input (e.g. .../chat/completions) -> trim to provider base
 * - Custom non-root path is preserved
 * @param {string | null | undefined} rawInput
 * @param {string} [fallback]
 * @returns {string}
 */
function normalizeOpenAIBaseUrl(rawInput, fallback = 'https://api.openai.com/v1') {
  const fallbackValue = String(fallback || 'https://api.openai.com/v1').trim()
  const raw = String(rawInput ?? '').trim()
  if (!raw) return fallbackValue

  let candidate = raw
  const hasScheme = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(candidate)
  if (!hasScheme && candidate.includes('.')) {
    candidate = `https://${candidate}`
  }

  let parsed
  try {
    parsed = new URL(candidate)
  } catch {
    return raw.replace(/\/+$/, '') || fallbackValue
  }

  if (!/^https?:$/i.test(parsed.protocol)) {
    return raw.replace(/\/+$/, '') || fallbackValue
  }

  let pathname = (parsed.pathname || '/').replace(/\/+$/, '')
  pathname = pathname.replace(
    /\/(chat\/completions|responses|models|completions|embeddings|audio\/transcriptions)$/i,
    ''
  )

  if (!pathname || pathname === '/') pathname = '/v1'

  parsed.pathname = pathname
  parsed.search = ''
  parsed.hash = ''

  return parsed.toString().replace(/\/+$/, '')
}

/**
 * Display path with ~ prefix when under user home.
 * @param {string} absolutePath
 * @returns {string}
 */
function toUserPath(absolutePath) {
  const home = os.homedir()
  if (absolutePath.startsWith(home)) {
    return `~${absolutePath.slice(home.length)}`
  }
  return absolutePath
}

/**
 * Map daemon status token to normalized state.
 * @param {string} raw
 * @returns {'running'|'stopped'|'not_installed'|'unknown'}
 */
function mapDaemonToken(raw) {
  const token = String(raw ?? '').trim().toLowerCase()
  if (!token) return 'unknown'
  if (token === 'not_installed' || token === 'not-installed' || token.includes('not install')) {
    return 'not_installed'
  }
  if (token.includes('stopped') || token.includes('not running')) return 'stopped'
  if (token === 'stopped' || token === 'inactive' || token === 'dead' || token === 'exited') {
    return 'stopped'
  }
  if (token === 'running' || token === 'online' || token === 'active' || token === 'started') {
    return 'running'
  }
  if (token.includes('running') || token.includes('active')) return 'running'
  return 'unknown'
}

/**
 * Parse daemon state from `openclaw daemon status --json` payload.
 * @param {any} parsed
 * @returns {'running'|'stopped'|'not_installed'|'unknown'}
 */
function parseDaemonStateFromJson(parsed) {
  const candidates = [
    parsed?.status,
    parsed?.service?.runtime?.status,
    parsed?.service?.runtime?.state,
  ]
  for (const candidate of candidates) {
    const mapped = mapDaemonToken(candidate)
    if (mapped !== 'unknown') return mapped
  }

  const command = parsed?.service?.command
  if (command === null) return 'not_installed'
  if (command && typeof command === 'object') return 'stopped'

  return 'unknown'
}

/**
 * Parse daemon state from command execution result.
 * @param {{stdout: string, stderr: string, code: number}} result
 * @returns {'running'|'stopped'|'not_installed'|'unknown'}
 */
function parseDaemonStateFromResult(result) {
  const cleanOut = stripAnsi(result.stdout).trim()
  const cleanErr = stripAnsi(result.stderr).trim().toLowerCase()

  if (cleanOut) {
    try {
      const parsed = JSON.parse(cleanOut)
      return parseDaemonStateFromJson(parsed)
    } catch {
      const mapped = mapDaemonToken(cleanOut)
      if (mapped !== 'unknown') return mapped
    }
  }

  if (result.code !== 0) {
    if (cleanErr.includes('not install') || cleanErr.includes('could not find service')) {
      return 'not_installed'
    }
    if (cleanErr.includes('stopped') || cleanErr.includes('not running')) {
      return 'stopped'
    }
  }

  return 'unknown'
}

/**
 * Whether daemon install/restart failure indicates schtasks permission denial.
 * @param {string} detail
 * @returns {boolean}
 */
function isSchtasksPermissionDenied(detail) {
  const text = stripAnsi(detail).toLowerCase()
  if (!text.includes('schtasks')) return false
  return (
    text.includes('access is denied') ||
    text.includes('denied') ||
    text.includes('拒绝访问') ||
    text.includes('�ܾ')
  )
}

/**
 * Whether daemon operation failed because service is missing/not installed.
 * @param {string} detail
 * @returns {boolean}
 */
function isDaemonNotInstalledIssue(detail) {
  const text = stripAnsi(detail).toLowerCase()
  return (
    text.includes('not install') ||
    text.includes('cannot find') ||
    text.includes('could not find service')
  )
}

/**
 * Wait until a TCP port reaches the desired busy state.
 * @param {number} port
 * @param {boolean} targetBusy
 * @param {number} timeoutMs
 * @returns {Promise<boolean>}
 */
async function waitForPortState(port, targetBusy, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const busy = await isPortBusy(port)
    if (busy === targetBusy) return true
    await new Promise((resolve) => setTimeout(resolve, 300))
  }
  return (await isPortBusy(port)) === targetBusy
}

/**
 * Start gateway runtime in background process (no daemon/schtasks).
 * @returns {Promise<{alreadyRunning: boolean, pid: number | null}>}
 */
async function startGatewayFallbackRuntime() {
  if (await isPortBusy(GATEWAY_PORT)) {
    return { alreadyRunning: true, pid: null }
  }

  const child = spawn(
    NODE_BIN,
    [OC_ENTRY, '--profile', PROFILE, 'gateway', 'run', '--port', String(GATEWAY_PORT), '--bind', 'loopback'],
    {
      env: { ...process.env, CI: process.env.CI ?? '1' },
      detached: true,
      windowsHide: true,
      stdio: 'ignore',
      cwd: PACK_ROOT,
    }
  )
  child.unref()

  const ready = await waitForPortState(GATEWAY_PORT, true, 20000)
  if (!ready) {
    throw new Error(`gateway fallback process did not open port ${GATEWAY_PORT}`)
  }

  return { alreadyRunning: false, pid: child.pid ?? null }
}

/**
 * Install daemon; on Windows permission-denied schtasks, fallback to background gateway.
 * @returns {Promise<{ok: boolean, mode?: 'daemon'|'gateway-fallback', warning?: string, error?: string}>}
 */
async function installGatewayRuntimeWithFallback() {
  const r = await runOc(['daemon', 'install', '--force', '--port', String(GATEWAY_PORT)], {
    timeoutMs: OC_TIMEOUT.DAEMON_INSTALL,
    opName: 'daemon install',
  })
  if (r.code === 0) return { ok: true, mode: 'daemon' }

  const detail = summarizeOcIssue(r)
  if (process.platform === 'win32' && isSchtasksPermissionDenied(detail)) {
    try {
      await startGatewayFallbackRuntime()
      return {
        ok: true,
        mode: 'gateway-fallback',
        warning: `daemon install skipped (schtasks permission denied): ${detail}`,
      }
    } catch (e) {
      return {
        ok: false,
        error: `daemon install failed: ${detail}; gateway fallback failed: ${e?.message ?? String(e)}`,
      }
    }
  }

  return { ok: false, error: `daemon install failed: ${detail}` }
}

/**
 * Restart gateway runtime, with fallback when daemon is unavailable on Windows.
 * @returns {Promise<{ok: boolean, mode?: 'daemon'|'gateway-fallback', warning?: string, error?: string}>}
 */
async function restartGatewayRuntimeWithFallback() {
  const r = await runOc(['daemon', 'restart'], {
    timeoutMs: OC_TIMEOUT.DAEMON_RESTART,
    opName: 'daemon restart',
  })
  if (r.code === 0) return { ok: true, mode: 'daemon' }

  const detail = summarizeOcIssue(r)
  const canFallback = process.platform === 'win32' && (
    isSchtasksPermissionDenied(detail) || isDaemonNotInstalledIssue(detail)
  )
  if (!canFallback) {
    return { ok: false, error: `daemon restart failed: ${detail}` }
  }

  try {
    await startGatewayFallbackRuntime()
    return {
      ok: true,
      mode: 'gateway-fallback',
      warning: `daemon restart skipped, using fallback runtime: ${detail}`,
    }
  } catch (e) {
    return {
      ok: false,
      error: `daemon restart failed: ${detail}; gateway fallback failed: ${e?.message ?? String(e)}`,
    }
  }
}

// ---------------------------------------------------------------------------
// Utility: HTTP helpers
// ---------------------------------------------------------------------------

/**
 * Parse the JSON body from an incoming request.
 * @param {http.IncomingMessage} req
 * @returns {Promise<any>}
 */
function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = ''
    req.on('data', (chunk) => { raw += chunk.toString() })
    req.on('end', () => {
      try {
        resolve(raw ? JSON.parse(raw) : {})
      } catch (e) {
        reject(e)
      }
    })
    req.on('error', reject)
  })
}

/**
 * Send a JSON response.
 * @param {http.ServerResponse} res
 * @param {number} status
 * @param {any} data
 */
function sendJson(res, status, data) {
  const body = JSON.stringify(data)
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body),
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  })
  res.end(body)
}

/**
 * Send a static file from the public directory.
 * @param {http.ServerResponse} res
 * @param {string} filePath  Absolute path to the file
 */
function sendFile(res, filePath) {
  const ext = path.extname(filePath).toLowerCase()
  const mimeMap = {
    '.html': 'text/html; charset=utf-8',
    '.css':  'text/css; charset=utf-8',
    '.js':   'application/javascript; charset=utf-8',
    '.mjs':  'application/javascript; charset=utf-8',
    '.json': 'application/json',
    '.png':  'image/png',
    '.svg':  'image/svg+xml',
    '.ico':  'image/x-icon',
  }
  const contentType = mimeMap[ext] ?? 'application/octet-stream'

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain' })
      res.end('Not Found')
      return
    }
    res.writeHead(200, {
      'Content-Type': contentType,
      'Content-Length': data.length,
    })
    res.end(data)
  })
}

// ---------------------------------------------------------------------------
// Route handlers
// ---------------------------------------------------------------------------

/** GET /api/status */
async function handleStatus(res) {
  const configExists = fs.existsSync(CONFIG_FILE)

  let daemon = 'unknown'
  let runtimeMode = 'daemon'
  try {
    const result = await runOc(['daemon', 'status', '--json'], {
      timeoutMs: OC_TIMEOUT.STATUS,
      opName: 'daemon status',
    })
    daemon = parseDaemonStateFromResult(result)
  } catch {
    daemon = 'unknown'
  }

  // Windows fallback mode: daemon may be "not_installed" while gateway is running.
  if (daemon !== 'running') {
    try {
      const gatewayPortBusy = await isPortBusy(GATEWAY_PORT)
      if (gatewayPortBusy) {
        daemon = 'running'
        runtimeMode = 'gateway-fallback'
      } else {
        runtimeMode = 'stopped'
      }
    } catch {
      runtimeMode = 'unknown'
    }
  }

  const installed = configExists && daemon === 'running'

  sendJson(res, 200, {
    installed,
    daemon,
    runtimeMode,
    profile: PROFILE,
    configPath: `~/.openclaw-${PROFILE}/openclaw.json`,
  })
}

/**
 * Copy bundled superpowers skills to user's Claude and Codex skill directories.
 * @returns {Promise<string[]>} list of error messages (empty if all OK)
 */
async function installSkills() {
  const errors = []

  // Check if source skills directory exists
  if (!fs.existsSync(SKILLS_SRC)) {
    // Not bundled — skip silently (optional component)
    return errors
  }

  for (const dest of SKILL_TARGETS) {
    try {
      fs.mkdirSync(dest, { recursive: true })
      const files = fs.readdirSync(SKILLS_SRC)
      for (const file of files) {
        const src = path.join(SKILLS_SRC, file)
        const dst = path.join(dest, file)
        fs.copyFileSync(src, dst)
      }
    } catch (e) {
      errors.push(`skills copy to ${dest} failed: ${e.message}`)
    }
  }

  return errors
}

/**
 * Remove a directory recursively if it exists.
 * @param {string} target
 * @returns {{removed: boolean, error: string | null}}
 */
function removeDirIfExists(target) {
  try {
    if (!fs.existsSync(target)) return { removed: false, error: null }
    fs.rmSync(target, { recursive: true, force: true })
    return { removed: true, error: null }
  } catch (e) {
    return { removed: false, error: e?.message ?? String(e) }
  }
}

/**
 * Before install/cleanup/reset, attempt to stop and remove existing openclaw daemon,
 * then release fixed gateway port if still occupied.
 * Does not throw — failures are logged only.
 * @param {{port?: number, graceful?: boolean, forceKill?: boolean}} [options]
 * @returns {Promise<{cleaned: boolean, portBusy: boolean, log: string[]}>}
 */
async function cleanupOldDaemon(options = {}) {
  const PORT = Number.isFinite(options?.port) ? options.port : 18889
  const graceful = options?.graceful !== false
  const forceKill = options?.forceKill !== false
  const log = []
  let cleaned = false

  const busyBefore = await isPortBusy(PORT) // true = occupied
  if (busyBefore) {
    log.push(`Port ${PORT} is occupied before cleanup`)
  } else {
    log.push(`Port ${PORT} is free before cleanup`)
  }

  // 1) Graceful cleanup always runs first to clear stale daemon state even if port is currently free.
  if (graceful) {
    try {
      const stopResult = await runOc(['daemon', 'stop'], {
        timeoutMs: OC_TIMEOUT.DAEMON_STOP,
        opName: 'daemon stop',
      })
      if (stopResult.code === 0) {
        cleaned = true
        log.push('daemon stop: OK')
      } else {
        log.push(`daemon stop: failed (${summarizeOcIssue(stopResult)})`)
      }
    } catch (e) {
      log.push(`daemon stop error: ${e?.message ?? String(e)}`)
    }

    try {
      const uninstallResult = await runOc(['daemon', 'uninstall'], {
        timeoutMs: OC_TIMEOUT.DAEMON_UNINSTALL,
        opName: 'daemon uninstall',
      })
      if (uninstallResult.code === 0) {
        cleaned = true
        log.push('daemon uninstall: OK')
      } else {
        log.push(`daemon uninstall: failed (${summarizeOcIssue(uninstallResult)})`)
      }
    } catch (e) {
      log.push(`daemon uninstall error: ${e?.message ?? String(e)}`)
    }
  }

  // 2) Wait briefly for listener to exit after graceful cleanup.
  for (let i = 0; i < 6; i++) {
    const busy = await isPortBusy(PORT)
    if (!busy) {
      log.push(`Port ${PORT} is free after graceful cleanup`)
      return { cleaned, portBusy: false, log }
    }
    await new Promise(r => setTimeout(r, 500))
  }

  const busyAfterGraceful = await isPortBusy(PORT)
  if (!busyAfterGraceful) {
    log.push(`Port ${PORT} is free after cleanup checks`)
    return { cleaned, portBusy: false, log }
  }

  if (!forceKill) {
    log.push(`Port ${PORT} still occupied; force kill disabled`)
    return { cleaned, portBusy: true, log }
  }

  // 3) Force kill if still busy — platform-specific and strictly port-bound.
  log.push(`Port ${PORT} still occupied — attempting force kill...`)
  try {
    const platform = process.platform
    if (platform === 'win32') {
      // Windows: netstat + taskkill
      const { stdout } = await new Promise((resolve) => {
        const proc = spawn('netstat', ['-ano'], { env: { ...process.env } })
        let out = ''
        proc.stdout.on('data', d => { out += d.toString() })
        proc.on('close', () => resolve({ stdout: out }))
        proc.on('error', () => resolve({ stdout: '' }))
      })
      const lines = stdout.split(/\r?\n/)
      const pids = new Set()
      for (const line of lines) {
        const parts = line.trim().split(/\s+/)
        const localAddress = parts[1] ?? ''
        const state = (parts[3] ?? '').toUpperCase()
        const pid = parts[parts.length - 1] ?? ''
        if (state === 'LISTENING' && localAddress.endsWith(`:${PORT}`) && /^\d+$/.test(pid)) {
          pids.add(pid)
        }
      }
      for (const pid of pids) {
        const r = await new Promise((resolve) => {
          const proc = spawn('taskkill', ['/PID', pid, '/F'], { env: { ...process.env } })
          proc.on('close', (code) => resolve(code))
          proc.on('error', () => resolve(1))
        })
        log.push(`taskkill PID ${pid}: ${r === 0 ? 'OK' : 'failed'}`)
      }
      if (pids.size === 0) {
        log.push(`No LISTENING PID found via netstat for port ${PORT}`)
      }
    } else {
      // Mac/Linux: lsof listener PIDs only
      const { stdout } = await new Promise((resolve) => {
        const proc = spawn('lsof', ['-nP', `-tiTCP:${PORT}`, '-sTCP:LISTEN'], { env: { ...process.env } })
        let out = ''
        proc.stdout.on('data', d => { out += d.toString() })
        proc.on('close', () => resolve({ stdout: out }))
        proc.on('error', () => resolve({ stdout: '' }))
      })
      const pids = [...new Set(
        stdout.trim().split(/\r?\n/).map(p => p.trim()).filter(p => /^\d+$/.test(p))
      )]
      for (const pid of pids) {
        const r = await new Promise((resolve) => {
          const proc = spawn('kill', ['-9', pid], { env: { ...process.env } })
          proc.on('close', (code) => resolve(code))
          proc.on('error', () => resolve(1))
        })
        log.push(`kill -9 PID ${pid}: ${r === 0 ? 'OK' : 'failed'}`)
      }
      if (pids.length === 0) {
        log.push(`No LISTENING PID found via lsof for port ${PORT}`)
      }
    }
  } catch (e) {
    log.push(`force kill error: ${e.message}`)
  }

  // 4) Final check
  await new Promise(r => setTimeout(r, 800))
  const stillBusy = await isPortBusy(PORT)
  if (!stillBusy) {
    log.push(`Port ${PORT} freed after force kill`)
    return { cleaned: true, portBusy: false, log }
  }

  log.push(`WARNING: Port ${PORT} still occupied after all cleanup attempts`)
  return { cleaned, portBusy: true, log }
}

/** POST /api/install */
async function handleInstall(res, body) {
  const channels = Array.isArray(body?.channels) ? body.channels : []
  const api = body?.api && typeof body.api === 'object' ? body.api : {}
  const baseUrlRaw = typeof api.baseUrl === 'string' ? api.baseUrl.trim() : ''
  const baseUrl = normalizeOpenAIBaseUrl(baseUrlRaw)
  const apiKey = typeof api.apiKey === 'string' ? api.apiKey.trim() : ''
  const model = typeof api.model === 'string' && api.model.trim() ? api.model.trim() : 'gpt-4o-mini'

  const errors = []
  const warnings = []
  const inputErrors = []

  if (!apiKey) {
    inputErrors.push('API Key 不能为空，请在网页中填写后再安装')
  }
  for (const ch of channels) {
    const type = typeof ch?.type === 'string' ? ch.type : ''
    if (!type) {
      inputErrors.push('渠道类型无效，请重新选择渠道')
      continue
    }
    if (type === 'feishu') {
      if (!String(ch.appId ?? '').trim()) inputErrors.push('飞书 App ID 不能为空')
      if (!String(ch.appSecret ?? '').trim()) inputErrors.push('飞书 App Secret 不能为空')
    } else if (type === 'dingtalk') {
      if (!String(ch.clientId ?? '').trim()) inputErrors.push('钉钉 Client ID 不能为空')
      if (!String(ch.clientSecret ?? '').trim()) inputErrors.push('钉钉 Client Secret 不能为空')
    } else if (type === 'wecom') {
      if (!String(ch.botId ?? '').trim()) inputErrors.push('企业微信 Bot ID 不能为空')
      if (!String(ch.secret ?? '').trim()) inputErrors.push('企业微信 Secret 不能为空')
    }
  }
  if (inputErrors.length > 0) {
    sendJson(res, 400, { ok: false, errors: inputErrors })
    return
  }

  // Step -1: Cleanup stale daemon/service state before install.
  {
    try {
      const { log, portBusy } = await cleanupOldDaemon({ graceful: true, forceKill: true })
      console.log('[cleanup]', log.join(' | '))
      if (portBusy) {
        console.log('[cleanup] warning: Port 18889 is still occupied after pre-install cleanup')
      }
    } catch (e) {
      console.log(`[cleanup] unexpected error: ${e?.message ?? String(e)}`)
    }
  }

  // Step 0: Install bundled superpowers skills
  {
    const skillErrors = await installSkills()
    errors.push(...skillErrors)
  }

  // Step 1: Install channel plugins (non-feishu channels share one package)
  const needsChannelPackage = channels.some(
    (ch) => ch.type === 'dingtalk' || ch.type === 'wecom'
  )
  if (needsChannelPackage) {
    const r = await runOc(['plugins', 'install', '@openclaw-china/channels'], {
      timeoutMs: OC_TIMEOUT.PLUGIN_INSTALL,
      opName: 'plugins install @openclaw-china/channels',
    })
    if (r.code !== 0) errors.push(`plugin install failed: ${r.stderr}`)
  }

  // Step 2: Write base gateway config
  const baseConfigs = [
    ['gateway.mode',   '"local"'],
    ['gateway.bind',   '"loopback"'],
    ['gateway.port',   String(GATEWAY_PORT)],
  ]
  for (const [key, value] of baseConfigs) {
    const r = await runOc(['config', 'set', key, value, '--strict-json'], {
      timeoutMs: OC_TIMEOUT.CONFIG_SET,
      opName: `config set ${key}`,
    })
    if (r.code !== 0) errors.push(`config set ${key} failed: ${r.stderr}`)
  }

  // Step 3: Write API (model provider) config
  // Always write baseUrl and models together — openclaw validates both fields simultaneously
  const effectiveModel = model
  const providerJson = JSON.stringify({
    baseUrl,
    models: [{ id: effectiveModel, name: effectiveModel, api: 'openai-completions' }],
  })
  {
    const r = await runOc([
      'config', 'set',
      'models.providers.openai',
      providerJson,
      '--strict-json',
    ], {
      timeoutMs: OC_TIMEOUT.CONFIG_SET,
      opName: 'config set models.providers.openai',
    })
    if (r.code !== 0) errors.push(`config set models.providers.openai failed: ${r.stderr}`)
  }
  {
    const modelForSet = effectiveModel.includes('/') ? effectiveModel : `openai/${effectiveModel}`
    const r = await runOc(['models', 'set', modelForSet], {
      timeoutMs: OC_TIMEOUT.MODEL_SET,
      opName: `models set ${modelForSet}`,
    })
    if (r.code !== 0) errors.push(`models set ${modelForSet} failed: ${r.stderr}`)
  }

  // Step 4: Write auth-profiles.json with the API key
  if (apiKey) {
    const authDir  = path.join(os.homedir(), `.openclaw-${PROFILE}`, 'agents', 'main', 'agent')
    const authFile = path.join(authDir, 'auth-profiles.json')
    try {
      fs.mkdirSync(authDir, { recursive: true })
      const authData = {
        version: 1,
        profiles: {
          'openai:default': { type: 'api_key', provider: 'openai', key: apiKey },
        },
        order: { openai: ['openai:default'] },
      }
      fs.writeFileSync(authFile, JSON.stringify(authData, null, 2), 'utf8')
    } catch (e) {
      errors.push(`writing auth-profiles.json failed: ${e.message}`)
    }
  }

  // Step 5: Write per-channel config
  for (const ch of channels) {
    const chErrors = await configureChannel(ch)
    errors.push(...chErrors)
  }

  // Step 6: Install daemon
  let runtimeMode = 'daemon'
  {
    const runtimeInstall = await installGatewayRuntimeWithFallback()
    if (!runtimeInstall.ok) {
      errors.push(runtimeInstall.error ?? 'daemon install failed')
    } else if (runtimeInstall.mode) {
      runtimeMode = runtimeInstall.mode
    }
    if (runtimeInstall.warning) warnings.push(runtimeInstall.warning)
  }

  // Step 7: Restart daemon
  if (errors.length === 0 && runtimeMode === 'daemon') {
    const runtimeRestart = await restartGatewayRuntimeWithFallback()
    if (!runtimeRestart.ok) {
      errors.push(runtimeRestart.error ?? 'daemon restart failed')
    } else if (runtimeRestart.mode) {
      runtimeMode = runtimeRestart.mode
    }
    if (runtimeRestart.warning) warnings.push(runtimeRestart.warning)
  }

  if (runtimeMode === 'gateway-fallback') {
    warnings.push('Windows current permission blocks schtasks; running gateway in background fallback mode.')
  }

  if (errors.length > 0) {
    sendJson(res, 500, { ok: false, errors, warnings, runtimeMode })
  } else {
    sendJson(res, 200, { ok: true, warnings, runtimeMode })
  }
}

/**
 * Write configuration for a single channel.
 * @param {{type: string, [key: string]: any}} channel
 * @returns {Promise<string[]>} list of error messages (empty if all OK)
 */
async function configureChannel(channel) {
  const errors = []

  async function oc(...args) {
    const r = await runOc(['config', 'set', ...args, '--strict-json'], {
      timeoutMs: OC_TIMEOUT.CONFIG_SET,
      opName: `config set ${args[0]}`,
    })
    if (r.code !== 0) errors.push(`config set ${args[0]} failed: ${r.stderr}`)
  }

  switch (channel.type) {
    case 'feishu': {
      const { appId = '', appSecret = '' } = channel
      await oc('channels.feishu.enabled',        'true')
      await oc('channels.feishu.connectionMode', '"websocket"')
      await oc('channels.feishu.domain',         '"feishu"')
      await oc('channels.feishu.appId',          JSON.stringify(appId))
      await oc('channels.feishu.appSecret',      JSON.stringify(appSecret))
      await oc('channels.feishu.dmPolicy',       '"open"')
      await oc('channels.feishu.allowFrom',      '["*"]')
      await oc('channels.feishu.requireMention', 'false')
      await oc('plugins.entries.feishu.enabled', 'true')
      break
    }

    case 'dingtalk': {
      const { clientId = '', clientSecret = '' } = channel
      await oc('channels.dingtalk.enabled',                          'true')
      await oc('channels.dingtalk.clientId',                         JSON.stringify(clientId))
      await oc('channels.dingtalk.clientSecret',                     JSON.stringify(clientSecret))
      await oc('gateway.http.endpoints.chatCompletions.enabled',     'true')
      break
    }

    case 'wecom': {
      const { botId = '', secret = '' } = channel
      await oc('channels.wecom.enabled', 'true')
      await oc('channels.wecom.mode',    '"ws"')
      await oc('channels.wecom.botId',   JSON.stringify(botId))
      await oc('channels.wecom.secret',  JSON.stringify(secret))
      break
    }

    default:
      errors.push(`Unknown channel type: ${channel.type}`)
  }

  return errors
}

/** GET /api/config */
function handleGetConfig(res) {
  try {
    const raw = fs.readFileSync(CONFIG_FILE, 'utf8')
    sendJson(res, 200, JSON.parse(raw))
  } catch (e) {
    sendJson(res, 404, { error: `Cannot read config: ${e.message}` })
  }
}

/** POST /api/config/api */
async function handleUpdateApi(res, body) {
  const { baseUrl, apiKey, model } = body
  const errors = []

  // Write baseUrl and models together so openclaw validation passes
  if (baseUrl !== undefined || model !== undefined) {
    // Read current config to avoid overwriting fields not being updated
    let currentBaseUrl = baseUrl
    let currentModel = model

    if (currentBaseUrl === undefined || currentModel === undefined) {
      try {
        const raw = fs.readFileSync(CONFIG_FILE, 'utf8')
        const cfg = JSON.parse(raw)
        const openai = cfg?.models?.providers?.openai ?? {}
        if (currentBaseUrl === undefined) currentBaseUrl = openai.baseUrl ?? 'https://api.openai.com/v1'
        if (currentModel === undefined) {
          const m = Array.isArray(openai.models) ? openai.models[0]?.id : null
          currentModel = m ?? 'gpt-4o-mini'
        }
      } catch {
        currentBaseUrl = currentBaseUrl ?? 'https://api.openai.com/v1'
        currentModel   = currentModel   ?? 'gpt-4o-mini'
      }
    }

    currentBaseUrl = normalizeOpenAIBaseUrl(currentBaseUrl)
    currentModel = typeof currentModel === 'string' ? currentModel.trim() : ''
    if (!currentModel) currentModel = 'gpt-4o-mini'

    const providerJson = JSON.stringify({
      baseUrl: currentBaseUrl,
      models: [{ id: currentModel, name: currentModel, api: 'openai-completions' }],
    })
    const r = await runOc([
      'config', 'set',
      'models.providers.openai',
      providerJson,
      '--strict-json',
    ], {
      timeoutMs: OC_TIMEOUT.CONFIG_SET,
      opName: 'config set models.providers.openai',
    })
    if (r.code !== 0) errors.push(`config set models.providers.openai failed: ${r.stderr}`)
  }

  if (apiKey !== undefined) {
    const authDir  = path.join(os.homedir(), `.openclaw-${PROFILE}`, 'agents', 'main', 'agent')
    const authFile = path.join(authDir, 'auth-profiles.json')
    try {
      fs.mkdirSync(authDir, { recursive: true })
      const authData = {
        version: 1,
        profiles: {
          'openai:default': { type: 'api_key', provider: 'openai', key: apiKey },
        },
        order: { openai: ['openai:default'] },
      }
      fs.writeFileSync(authFile, JSON.stringify(authData, null, 2), 'utf8')
    } catch (e) {
      errors.push(`writing auth-profiles.json failed: ${e.message}`)
    }
  }

  // Restart daemon to apply changes
  const restartResult = await restartGatewayRuntimeWithFallback()
  if (!restartResult.ok) {
    errors.push(restartResult.error ?? 'daemon restart failed')
  }

  if (errors.length > 0) {
    sendJson(res, 500, { ok: false, errors })
  } else {
    sendJson(res, 200, { ok: true })
  }
}

/** GET /api/config/channels */
function handleGetChannels(res) {
  try {
    const raw = fs.readFileSync(CONFIG_FILE, 'utf8')
    const config = JSON.parse(raw)
    sendJson(res, 200, config.channels ?? {})
  } catch (e) {
    sendJson(res, 404, { error: `Cannot read config: ${e.message}` })
  }
}

/** POST /api/config/channels */
async function handleUpdateChannel(res, body) {
  const errors = []

  // Handle enabled toggle — if explicitly set to false, just disable the channel
  if (body.enabled === false) {
    const key = `channels.${body.type}.enabled`
    const r = await runOc(['config', 'set', key, 'false', '--strict-json'], {
      timeoutMs: OC_TIMEOUT.CONFIG_SET,
      opName: `config set ${key}`,
    })
    if (r.code !== 0) errors.push(`config set ${key} failed: ${r.stderr}`)
  } else {
    const chErrors = await configureChannel(body)
    errors.push(...chErrors)
  }

  // Restart daemon to apply changes
  const restartResult = await restartGatewayRuntimeWithFallback()
  if (!restartResult.ok) {
    errors.push(restartResult.error ?? 'daemon restart failed')
  }

  if (errors.length > 0) {
    sendJson(res, 500, { ok: false, errors })
  } else {
    sendJson(res, 200, { ok: true })
  }
}

/** POST /api/daemon */
async function handleDaemon(res, body) {
  const { action } = body
  const allowed = ['start', 'stop', 'restart']
  if (!allowed.includes(action)) {
    sendJson(res, 400, { error: `Invalid action. Use one of: ${allowed.join(', ')}` })
    return
  }

  if (action === 'restart') {
    const result = await restartGatewayRuntimeWithFallback()
    if (!result.ok) {
      sendJson(res, 500, { ok: false, error: result.error })
      return
    }
    sendJson(res, 200, { ok: true, mode: result.mode ?? 'daemon', warning: result.warning ?? null })
    return
  }

  if (action === 'start') {
    const timeoutMs = OC_TIMEOUT.DAEMON_RESTART
    const r = await runOc(['daemon', 'start'], {
      timeoutMs,
      opName: 'daemon start',
    })
    if (r.code === 0) {
      sendJson(res, 200, { ok: true, mode: 'daemon', stdout: r.stdout })
      return
    }

    const detail = summarizeOcIssue(r)
    const canFallback = process.platform === 'win32' && (
      isSchtasksPermissionDenied(detail) || isDaemonNotInstalledIssue(detail)
    )
    if (!canFallback) {
      sendJson(res, 500, { ok: false, error: detail })
      return
    }

    try {
      const fallback = await startGatewayFallbackRuntime()
      sendJson(res, 200, {
        ok: true,
        mode: 'gateway-fallback',
        pid: fallback.pid,
        warning: `daemon start failed, using fallback runtime: ${detail}`,
      })
      return
    } catch (e) {
      sendJson(res, 500, { ok: false, error: `daemon start failed: ${detail}; fallback failed: ${e?.message ?? String(e)}` })
      return
    }
  }

  // action === 'stop'
  const r = await runOc(['daemon', 'stop'], {
    timeoutMs: OC_TIMEOUT.DAEMON_STOP,
    opName: 'daemon stop',
  })
  if (r.code === 0) {
    sendJson(res, 200, { ok: true, mode: 'daemon', stdout: r.stdout })
    return
  }

  const detail = summarizeOcIssue(r)
  const mayFallbackRuntime = process.platform === 'win32' && (
    isDaemonNotInstalledIssue(detail) || isSchtasksPermissionDenied(detail)
  )
  if (!mayFallbackRuntime) {
    sendJson(res, 500, { ok: false, error: detail })
    return
  }

  try {
    const cleanup = await cleanupOldDaemon({ port: GATEWAY_PORT, graceful: false, forceKill: true })
    if (cleanup.portBusy) {
      sendJson(res, 500, { ok: false, error: `gateway fallback stop failed: port ${GATEWAY_PORT} still busy`, log: cleanup.log })
      return
    }
    sendJson(res, 200, {
      ok: true,
      mode: 'gateway-fallback',
      warning: `daemon stop failed (${detail}); fallback runtime stopped by port cleanup`,
      log: cleanup.log,
    })
  } catch (e) {
    sendJson(res, 500, { ok: false, error: `daemon stop failed: ${detail}; fallback stop failed: ${e?.message ?? String(e)}` })
  }
}

/** POST /api/cleanup */
async function handleCleanup(res) {
  const errors = []
  const log = []

  try {
    const cleanupResult = await cleanupOldDaemon({ graceful: true, forceKill: true })
    log.push(...cleanupResult.log)
    if (cleanupResult.portBusy) {
      errors.push('Port 18889 is still occupied after cleanup')
    }
  } catch (e) {
    log.push(`cleanupOldDaemon error: ${e?.message ?? String(e)}`)
  }

  console.log('[cleanup:manual]', log.join(' | '))

  if (errors.length > 0) {
    sendJson(res, 500, { ok: false, errors, log })
  } else {
    sendJson(res, 200, { ok: true, log })
  }
}

/** POST /api/reset */
async function handleFactoryReset(res, body) {
  const cleanupSkills = body?.cleanupSkills !== false
  const errors = []
  const warnings = []
  const log = []
  const removed = []

  try {
    const uninstallResult = await runOc([
      'uninstall',
      '--service',
      '--state',
      '--workspace',
      '--yes',
      '--non-interactive',
    ], {
      timeoutMs: OC_TIMEOUT.UNINSTALL_FULL,
      opName: 'openclaw uninstall --service --state --workspace',
    })
    if (uninstallResult.code === 0) {
      log.push('openclaw uninstall --service --state --workspace: OK')
    } else {
      const detail = stripAnsi(uninstallResult.stderr).trim() || `exit code ${uninstallResult.code}`
      log.push(`openclaw uninstall --service --state --workspace: failed (${detail})`)
      errors.push('OpenClaw 全量卸载失败，请查看日志并重试')
    }
  } catch (e) {
    const detail = e?.message ?? String(e)
    log.push(`openclaw uninstall exception: ${detail}`)
    errors.push('OpenClaw 全量卸载执行异常')
  }

  // Clear stale/foreign daemon occupying fixed gateway port.
  try {
    const cleanupResult = await cleanupOldDaemon({ graceful: true, forceKill: true })
    log.push(...cleanupResult.log)
    if (cleanupResult.portBusy) {
      warnings.push('Port 18889 is still occupied after factory reset cleanup')
    }
  } catch (e) {
    log.push(`cleanupOldDaemon error: ${e?.message ?? String(e)}`)
  }

  // Ensure profile state/workspace are gone; remove manually as a fallback.
  const profileRemoval = removeDirIfExists(PROFILE_DIR)
  if (profileRemoval.error) {
    errors.push(`删除 profile 目录失败: ${toUserPath(PROFILE_DIR)} (${profileRemoval.error})`)
  } else if (profileRemoval.removed) {
    removed.push(toUserPath(PROFILE_DIR))
    log.push(`removed directory: ${toUserPath(PROFILE_DIR)}`)
  }

  const workspaceRemoval = removeDirIfExists(WORKSPACE_DIR)
  if (workspaceRemoval.error) {
    errors.push(`删除 workspace 目录失败: ${toUserPath(WORKSPACE_DIR)} (${workspaceRemoval.error})`)
  } else if (workspaceRemoval.removed) {
    removed.push(toUserPath(WORKSPACE_DIR))
    log.push(`removed directory: ${toUserPath(WORKSPACE_DIR)}`)
  }

  if (cleanupSkills) {
    for (const target of SKILL_TARGETS) {
      const skillRemoval = removeDirIfExists(target)
      if (skillRemoval.error) {
        errors.push(`删除 skills 目录失败: ${toUserPath(target)} (${skillRemoval.error})`)
      } else if (skillRemoval.removed) {
        removed.push(toUserPath(target))
        log.push(`removed directory: ${toUserPath(target)}`)
      } else {
        log.push(`skills directory not found: ${toUserPath(target)}`)
      }
    }
  }

  if (fs.existsSync(CONFIG_FILE)) {
    errors.push(`配置文件仍存在: ${toUserPath(CONFIG_FILE)}`)
  }
  if (await isPortBusy(18889)) {
    warnings.push('Port 18889 is still occupied after factory reset')
  }

  console.log('[cleanup:factory-reset]', log.join(' | '))
  if (warnings.length > 0) {
    console.log('[cleanup:factory-reset:warning]', warnings.join(' | '))
  }

  const resetComplete = !fs.existsSync(PROFILE_DIR) && !fs.existsSync(CONFIG_FILE)

  const payload = {
    ok: errors.length === 0,
    errors,
    warnings,
    log,
    removed,
    resetComplete,
    profile: PROFILE,
    cleanupSkills,
  }
  sendJson(res, errors.length > 0 ? 500 : 200, payload)
}

// ---------------------------------------------------------------------------
// Main request router
// ---------------------------------------------------------------------------

async function requestHandler(req, res) {
  const { method, url } = req

  // Handle CORS preflight
  if (method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin':  '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    })
    res.end()
    return
  }

  // Parse URL (ignore query string for routing)
  const parsedUrl = new URL(url, `http://localhost`)
  const pathname  = parsedUrl.pathname

  // --- Static file routes ---
  if (method === 'GET' && pathname === '/') {
    sendFile(res, path.join(PUBLIC_DIR, 'index.html'))
    return
  }

  if (method === 'GET' && pathname === '/dashboard') {
    sendFile(res, path.join(PUBLIC_DIR, 'dashboard.html'))
    return
  }

  if (method === 'GET' && pathname === '/setup') {
    sendFile(res, path.join(PUBLIC_DIR, 'index.html'))
    return
  }

  if (method === 'GET' && (pathname.endsWith('.css') || pathname.endsWith('.js') || pathname.endsWith('.mjs'))) {
    // Serve only from the public directory, prevent path traversal
    const safeName = path.basename(pathname)
    sendFile(res, path.join(PUBLIC_DIR, safeName))
    return
  }

  // --- API routes ---
  try {
    if (method === 'GET' && pathname === '/api/status') {
      await handleStatus(res)
      return
    }

    if (method === 'POST' && pathname === '/api/install') {
      const body = await readBody(req)
      await handleInstall(res, body)
      return
    }

    if (method === 'GET' && pathname === '/api/config') {
      handleGetConfig(res)
      return
    }

    if (method === 'POST' && pathname === '/api/config/api') {
      const body = await readBody(req)
      await handleUpdateApi(res, body)
      return
    }

    if (method === 'GET' && pathname === '/api/config/channels') {
      handleGetChannels(res)
      return
    }

    if (method === 'POST' && pathname === '/api/config/channels') {
      const body = await readBody(req)
      await handleUpdateChannel(res, body)
      return
    }

    if (method === 'POST' && pathname === '/api/daemon') {
      const body = await readBody(req)
      await handleDaemon(res, body)
      return
    }

    if (method === 'POST' && pathname === '/api/cleanup') {
      await handleCleanup(res)
      return
    }

    if (method === 'POST' && pathname === '/api/reset') {
      const body = await readBody(req)
      await handleFactoryReset(res, body)
      return
    }

    // 404 fallback
    sendJson(res, 404, { error: 'Not Found' })
  } catch (err) {
    console.error('[server] Unhandled error:', err)
    sendJson(res, 500, { error: err.message ?? 'Internal Server Error' })
  }
}

// ---------------------------------------------------------------------------
// Open browser helper
// ---------------------------------------------------------------------------

/**
 * Open a URL in the default browser.
 * @param {string} url
 */
function openBrowser(url) {
  const platform = process.platform
  let cmd, args

  if (platform === 'darwin') {
    cmd  = 'open'
    args = [url]
  } else if (platform === 'win32') {
    cmd  = 'cmd'
    args = ['/c', 'start', url]
  } else {
    // Linux / other: try xdg-open
    cmd  = 'xdg-open'
    args = [url]
  }

  const child = spawn(cmd, args, {
    detached: true,
    stdio: 'ignore',
    env: { ...process.env },
  })
  child.unref()
}

// ---------------------------------------------------------------------------
// Server startup
// ---------------------------------------------------------------------------

async function startServer() {
  const port = await findPort(DEFAULT_PORT)

  const server = http.createServer(requestHandler)

  server.listen(port, '127.0.0.1', () => {
    const url = `http://localhost:${port}`
    console.log(`\nClawBot UI server started`)
    console.log(`  Profile  : ${PROFILE}`)
    console.log(`  Node Bin : ${NODE_BIN}`)
    console.log(`  Config   : ${CONFIG_FILE}`)
    console.log(`  Listening: ${url}\n`)

    if (AUTO_OPEN_BROWSER) {
      openBrowser(url)
    } else {
      console.log('  Browser  : auto-open disabled by OPENSPARROW_AUTO_OPEN\n')
    }
  })

  server.on('error', (err) => {
    console.error('[server] Fatal error:', err)
    process.exit(1)
  })
}

// Start the server
startServer()
