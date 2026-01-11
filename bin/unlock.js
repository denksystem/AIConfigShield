#!/usr/bin/env node
const { spawn } = require('child_process');
const path = require('path');

const scriptPath = path.join(__dirname, 'unlock.ps1');
const args = [
  '-NoProfile',
  '-ExecutionPolicy', 'Bypass',
  '-File', scriptPath,
  ...process.argv.slice(2)
];

const child = spawn('powershell.exe', args, { stdio: 'inherit' });

child.on('exit', (code) => {
  process.exit(code);
});
