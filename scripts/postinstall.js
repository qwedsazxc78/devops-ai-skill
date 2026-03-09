#!/usr/bin/env node
/**
 * Postinstall hook for npm/npx distribution.
 * Auto-detects installed AI agents and copies skills to appropriate directories.
 */

const fs = require('fs');
const path = require('path');

const SKILLS_DIR = path.join(__dirname, '..', 'skills');
const detected = [];

// Detect Claude Code
if (fs.existsSync(path.join(process.env.HOME || '', '.claude'))) {
  detected.push('Claude Code');
}

// Detect Codex CLI
if (fs.existsSync(path.join(process.env.HOME || '', '.codex'))) {
  detected.push('Codex CLI');
}

// Detect Gemini CLI
if (fs.existsSync(path.join(process.env.HOME || '', '.gemini'))) {
  detected.push('Gemini CLI');
}

if (detected.length > 0) {
  console.log(`\nDevOps AI Skill Pack installed!`);
  console.log(`Detected agents: ${detected.join(', ')}`);
  console.log(`\nRun setup for your platform:`);
  if (detected.includes('Claude Code')) {
    console.log(`  npm run setup:claude`);
  }
  if (detected.includes('Codex CLI')) {
    console.log(`  npm run setup:codex`);
  }
  if (detected.includes('Gemini CLI')) {
    console.log(`  npm run setup:gemini`);
  }
} else {
  console.log(`\nDevOps AI Skill Pack installed!`);
  console.log(`No AI agents detected. Run setup manually:`);
  console.log(`  npm run setup:claude   # For Claude Code`);
  console.log(`  npm run setup:codex    # For Codex CLI`);
  console.log(`  npm run setup:gemini   # For Gemini CLI`);
}
console.log('');
