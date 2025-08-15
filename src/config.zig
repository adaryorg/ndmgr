// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const toml = @import("toml");
const fs = std.fs;
const constants = @import("constants.zig");
const path_utils = @import("path_utils.zig");

pub const Repository = struct {
    name: []const u8,
    path: []const u8,
    remote: []const u8,
    branch: []const u8 = constants.DEFAULT_BRANCH,
    auto_commit: bool = constants.DEFAULT_AUTO_COMMIT,
};

// TOML-compatible struct for the entire configuration file
pub const TomlConfig = struct {
    git: ?GitConfig = null,
    settings: ?Settings = null,
    linking: ?LinkingConfig = null,
    repository: ?[]Repository = null,
};

pub const GitConfig = struct {
    conflict_resolution: ConflictResolution = .ask,
    commit_message_template: []const u8 = constants.DEFAULT_COMMIT_MESSAGE_TEMPLATE,
};

pub const Settings = struct {
    default_target: []const u8 = constants.DEFAULT_TARGET,
    verbose: bool = constants.DEFAULT_VERBOSE,
};


pub const LinkingConfig = struct {
    conflict_resolution: LinkingConflictResolution = .fail,
    tree_folding: TreeFoldingStrategy = .directory,
    backup_conflicts: bool = constants.DEFAULT_BACKUP_CONFLICTS,
    backup_suffix: []const u8 = constants.DEFAULT_BACKUP_SUFFIX,
    
    scan_depth: u32 = constants.DEFAULT_SCAN_DEPTH,
    ignore_patterns: []const []const u8 = &constants.DEFAULT_IGNORE_PATTERNS,
};

pub const LinkingConflictResolution = enum {
    fail,
    skip,
    adopt,
    replace,
};

pub const TreeFoldingStrategy = enum {
    directory,
    aggressive,
};

pub const ConflictResolution = enum {
    local,
    remote,
    ask,
};

pub const Config = struct {
    git: GitConfig = .{},
    settings: Settings = .{},
    linking: LinkingConfig = .{},
    
    pub fn init() Config {
        return Config{
            .git = .{},
            .settings = .{},
            .linking = .{},
        };
    }
    
    pub fn deinit(self: *Config) void {
        _ = self;
    }
};

pub const ConfigWithRepositories = struct {
    config: Config,
    repositories: std.StringHashMap(Repository),
    allocator: std.mem.Allocator,
    // Keep the TOML parser and result alive to avoid memory issues
    parser: ?*toml.Parser(TomlConfig) = null,
    parsed: ?toml.Parsed(TomlConfig) = null,
    
    pub fn init(allocator: std.mem.Allocator) ConfigWithRepositories {
        return ConfigWithRepositories{
            .config = Config.init(),
            .repositories = std.StringHashMap(Repository).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ConfigWithRepositories) void {
        self.config.deinit();
        self.repositories.deinit();
        
        // Clean up TOML parser and result
        if (self.parsed) |*parsed| {
            parsed.deinit();
        }
        if (self.parser) |parser| {
            parser.deinit();
            self.allocator.destroy(parser);
        }
    }
};

pub const ConfigManager = struct {
    allocator: std.mem.Allocator,
    config_dir: []const u8,
    config_file: []const u8,
    
    pub fn init(allocator: std.mem.Allocator) !ConfigManager {
        const config_dir = if (std.process.getEnvVarOwned(allocator, constants.ENV_NDMGR_CONFIG_DIR)) |custom_dir|
            custom_dir
        else |_|
            try path_utils.PathUtils.getDefaultConfigDir(allocator);
        
        const config_file = try fs.path.join(allocator, &.{ config_dir, constants.CONFIG_FILE_NAME });
        
        return ConfigManager{
            .allocator = allocator,
            .config_dir = config_dir,
            .config_file = config_file,
        };
    }
    
    pub fn deinit(self: ConfigManager) void {
        self.allocator.free(self.config_dir);
        self.allocator.free(self.config_file);
    }
    
    pub fn ensureConfigDir(self: ConfigManager) !void {
        fs.cwd().makePath(self.config_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
    
    pub fn loadConfig(self: ConfigManager) !ConfigWithRepositories {
        var config = ConfigWithRepositories.init(self.allocator);
        
        // Check if config file exists
        fs.cwd().access(self.config_file, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                try self.createDefaultConfig();
                return config;
            },
            else => return err,
        };
        
        // Create parser on heap to keep it alive
        config.parser = try self.allocator.create(toml.Parser(TomlConfig));
        config.parser.?.* = toml.Parser(TomlConfig).init(self.allocator);
        
        // Parse the TOML file
        config.parsed = config.parser.?.parseFile(self.config_file) catch |err| switch (err) {
            else => {
                std.debug.print("Error parsing config file: {}\n", .{err});
                return config; // Return default config on parse error
            },
        };
        
        const toml_config = config.parsed.?.value;
        
        // Extract configuration sections
        if (toml_config.git) |git| {
            config.config.git = git;
        }
        if (toml_config.settings) |settings| {
            config.config.settings = settings;
        }
        
        // Handle linking config
        if (toml_config.linking) |linking| {
            config.config.linking = linking;
        }
        
        // Process repositories
        if (toml_config.repository) |repos| {
            for (repos) |repo| {
                try config.repositories.put(repo.name, repo);
            }
        }
        
        return config;
    }
    
    
    pub fn createDefaultConfig(self: ConfigManager) !void {
        try self.ensureConfigDir();
        
        const default_config =
            \\[settings]
            \\default_target = "$HOME"
            \\verbose = false
            \\
            \\[linking]
            \\conflict_resolution = "fail"
            \\tree_folding = "directory"
            \\backup_conflicts = true
            \\backup_suffix = "bkp"
            \\scan_depth = 3
            \\ignore_patterns = ["*.git", "node_modules"]
            \\
            \\[git]
            \\conflict_resolution = "ask"
            \\commit_message_template = "ndmgr: update {module} on {date}"
        ;
        
        try fs.cwd().writeFile(.{ .sub_path = self.config_file, .data = default_config });
        
        std.debug.print("Created default configuration at: {s}\n", .{self.config_file});
    }
    
    pub fn validateConfig(config_with_repos: *const ConfigWithRepositories) !void {
        // Validate repository configurations
        var iterator = config_with_repos.repositories.iterator();
        while (iterator.next()) |entry| {
            const repo = entry.value_ptr.*;
            
            if (repo.name.len == 0) return error.InvalidRepositoryName;
            if (repo.path.len == 0) return error.InvalidRepositoryPath;
            if (repo.remote.len == 0) return error.InvalidRepositoryRemote;
            if (repo.branch.len == 0) return error.InvalidRepositoryBranch;
        }
        
        // Validate linking configuration
        if (config_with_repos.config.linking.scan_depth == 0) return error.InvalidScanDepth;
        if (config_with_repos.config.settings.default_target.len == 0) return error.InvalidDefaultTarget;
    }
};