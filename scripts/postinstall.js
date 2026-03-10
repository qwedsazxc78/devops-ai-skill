#!/usr/bin/env node
/**
 * Postinstall hook for npm/npx distribution.
 * Copies agents, prompts, and entry files to the project root.
 * Safe: never overwrites existing files.
 */

const fs = require('fs');
const path = require('path');

// Package root (where this package is installed)
const PKG_ROOT = path.join(__dirname, '..');

// Project root (the directory that ran npm install)
// When installed as dependency: node_modules/devops-ai-skill/scripts/ → go up to project
// When running directly: use current working directory
const PROJECT_ROOT = process.env.INIT_CWD || process.cwd();

// Skip if running inside the package itself (development mode)
if (path.resolve(PROJECT_ROOT) === path.resolve(PKG_ROOT)) {
  process.exit(0);
}

const installed = [];
const skipped = [];

/**
 * Recursively copy a directory, skipping existing files
 */
function copyDirSafe(src, dest, prefix) {
  if (!fs.existsSync(src)) return;
  fs.mkdirSync(dest, { recursive: true });

  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    const relPath = prefix ? `${prefix}/${entry.name}` : entry.name;

    if (entry.isDirectory()) {
      copyDirSafe(srcPath, destPath, relPath);
    } else {
      if (fs.existsSync(destPath)) {
        skipped.push(relPath);
      } else {
        fs.copyFileSync(srcPath, destPath);
        installed.push(relPath);
      }
    }
  }
}

/**
 * Copy a single file if it doesn't exist at destination
 */
function copyFileSafe(src, dest, label) {
  if (!fs.existsSync(src)) return;
  if (fs.existsSync(dest)) {
    skipped.push(label);
  } else {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(src, dest);
    installed.push(label);
  }
}

// --- Copy agents ---
copyDirSafe(
  path.join(PKG_ROOT, '.claude', 'agents'),
  path.join(PROJECT_ROOT, '.claude', 'agents'),
  '.claude/agents'
);
copyDirSafe(
  path.join(PKG_ROOT, '.gemini', 'agents'),
  path.join(PROJECT_ROOT, '.gemini', 'agents'),
  '.gemini/agents'
);

// --- Copy prompts ---
copyDirSafe(
  path.join(PKG_ROOT, 'prompts'),
  path.join(PROJECT_ROOT, 'prompts'),
  'prompts'
);

// --- Copy platform entry files (don't overwrite) ---
const entryFiles = ['CLAUDE.md', 'AGENTS.md', 'GEMINI.md'];
for (const file of entryFiles) {
  copyFileSafe(
    path.join(PKG_ROOT, file),
    path.join(PROJECT_ROOT, file),
    file
  );
}

// --- Copy platform configs ---
copyDirSafe(
  path.join(PKG_ROOT, '.claude-plugin'),
  path.join(PROJECT_ROOT, '.claude-plugin'),
  '.claude-plugin'
);
copyDirSafe(
  path.join(PKG_ROOT, '.gemini', 'extensions'),
  path.join(PROJECT_ROOT, '.gemini', 'extensions'),
  '.gemini/extensions'
);
copyFileSafe(
  path.join(PKG_ROOT, '.codex', 'config.toml'),
  path.join(PROJECT_ROOT, '.codex', 'config.toml'),
  '.codex/config.toml'
);

// --- Copy docs ---
copyDirSafe(
  path.join(PKG_ROOT, 'docs'),
  path.join(PROJECT_ROOT, 'docs'),
  'docs'
);

// --- Print summary ---
console.log('\n⚡ DevOps AI Skill Pack — postinstall');
console.log('────────────────────────────────────');

if (installed.length > 0) {
  console.log(`\n✓ Installed ${installed.length} files:`);
  // Group by directory for cleaner output
  const groups = {};
  for (const f of installed) {
    const dir = path.dirname(f);
    if (!groups[dir]) groups[dir] = [];
    groups[dir].push(path.basename(f));
  }
  for (const [dir, files] of Object.entries(groups)) {
    if (dir === '.') {
      console.log(`  ${files.join(', ')}`);
    } else {
      console.log(`  ${dir}/  (${files.length} files)`);
    }
  }
}

if (skipped.length > 0) {
  console.log(`\n⊘ Skipped ${skipped.length} existing files (not overwritten)`);
}

console.log('\n🤖 Agents: Horus (IaC) + Zeus (GitOps)');
console.log('📋 Prompts: 14 pipeline workflows');
console.log('🔧 Skills: 8 shared skills in skills/');
console.log('\nRun platform setup:');
console.log('  pnpm setup:claude   # Claude Code');
console.log('  pnpm setup:codex    # OpenAI Codex CLI');
console.log('  pnpm setup:gemini   # Google Gemini CLI');
console.log('');
