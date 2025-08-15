# NDMGR User Guide

This comprehensive guide covers advanced usage patterns, configuration details, and real-world workflows for NDMGR (Nocturne Dotfile Manager).

## Table of Contents

- [Overview](#overview)
- [Installation and Setup](#installation-and-setup)
- [Module System Deep Dive](#module-system-deep-dive)
- [Configuration Management](#configuration-management)
- [Conflict Resolution](#conflict-resolution)
- [Git Integration](#git-integration)
- [Advanced Workflows](#advanced-workflows)
- [Force Modes and Automation](#force-modes-and-automation)
- [Pattern Matching](#pattern-matching)
- [Environment Variables](#environment-variables)
- [Troubleshooting](#troubleshooting)

## Overview

NDMGR is a symlink farm manager that helps organize and deploy dotfiles through symbolic links. This guide assumes familiarity with basic concepts covered in the README.md.

Key principles:
- **Non-destructive**: Always preserves existing files through backups
- **Predictable**: Same operation produces same results
- **Transparent**: Clear feedback about what actions are taken

## Installation and Setup

### Initial Configuration

```bash
# Initialize configuration file
ndmgr --init-config

# Verify configuration was created
ndmgr --config
```

This creates `~/.config/ndmgr/config.toml` with default settings.

### Environment Setup

NDMGR respects XDG Base Directory specification:

```bash
# Default configuration location
~/.config/ndmgr/config.toml

# Override with XDG_CONFIG_HOME
export XDG_CONFIG_HOME=/custom/config
# Now uses: /custom/config/ndmgr/config.toml

# Override with NDMGR_CONFIG_DIR  
export NDMGR_CONFIG_DIR=/tmp/ndmgr-test
# Now uses: /tmp/ndmgr-test/config.toml
```

## Module System Deep Dive

### Module Discovery

NDMGR scans directories to find modules using these rules:

1. **Scan depth**: Configurable depth limit (default: 3 levels)
2. **Module detection**: Directories containing files or `.ndmgr` configuration
3. **Ignore patterns**: Skip directories matching configured patterns

```bash
# View scan results before deployment
ndmgr --deploy --simulate --verbose

# Scan specific directory with custom depth
# (configured via config.toml linking.scan_depth)
ndmgr --deploy --dir ~/deep-configs
```

### Module Structure Examples

**Basic module structure:**
```
dotfiles/
└── vim/
    ├── .vimrc
    ├── .gvimrc
    └── .vim/
        ├── autoload/
        └── plugin/
```

**Configured module with custom target:**
```
dotfiles/
└── neovim/
    ├── .ndmgr                 # Configuration file
    ├── init.lua
    ├── lua/
    │   ├── plugins/
    │   └── config/
    └── after/
        └── plugin/
```

**Contents of `.ndmgr` file:**
```toml
description = "Neovim configuration"
target_dir = "$HOME/.config/nvim"
```

### Module Configuration Options

The `.ndmgr` file supports these options:

| Option | Type | Description | Example |
|--------|------|-------------|---------|
| `description` | String | Human-readable description | `"Vim configuration"` |
| `target_dir` | String | Custom target directory | `"$HOME/.config"` |

**Path expansion** in `target_dir`:
- `~` → User home directory
- `~/path` → Home directory + path  
- `$HOME` → Home directory (environment variable)
- `$HOME/path` → Home directory + path
- `/absolute/path` → Used as-is

## Configuration Management

### Configuration File Structure

```toml
[settings]
default_target = "$HOME"
verbose = false

[linking]
conflict_resolution = "fail"    # fail, skip, adopt, replace
tree_folding = "directory"      # directory, aggressive  
backup_conflicts = true
backup_suffix = "bkp"
scan_depth = 3
ignore_patterns = ["*.git", "node_modules"]

[git]
conflict_resolution = "ask"     # local, remote, ask
commit_message_template = "ndmgr: update {module} on {date}"
```

### Configuration Commands

```bash
# Show all configuration
ndmgr --config

# Show specific section
ndmgr --config linking

# Show specific key
ndmgr --config linking.conflict_resolution

# Show git configuration
ndmgr --config git
```

### Tree Folding Strategies

**Directory folding** (default):
- Links entire directories when possible
- Minimizes number of symlinks created
- Preserves directory structure

**Aggressive folding**:
- More aggressive about replacing existing directories
- May create deeper symlink structures
- Use with caution in shared environments

```bash
# Configure tree folding in config.toml
[linking]
tree_folding = "aggressive"
```

## Conflict Resolution

### Resolution Strategies

NDMGR provides four strategies for handling conflicts when target files already exist:

1. **fail** (default): Stop operation and show error when conflicts are detected
2. **skip**: Skip conflicting files and continue with non-conflicting files (useful in --deploy mode with multiple modules)  
3. **adopt**: Move existing files into the source module, then create symlinks
4. **replace**: Delete existing files in target and create symlinks (respects backup settings)

### Strategy Details

**fail**: Immediately stops when any conflict is detected. Shows clear error message.
```bash
ndmgr vim
# Output: "Conflict detected: ~/.vimrc already exists"
# Operation stops, no changes made
```

**skip**: Continues processing other files when conflicts are found. Useful for batch operations.
```bash
# In --deploy mode with multiple modules
ndmgr --deploy
# Skips conflicting files, continues with remaining modules
# Reports: "Warning: Skipped 3 conflicting files"
```

**adopt**: Integrates existing files into your dotfiles repository.
```bash
# Before: ~/.vimrc exists in target
# After adoption:
#   dotfiles/vim/.vimrc     (moved from target)  
#   ~/.vimrc -> dotfiles/vim/.vimrc  (new symlink)
```

**replace**: Removes existing files and creates symlinks.
```bash
# Before: ~/.vimrc exists in target  
# After replacement:
#   ~/.vimrc -> dotfiles/vim/.vimrc  (new symlink)
#   ~/.vimrc.bkp  (backup, if backup_conflicts = true)
```

### Configuration

Set the default strategy in your configuration:
```bash
# Edit ~/.config/ndmgr/config.toml
[linking]
conflict_resolution = "replace"  # or "fail", "skip", "adopt"
backup_conflicts = true          # Create backups before replace/adopt
backup_suffix = "bkp"           # Backup file suffix
```

### Backup Behavior

When `backup_conflicts = true`:
- Existing files are backed up before replacement
- Backup suffix is configurable (default: "bkp")
- Backups are created as: `original_file.suffix`

```bash
# Before: ~/.vimrc exists
# After linking: 
#   ~/.vimrc -> dotfiles/vim/.vimrc  (symlink)
#   ~/.vimrc.bkp                      (backup)
```

## Git Integration

### Repository Configuration

```bash
# Add repository with all options
ndmgr --add-repo \
    --name work-config \
    --path ~/work/dotfiles \
    --remote https://github.com/company/config.git \
    --branch develop
```

### Repository Operations

**Single repository operations:**
```bash
# Pull specific repository
ndmgr --pull --repository work-config

# Push specific repository  
ndmgr --push --repository work-config
```

**Multi-repository operations:**
```bash
# Pull all configured repositories
ndmgr --pull-all

# Push all configured repositories
ndmgr --push-all

# Full sync: pull all + deploy all
ndmgr --sync
```

### Repository Information

```bash
# List all repositories
ndmgr --repos

# Show detailed system status
ndmgr --status

# Show module information
ndmgr --info
ndmgr --info --module vim
```

### Commit Message Templates

Templates support these variables:
- `{module}`: Module name being updated
- `{date}`: Current date (YYYY-MM-DD format)

**Template examples:**
```toml
# Concise format
commit_message_template = "Update {module} - {date}"
# Result: "Update dotfiles - 2025-08-15"

# Professional format  
commit_message_template = "feat({module}): automated sync {date}"
# Result: "feat(dotfiles): automated sync 2025-08-15"

# Simple format
commit_message_template = "{date}: Updated {module} configuration"  
# Result: "2025-08-15: Updated vim configuration"
```

## Advanced Workflows

### Development Environment Setup

```bash
# 1. Initialize configuration
ndmgr --init-config

# 2. Add multiple repositories
ndmgr --add-repo --name personal --path ~/dotfiles --remote git@github.com:user/dotfiles.git
ndmgr --add-repo --name work --path ~/work-config --remote https://work.com/config.git

# 3. Deploy personal configs to home
ndmgr --deploy --dir ~/dotfiles --target ~

# 4. Deploy work configs to separate location  
ndmgr --deploy --dir ~/work-config --target ~/work-env
```

### Multi-Environment Deployment

```bash
# Test environment deployment
ndmgr --deploy --dir ~/dotfiles --target ~/test-env --simulate

# Production deployment with backup
ndmgr --deploy --dir ~/dotfiles --target ~ --force yes

# Work environment with specific modules
ndmgr --dir ~/work-config tmux vim git
```

### Maintenance Workflows

```bash
# Daily sync routine
ndmgr --sync

# Weekly cleanup check
ndmgr --status
ndmgr --info

# Module-specific updates
ndmgr --relink vim
ndmgr --pull --repository dotfiles
ndmgr --push --repository dotfiles
```

## Force Modes and Automation

### Force Mode Options

1. **`--force`** (default): Override conflicts automatically
2. **`--force yes`**: Answer "yes" to all interactive prompts
3. **`--force no`**: Answer "no" to all interactive prompts

### Interactive Scenarios

**Backup conflicts:**
```bash
# Scenario: backup file already exists
# Interactive: "Replace existing backup? [y/N]"
# --force yes: "(forced: yes)" - replaces backup
# --force no: "(forced: no)" - preserves backup
# --force: uses default behavior for non-prompt conflicts
```

**File adoption:**
```bash
# Scenario: using adopt strategy with existing files
# Interactive: "Adopt existing directory? [y/N]"
# --force yes: proceeds with adoption
# --force no: cancels adoption, preserves existing files
```

### Automation Examples

```bash
# Fully automated deployment
ndmgr --deploy --force yes --verbose

# Safe automation (never overwrites)
ndmgr --deploy --force no

# Default automation (handles basic conflicts)
ndmgr --deploy --force
```

## Pattern Matching

### Ignore Patterns

**Single pattern:**
```bash
ndmgr --ignore "*.log" vim
```

**Multiple patterns:**
```bash
ndmgr --ignore "*.log" --ignore "*.tmp" --ignore "node_modules" web-config
```

**Common ignore patterns:**
```bash
# Development files
ndmgr --ignore "node_modules" --ignore ".git" --ignore "*.log"

# Temporary files  
ndmgr --ignore "*.tmp" --ignore "*.swp" --ignore ".DS_Store"

# Build artifacts
ndmgr --ignore "target/" --ignore "build/" --ignore "dist/"
```

### Pattern Syntax

NDMGR supports basic glob patterns:
- `*.ext`: Match files ending with extension
- `prefix*`: Match files starting with prefix  
- `*substring*`: Match files containing substring
- `exact-name`: Match exact filename

## Environment Variables

### Configuration Override

```bash
# Use custom configuration directory
export NDMGR_CONFIG_DIR=/tmp/test-config
ndmgr --init-config

# Use XDG_CONFIG_HOME for testing environment
export NDMGR_CONFIG_DIR=$XDG_CONFIG_HOME/ndmgr_testing
ndmgr --init-config
```

### Path Expansion Variables

```bash
# These are equivalent in .ndmgr files:
target_dir = "~/.config"
target_dir = "$HOME/.config"

# Absolute paths work as-is:
target_dir = "/opt/application/config"
```

## Troubleshooting

### Diagnostic Commands

```bash
# Show what would happen without doing it
ndmgr --simulate --verbose --deploy

# Check module structure
ls -la dotfiles/module-name/

# Verify configuration
ndmgr --config

# Check repository status
ndmgr --repos
ndmgr --status
```

### Common Issues and Solutions

**"Module not found"**
```bash
# Check directory structure
ls -la dotfiles/

# Verify scan depth isn't too shallow
ndmgr --config linking.scan_depth

# Use verbose mode to see scan results
ndmgr --deploy --simulate --verbose
```

**"Git operation failed"**  
```bash
# Verify git is available
git --version

# Check repository configuration
ndmgr --repos

# Verify repository paths exist
ls -la ~/dotfiles/
```

**"Permission denied"**
```bash
# Check target directory permissions
ls -ld ~/

# Verify source directory access
ls -la dotfiles/

# Use verbose mode for details
ndmgr --verbose vim
```

**"Conflicts detected"**
```bash
# See what conflicts exist
ndmgr --simulate --verbose module-name

# Configure automatic resolution
# Edit ~/.config/ndmgr/config.toml:
[linking]
conflict_resolution = "adopt"  # or "skip" or "replace"

# Or use force mode
ndmgr --force module-name
```

### Debug Output

**Verbose output levels:**
```bash
# Basic verbose
ndmgr --verbose command

# Simulation with verbose
ndmgr --simulate --verbose command

# Configuration debugging
ndmgr --config
```

**Log analysis:**
- Verbose output shows each step taken
- Simulation shows planned actions without executing
- Configuration display helps identify setting issues

### Configuration Backup System

NDMGR automatically creates backups when modifying configuration:

```bash
# First modification creates backup
ls ~/.config/ndmgr/
# config.toml
# config.toml.bkp.20250815-1

# Subsequent modifications create numbered backups
# config.toml.bkp.20250815-2
# config.toml.bkp.20250815-3
```

Backups include timestamp and sequence number to prevent data loss during configuration changes.

## Support

For additional help:
- Check configuration: `ndmgr --config`
- Use simulation mode: `ndmgr --simulate --verbose`
- Review repository status: `ndmgr --status`
- Examine module structure with standard tools: `ls -la`, `tree`