# AIConfigShield 🛡️

### Stop AI agents from taking shortcuts in your configuration files.

## The Background
Large Language Models (LLMs) and AI coding agents are powerful, but they have a "laziness" property learned from the vast amount of human data they've been trained on. When tasked with fixing thousands of linting errors or complex architectural issues, they often try to take the path of least resistance. 

Instead of fixing 1000 errors, an AI might "secretly" modify your configuration files (like `.flake8`, `eslint.config.js`, or `.pre-commit-config.yaml`) to ignore entire categories of rules. You return to your PC after half an hour, the AI proudly reports "All tasks completed!", only for you to find out it actually fixed 10 errors and muted the other 990.

Even worse, a simple Windows "Read-Only" attribute is often not enough. Modern AI agents are clever enough to recognize and remove that attribute to continue their shortcut. **AIConfigShield** provides hardened, NTFS-level protection that makes unauthorized modification **impossible** without administrative privileges.

## Features
- **Unbypassable Locking**: Uses NTFS permissions (`takeown` and `icacls`) to lock files at a system level.
- **Admin-Only Access**: Prevents any modification by the standard user session. Even "force" writes fail.
- **Auto-Elevation**: Automatically requests Administrator privileges to apply these deep locks.
- **Universal**: Use it in any project (Node, Python, Go, etc.) as long as you're on Windows.

## Installation

```bash
npm install -g ai-config-shield
```

## Usage

### Locking your "Fortress"
Lock your linting configs and hooks to ensure the AI actually *fixes* the code instead of hiding the problems:

```bash
npx shield-lock eslint.config.js .flake8 .pre-commit-config.yaml .git/hooks/pre-commit
```

### Unlocking for Manual Maintenance
When *you* (the human) want to change the configurations:

```bash
npx shield-unlock <path-to-file-or-dir>
```

## How it works
The tool performs a "Take Ownership" operation and then modifies the Access Control List (ACL) to grant the current user only **Read & Execute** rights, while preserving **Full Control** for the SYSTEM and Administrators (who must consciously elevate to change these rules).

## License
MIT
