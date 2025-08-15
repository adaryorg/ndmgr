// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

/// Central constants file for NDMGR
/// Contains all hardcoded strings and values used throughout the application

// =============================================================================
// File Extensions and Names
// =============================================================================

/// Module configuration file extension
pub const MODULE_CONFIG_FILE = ".ndmgr";

/// Configuration file name
pub const CONFIG_FILE_NAME = "config.toml";

/// Standard configuration directory name
pub const CONFIG_DIR_NAME = ".config";

/// Application configuration subdirectory
pub const APP_CONFIG_DIR = "ndmgr";

// =============================================================================
// Environment Variables
// =============================================================================

/// Home directory environment variable
pub const ENV_HOME = "HOME";

/// XDG Base Directory specification config home
pub const ENV_XDG_CONFIG_HOME = "XDG_CONFIG_HOME";

/// Custom configuration directory environment variable
pub const ENV_NDMGR_CONFIG_DIR = "NDMGR_CONFIG_DIR";

// =============================================================================
// Default Configuration Values
// =============================================================================

/// Default Git branch name
pub const DEFAULT_BRANCH = "main";

/// Default backup file suffix
pub const DEFAULT_BACKUP_SUFFIX = "bkp";

/// Default home directory target
pub const DEFAULT_TARGET = "$HOME";

/// Default commit message template
pub const DEFAULT_COMMIT_MESSAGE_TEMPLATE = "ndmgr: update {module} on {date}";

/// Default scan depth for module discovery
pub const DEFAULT_SCAN_DEPTH: u32 = 3;

/// Default verbose setting
pub const DEFAULT_VERBOSE = false;

/// Default backup conflicts setting
pub const DEFAULT_BACKUP_CONFLICTS = true;

/// Default auto commit setting
pub const DEFAULT_AUTO_COMMIT = true;

// =============================================================================
// Configuration Keys
// =============================================================================

/// Module configuration key for target directory
pub const CONFIG_KEY_TARGET_DIR = "target_dir";

/// Module configuration key for ignore flag
pub const CONFIG_KEY_IGNORE = "ignore";

/// Boolean string values
pub const BOOL_TRUE = "true";

// =============================================================================
// Default Ignore Patterns
// =============================================================================

/// Default ignore patterns for module scanning and linking
pub const DEFAULT_IGNORE_PATTERNS = [_][]const u8{
    "*.git",
    "node_modules",
};

// =============================================================================
// File Suffixes and Extensions
// =============================================================================

// =============================================================================
// Path Separators and Special Paths
// =============================================================================

/// Tilde prefix for home directory
pub const TILDE_PREFIX = "~/";