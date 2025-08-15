# NDMGR - Nocturne Dotfile Manager

NDMGR is a modern symlink farm manager written in Zig, designed for efficient dotfile and configuration management. It combines the simplicity of traditional stow-like tools with advanced features including git integration, intelligent conflict resolution, and automated module discovery.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Core Concepts](#core-concepts)
- [Basic Usage](#basic-usage)
- [Module System](#module-system)
- [Git Integration](#git-integration)
- [Configuration](#configuration)
- [Command Reference](#command-reference)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

NDMGR manages your dotfiles by creating symbolic links from source directories (modules) to target locations. Unlike simple directory mirroring, NDMGR provides:

- **Intelligent Conflict Resolution**: Safe handling of existing files with multiple resolution strategies
- **Git Integration**: Full repository management with automated pull/push workflows
- **Module Discovery**: Automatic detection and deployment of configured modules
- **Tree Folding**: Efficient directory linking that minimizes symlink creation
- **Zero Dependencies**: Pure Zig implementation with clean text output

## Installation

### Building from Source

```bash
git clone https://github.com/user/ndm.git
cd ndm
zig build
```

The binary will be available at `zig-out/bin/ndmgr`.

## Core Concepts

### What is a Module?

A **module** is a directory containing configuration files that should be linked to a target location. Modules come in two types:

1. **Basic Module**: A simple directory with files to be linked
2. **Configured Module**: A directory with an `.ndmgr` configuration file specifying linking behavior

### Module Structure

```
dotfiles/
├── vim/                    # Basic module
│   ├── .vimrc
│   └── .vim/
│       └── colors/
└── nvim/                   # Configured module  
    ├── .ndmgr              # Configuration file
    ├── init.vim
    └── lua/
        └── config.lua
```

### How Modules are Linked

When NDMGR processes a module:

1. **Discovery**: Scans the source directory for modules
2. **Analysis**: Checks for existing files in target locations
3. **Conflict Resolution**: Handles conflicts based on configuration
4. **Linking**: Creates symbolic links from target to source

```
# Before linking
~/.vimrc           # Existing file
dotfiles/vim/.vimrc  # Source file

# After linking  
~/.vimrc -> dotfiles/vim/.vimrc  # Symbolic link created
~/.vimrc.bkp       # Original backed up (if configured)
```

## Basic Usage

### Link Operations

```bash
# Link a single module
ndmgr vim

# Link multiple modules
ndmgr vim git tmux

# Unlink a module
ndmgr --unlink vim

# Relink a module (unlink then link)
ndmgr --relink vim
```

### Directory Control

```bash
# Specify source directory
ndmgr --dir ~/dotfiles vim

# Specify target directory
ndmgr --target ~/test-env vim

# Both source and target
ndmgr --dir ~/dotfiles --target ~ vim
```

### Output Control

```bash
# Verbose output
ndmgr --verbose vim

# Dry run (preview only)
ndmgr --simulate vim

# Quiet operation (default)
ndmgr vim
```

### Conflict Handling

```bash
# Interactive conflict resolution (default)
ndmgr vim

# Force operation with prompts
ndmgr --force yes vim    # Answer yes to all prompts
ndmgr --force no vim     # Answer no to all prompts

# Force operation without prompts
ndmgr --force vim        # Override conflicts automatically
```

### Pattern Matching

```bash
# Ignore specific file patterns
ndmgr --ignore "*.log" --ignore "*.tmp" vim

# Multiple ignore patterns
ndmgr -i "*.log" -i "node_modules" -i ".DS_Store" vim
```

## Module System

### Module Discovery and Deployment

```bash
# Deploy all discovered modules
ndmgr --deploy

# Deploy from specific directory
ndmgr --deploy --dir ~/dotfiles

# Deploy to custom target
ndmgr --deploy --target ~/test-env
```

### Module Configuration (.ndmgr files)

Create an `.ndmgr` file in your module to control its behavior:

```toml
# dotfiles/nvim/.ndmgr
description = "Neovim configuration"
target_dir = "$HOME/.config"
```

**Configuration Options:**
- `description`: Human-readable module description
- `target_dir`: Custom target directory (supports `~`, `~/path`, `$HOME`, `$HOME/path`)

## Git Integration

### Repository Management

```bash
# Initialize NDMGR configuration
ndmgr --init-config

# Add a git repository
ndmgr --add-repo --name dotfiles --path ~/dotfiles --remote git@github.com:user/dotfiles.git

# Add with custom branch
ndmgr --add-repo --name work --path ~/work-config --remote https://github.com/company/config.git --branch main
```

### Repository Operations

```bash
# Pull changes from a repository
ndmgr --pull --repository dotfiles

# Push changes to a repository  
ndmgr --push --repository dotfiles

# Pull all configured repositories
ndmgr --pull-all

# Push all configured repositories
ndmgr --push-all

# Sync: pull all + deploy all
ndmgr --sync
```

### Git Repository Initialization

```bash
# Initialize git repository in current directory
ndmgr --init-repo
```

## Configuration

### Configuration File

NDMGR uses a TOML configuration file located at `~/.config/ndmgr/config.toml`:

```toml
[settings]
default_target = "$HOME"
verbose = false

[linking]
conflict_resolution = "fail"    # "fail", "skip", "adopt", "replace"
tree_folding = "directory"      # "directory", "aggressive"
backup_conflicts = true
backup_suffix = "bkp"
scan_depth = 3
ignore_patterns = ["*.git", "node_modules"]

[git]
conflict_resolution = "ask"     # "local", "remote", "ask"
commit_message_template = "ndmgr: update {module} on {date}"
```

### Configuration Management

```bash
# Show current configuration
ndmgr --config

# Show specific configuration key
ndmgr --config linking.conflict_resolution

# Initialize default configuration
ndmgr --init-config
```

### Environment Variables

- `NDMGR_CONFIG_DIR`: Override default configuration directory
- `XDG_CONFIG_HOME`: Respects XDG Base Directory specification

## Command Reference

### Link Operations
- `--link` (default): Link specified modules
- `--unlink`: Remove links for specified modules  
- `--relink`: Unlink then relink specified modules
- `--ignore PATTERN`: Ignore files matching pattern

### Deployment
- `--deploy`: Deploy all discovered modules

### Git Operations
- `--pull [--repository NAME]`: Pull repository changes
- `--push [--repository NAME]`: Push repository changes
- `--pull-all`: Pull all configured repositories
- `--push-all`: Push all configured repositories  
- `--sync`: Pull all repositories then deploy
- `--init-repo`: Initialize git repository

### Configuration
- `--config [KEY]`: Show configuration
- `--init-config`: Initialize configuration file
- `--add-repo`: Add repository (requires --name, --path, --remote)
- `--name NAME`: Repository name (for --add-repo)
- `--path PATH`: Repository path (for --add-repo)
- `--remote URL`: Repository remote URL (for --add-repo)
- `--branch BRANCH`: Repository branch (for --add-repo)

### Information
- `--status`: Show system and repository status
- `--repos`: List configured repositories
- `--info [--module MODULE]`: Show module information

### Basic Options
- `--dir DIR`: Source directory (default: current)
- `--target DIR`: Target directory (default: $HOME)
- `--force [yes|no]`: Force operation mode
- `--verbose`: Verbose output
- `--simulate`: Dry run mode
- `--help`: Show help message
- `--version`: Show version information

## Examples

### Initial Setup

```bash
# 1. Initialize configuration
ndmgr --init-config

# 2. Add your dotfiles repository
ndmgr --add-repo --name dotfiles --path ~/dotfiles --remote git@github.com:user/dotfiles.git

# 3. Deploy all modules
ndmgr --sync
```

### Daily Workflow

```bash
# Sync all repositories and deploy changes
ndmgr --sync

# Check repository status
ndmgr --status

# Deploy specific modules only
ndmgr vim tmux

# View system information
ndmgr --repos
ndmgr --info
```

### Advanced Usage

```bash
# Deploy with conflict resolution
ndmgr --deploy --force yes

# Deploy specific directory with custom target
ndmgr --deploy --dir ~/work-config --target ~/work-env

# Link with ignore patterns
ndmgr --ignore "*.log" --ignore "node_modules" --link web-config

# Verbose dry run
ndmgr --simulate --verbose --deploy
```

## Troubleshooting

### Common Issues

**Module not linking:**
```bash
# Check module structure
ls -la dotfiles/module-name/

# Use verbose mode for details
ndmgr --verbose --simulate module-name

# Check configuration
ndmgr --config
```

**Git operations failing:**
```bash
# Verify git availability
git --version

# Check repository configuration
ndmgr --repos

# Check repository status
ndmgr --status
```

**Conflict resolution issues:**
```bash
# See what conflicts exist
ndmgr --simulate --verbose module-name

# Use force mode to override
ndmgr --force module-name

# Or configure conflict resolution
ndmgr --config linking.conflict_resolution
```

### Debug Output

```bash
# Enable verbose output
ndmgr --verbose command

# Dry run to see planned actions
ndmgr --simulate command

# Show configuration
ndmgr --config
```

## License

Released under the MIT License.