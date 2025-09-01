// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const config = @import("config.zig");
const git_ops = @import("git_operations.zig");
const repository_manager = @import("repository_manager.zig");
const module_scanner = @import("module_scanner.zig");
const Allocator = std.mem.Allocator;

pub const ConfigurationManager = struct {
    allocator: Allocator,
    config_mgr: config.ConfigManager,
    
    pub fn init(allocator: Allocator) !ConfigurationManager {
        return ConfigurationManager{
            .allocator = allocator,
            .config_mgr = try config.ConfigManager.init(allocator),
        };
    }
    
    pub fn deinit(self: *ConfigurationManager) void {
        self.config_mgr.deinit();
    }
    
    pub fn showConfiguration(self: *ConfigurationManager, key: ?[]const u8) !void {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        
        var config_with_repos = self.config_mgr.loadConfig() catch |err| switch (err) {
            error.FileNotFound => {
                try stdout.print("Configuration file not found. Use --init-config to create one.\n", .{});
                return;
            },
            else => return err,
        };
        defer config_with_repos.deinit();
        
        if (key) |k| {
            try self.showConfigurationKey(k, &config_with_repos);
        } else {
            try self.showAllConfiguration(&config_with_repos);
        }
    }
    
    fn showConfigurationKey(self: *ConfigurationManager, key: []const u8, config_with_repos: *const config.ConfigWithRepositories) !void {
        _ = self;
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        
        if (std.mem.eql(u8, key, "git.conflict_resolution")) {
            std.debug.print("{s}\n", .{@tagName(config_with_repos.config.git.conflict_resolution)});
        } else if (std.mem.eql(u8, key, "git.commit_message_template")) {
            try stdout.print("{s}\n", .{config_with_repos.config.git.commit_message_template});
        } else if (std.mem.eql(u8, key, "linking.scan_depth")) {
            try stdout.print("{}\n", .{config_with_repos.config.linking.scan_depth});
        } else if (std.mem.eql(u8, key, "linking.backup_conflicts")) {
            try stdout.print("{}\n", .{config_with_repos.config.linking.backup_conflicts});
        } else if (std.mem.eql(u8, key, "linking.conflict_resolution")) {
            try stdout.print("{s}\n", .{@tagName(config_with_repos.config.linking.conflict_resolution)});
        } else if (std.mem.eql(u8, key, "linking.tree_folding")) {
            try stdout.print("{s}\n", .{@tagName(config_with_repos.config.linking.tree_folding)});
        } else if (std.mem.eql(u8, key, "settings.default_target")) {
            try stdout.print("{s}\n", .{config_with_repos.config.settings.default_target});
        } else if (std.mem.eql(u8, key, "settings.verbose")) {
            try stdout.print("{}\n", .{config_with_repos.config.settings.verbose});
        } else {
            try stdout.print("Unknown configuration key: {s}\n", .{key});
            try stdout.print("Available keys:\n", .{});
            try stdout.print("  git.conflict_resolution\n", .{});
            try stdout.print("  git.commit_message_template\n", .{});
            try stdout.print("  linking.scan_depth\n", .{});
            try stdout.print("  linking.backup_conflicts\n", .{});
            try stdout.print("  linking.conflict_resolution\n", .{});
            try stdout.print("  linking.tree_folding\n", .{});
            try stdout.print("  settings.default_target\n", .{});
            try stdout.print("  settings.verbose\n", .{});
        }
    }
    
    fn showAllConfiguration(self: *ConfigurationManager, config_with_repos: *const config.ConfigWithRepositories) !void {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        
        try stdout.print("NDMGR Configuration\n", .{});
        try stdout.print("==================\n\n", .{});
        
        try stdout.print("Configuration File: {s}\n", .{self.config_mgr.config_file});
        
        // Display parsed configuration using TOML library data
        try stdout.print("Contents:\n", .{});
        
        if (config_with_repos.parsed) |parsed| {
            const toml_config = parsed.value;
            
            try stdout.print("\n[git]\n", .{});
            if (toml_config.git) |git| {
                try stdout.print("conflict_resolution = \"{s}\"\n", .{@tagName(git.conflict_resolution)});
                try stdout.print("commit_message_template = \"{s}\"\n", .{git.commit_message_template});
            }
            
            std.debug.print("\n[settings]\n", .{});
            if (toml_config.settings) |settings| {
                std.debug.print("default_target = \"{s}\"\n", .{settings.default_target});
                std.debug.print("verbose = {}\n", .{settings.verbose});
            }
            
            // Show the merged linking configuration (not raw TOML)
            try stdout.print("\n[linking]\n", .{});
            const merged_linking = config_with_repos.config.linking;
            try stdout.print("conflict_resolution = \"{s}\"\n", .{@tagName(merged_linking.conflict_resolution)});
            try stdout.print("tree_folding = \"{s}\"\n", .{@tagName(merged_linking.tree_folding)});
            try stdout.print("backup_conflicts = {}\n", .{merged_linking.backup_conflicts});
            try stdout.print("backup_suffix = \"{s}\"\n", .{merged_linking.backup_suffix});
            try stdout.print("scan_depth = {}\n", .{merged_linking.scan_depth});
            try stdout.print("ignore_patterns = [", .{});
            for (merged_linking.ignore_patterns, 0..) |pattern, i| {
                if (i > 0) try stdout.print(", ", .{});
                try stdout.print("\"{s}\"", .{pattern});
            }
            try stdout.print("]\n", .{});
            
            
            std.debug.print("\nRepositories:\n", .{});
            if (toml_config.repository) |repos| {
                for (repos) |repo| {
                    std.debug.print("\n[[repository]]\n", .{});
                    std.debug.print("name = \"{s}\"\n", .{repo.name});
                    std.debug.print("path = \"{s}\"\n", .{repo.path});
                    std.debug.print("remote = \"{s}\"\n", .{repo.remote});
                    std.debug.print("branch = \"{s}\"\n", .{repo.branch});
                    std.debug.print("auto_commit = {}\n", .{repo.auto_commit});
                }
            } else {
                std.debug.print("No repositories configured.\n", .{});
            }
        } else {
            // Show default configuration when no parsed data is available
            std.debug.print("\n[git]\n", .{});
            std.debug.print("conflict_resolution = \"ask\"\n", .{});
            std.debug.print("commit_message_template = \"ndmgr: update {{module}} on {{date}}\"\n", .{});
            
            std.debug.print("\n[settings]\n", .{});
            std.debug.print("default_target = \"$HOME\"\n", .{});
            std.debug.print("verbose = false\n", .{});
            
            std.debug.print("\n[linking]\n", .{});
            std.debug.print("conflict_resolution = \"fail\"\n", .{});
            std.debug.print("tree_folding = \"directory\"\n", .{});
            std.debug.print("backup_conflicts = true\n", .{});
            std.debug.print("backup_suffix = \"bkp\"\n", .{});
            std.debug.print("scan_depth = 3\n", .{});
            std.debug.print("ignore_patterns = [\".git\", \"node_modules\"]\n", .{});
            
            
            std.debug.print("\nRepositories:\n", .{});
            std.debug.print("No repositories configured.\n", .{});
        }
        
        std.debug.print("\nActive Repository Summary ({}):\n", .{config_with_repos.repositories.count()});
        var iterator = config_with_repos.repositories.iterator();
        while (iterator.next()) |entry| {
            const repo = entry.value_ptr.*;
            std.debug.print("  {s}: {s} -> {s} ({s})\n", .{repo.name, repo.path, repo.remote, repo.branch});
        }
    }
    
    pub fn addRepository(self: *ConfigurationManager, name: []const u8, path: []const u8, remote: []const u8, branch: ?[]const u8) !void {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        const config_file_path = self.config_mgr.config_file;
        
        const config_exists = blk: {
            std.fs.cwd().access(config_file_path, .{}) catch break :blk false;
            break :blk true;
        };
        
        if (!config_exists) {
            try self.config_mgr.createDefaultConfig();
        }
        
        var existing_config = self.config_mgr.loadConfig() catch |err| {
            std.debug.print("Error loading existing config: {}\n", .{err});
            return;
        };
        defer existing_config.deinit();
        
        // Check if repository already exists by name
        if (existing_config.repositories.get(name) != null) {
            std.debug.print("Repository '{s}' already exists.\n", .{name});
            return;
        }
        
        // Create backup before modifying the config file
        try self.createSmartConfigBackup();
        
        // Since the TOML library doesn't support serialization, append to file
        const file = std.fs.cwd().openFile(config_file_path, .{ .mode = .write_only }) catch |err| {
            std.debug.print("Error opening config file for writing: {}\n", .{err});
            return;
        };
        defer file.close();
        
        try file.seekFromEnd(0); // Seek to end of file
        
        const repo_config = try std.fmt.allocPrint(self.allocator, 
            \\
            \\
            \\[[repository]]
            \\name = "{s}"
            \\path = "{s}"
            \\remote = "{s}"
            \\branch = "{s}"
            \\auto_commit = true
            \\
        , .{ name, path, remote, branch orelse "main" });
        defer self.allocator.free(repo_config);
        
        _ = try file.writeAll(repo_config);
        
        try stdout.print("Repository '{s}' added successfully.\n", .{name});
        try stdout.print("  Path: {s}\n", .{path});
        try stdout.print("  Remote: {s}\n", .{remote});
        try stdout.print("  Branch: {s}\n", .{branch orelse "main"});
    }
    
    
    pub fn initializeConfiguration(self: *ConfigurationManager) !void {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        try self.config_mgr.ensureConfigDir();
        
        // Check if config file already exists
        const config_exists = blk: {
            std.fs.cwd().access(self.config_mgr.config_file, .{}) catch |err| switch (err) {
                error.FileNotFound => break :blk false,
                else => break :blk false,
            };
            break :blk true;
        };
        
        if (config_exists) {
            var existing_config = self.config_mgr.loadConfig() catch |err| switch (err) {
                error.FileNotFound => {
                    // File existed but now doesn't, proceed with default
                    try self.config_mgr.createDefaultConfig();
                    try stdout.print("Configuration initialized at: {s}\n", .{self.config_mgr.config_file});
                    return;
                },
                else => {
                    try stdout.print("Warning: Cannot read existing config file, proceeding with initialization.\n", .{});
                    try self.config_mgr.createDefaultConfig();
                    try stdout.print("Configuration initialized at: {s}\n", .{self.config_mgr.config_file});
                    return;
                },
            };
            defer existing_config.deinit();
            
            // Check if the existing config has any repositories or non-default values
            const has_repositories = existing_config.repositories.count() > 0;
            
            if (has_repositories) {
                std.debug.print("Warning: Configuration file already exists and contains {} configured repositories.\n", .{existing_config.repositories.count()});
                std.debug.print("Proceeding with --init-config will DESTROY ALL EXISTING CONFIGURATION and reset to defaults.\n", .{});
                std.debug.print("\nCurrent repositories that will be lost:\n", .{});
                
                var iterator = existing_config.repositories.iterator();
                while (iterator.next()) |entry| {
                    const repo = entry.value_ptr.*;
                    std.debug.print("  - {s}: {s} -> {s}\n", .{ repo.name, repo.path, repo.remote });
                }
                
                std.debug.print("\nDo you want to proceed and destroy the existing configuration? [y/N]: ", .{});
                
                var stdin_buffer: [1024]u8 = undefined;
    var file_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &file_reader.interface;
                const input = stdin.takeDelimiterExclusive('\n') catch "";
                const trimmed = std.mem.trim(u8, input, " \t\n\r");
                
                if (!std.mem.eql(u8, trimmed, "y") and !std.mem.eql(u8, trimmed, "Y")) {
                    std.debug.print("Operation cancelled. Existing configuration preserved.\n", .{});
                    return;
                }
                
                std.debug.print("Proceeding with configuration reset...\n", .{});
                
                // Create backup before overwriting
                try self.createConfigBackup();
            }
        }
        
        try self.config_mgr.createDefaultConfig();
        std.debug.print("Configuration initialized at: {s}\n", .{self.config_mgr.config_file});
    }
    
    /// Creates a smart backup of the config file with date-counter format and duplicate detection
    fn createSmartConfigBackup(self: *ConfigurationManager) !void {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        
        // Get current date in YYYYMMDD format
        const timestamp = std.time.timestamp();
        
        // Convert timestamp to days since epoch
        const SECONDS_PER_DAY = 86400;
        const days_since_epoch = @divFloor(timestamp, SECONDS_PER_DAY);
        
        // Use algorithm to convert days since epoch to year/month/day
        // This is based on the civil calendar algorithm
        const DAYS_FROM_CIVIL_1970_01_01 = 719468;
        const era_days = days_since_epoch + DAYS_FROM_CIVIL_1970_01_01;
        
        const era = @divFloor(era_days, 146097);  // 400-year cycles
        const doe = era_days - era * 146097;      // day of era [0, 146096]
        
        const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365); // year of era [0, 399]
        const year = yoe + era * 400;
        
        const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100)); // day of year [0, 365]
        
        const mp = @divFloor(5 * doy + 2, 153);   // month point
        const day = doy - @divFloor(153 * mp + 2, 5) + 1; // day [1, 31]
        const month_temp = mp + if (mp < 10) @as(i64, 3) else @as(i64, -9); // month [1, 12]
        const month = @as(u32, @intCast(month_temp));
        const final_year = @as(u32, @intCast(year + if (mp >= 10) @as(i64, 1) else @as(i64, 0)));
        const final_day = @as(u32, @intCast(day));
        
        const date_str = try std.fmt.allocPrint(self.allocator, "{d:0>4}{d:0>2}{d:0>2}", .{ final_year, month, final_day });
        defer self.allocator.free(date_str);
        
        // Find the next available counter for today
        var counter: u32 = 1;
        var backup_path: []const u8 = "";
        
        while (true) {
            if (backup_path.len > 0) self.allocator.free(backup_path);
            backup_path = try std.fmt.allocPrint(self.allocator, "{s}.bkp.{s}-{d}", .{ self.config_mgr.config_file, date_str, counter });
            
            // Check if this backup file already exists
            const backup_exists = blk: {
                std.fs.cwd().access(backup_path, .{}) catch break :blk false;
                break :blk true;
            };
            
            if (!backup_exists) break;
            
            // Check if existing backup is identical to current config
            if (try self.areFilesIdentical(self.config_mgr.config_file, backup_path)) {
                self.allocator.free(backup_path);
                try stdout.print("Configuration file is identical to the last backup, skipping backup creation.\n", .{});
                return;
            }
            
            counter += 1;
        }
        
        defer self.allocator.free(backup_path);
        
        // Read the existing config file
        const config_content = std.fs.cwd().readFileAlloc(self.allocator, self.config_mgr.config_file, 1024 * 1024) catch |err| {
            std.debug.print("Warning: Could not read existing config file for backup: {}\n", .{err});
            return;
        };
        defer self.allocator.free(config_content);
        
        // Write to backup file
        std.fs.cwd().writeFile(.{ .sub_path = backup_path, .data = config_content }) catch |err| {
            std.debug.print("Warning: Could not create backup file {s}: {}\n", .{ backup_path, err });
            return;
        };
        
        try stdout.print("Created backup of existing configuration: {s}\n", .{backup_path});
    }
    
    /// Compares two files to check if they are identical
    fn areFilesIdentical(self: *ConfigurationManager, file1: []const u8, file2: []const u8) !bool {
        const content1 = std.fs.cwd().readFileAlloc(self.allocator, file1, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };
        defer self.allocator.free(content1);
        
        const content2 = std.fs.cwd().readFileAlloc(self.allocator, file2, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };
        defer self.allocator.free(content2);
        
        return std.mem.eql(u8, content1, content2);
    }
    
    fn createConfigBackup(self: *ConfigurationManager) !void {
        try self.createSmartConfigBackup();
    }
    
    pub fn showSystemStatus(self: *ConfigurationManager) !void {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        
        
        // Configuration status
        const config_exists = blk: {
            std.fs.cwd().access(self.config_mgr.config_file, .{}) catch |err| switch (err) {
                error.FileNotFound => break :blk false,
                else => break :blk false,
            };
            break :blk true;
        };
        try stdout.print("Config Path: {s}\n", .{self.config_mgr.config_file});
        
        if (!config_exists) {
            try stdout.print("\nUse --init-config to create a configuration file.\n", .{});
            return;
        }
        
        var config_with_repos = self.config_mgr.loadConfig() catch |err| {
            std.debug.print("Error loading configuration: {}\n", .{err});
            return;
        };
        defer config_with_repos.deinit();
        
        try stdout.print("\nRepositories ({}):\n", .{config_with_repos.repositories.count()});
        
        if (config_with_repos.repositories.count() == 0) {
            try stdout.print("  No repositories configured\n", .{});
        } else {
            var git_operations = git_ops.GitOperations.init(self.allocator);
            
            var iterator = config_with_repos.repositories.iterator();
            while (iterator.next()) |entry| {
                const repo = entry.value_ptr.*;
                const exists = blk: {
                    std.fs.cwd().access(repo.path, .{}) catch break :blk false;
                    break :blk true;
                };
                const is_git = if (exists) git_operations.isGitRepository(repo.path) else false;
                
                try stdout.print("  {s}:\n", .{repo.name});
                try stdout.print("    Path: {s}\n", .{repo.path});
                try stdout.print("    Git Repository: {s}\n", .{if (is_git) "Yes" else "No"});
                try stdout.print("    Remote: {s}\n", .{repo.remote});
                try stdout.print("    Branch: {s}\n", .{repo.branch});
            }
        }
        
        // Show module discovery
        try self.showModuleStatus();
    }
    
    fn showModuleStatus(self: *ConfigurationManager) !void {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        
        // Check if current working directory is a git repository
        var git_operations = git_ops.GitOperations.init(self.allocator);
        const cwd_path = try std.process.getCwdAlloc(self.allocator);
        defer self.allocator.free(cwd_path);
        
        if (!git_operations.isGitRepository(cwd_path)) {
            return;
        }
        
        const cfg_mgr = try config.ConfigManager.init(self.allocator);
        defer cfg_mgr.deinit();
        
        var app_config = try cfg_mgr.loadConfig();
        defer app_config.deinit();
        
        const linking_config = app_config.config.linking;
        var scanner = module_scanner.ModuleScanner.init(self.allocator, linking_config.scan_depth, linking_config.ignore_patterns);
        
        // Scan for modules in current directory
        var modules = scanner.scanForModules(".") catch |err| {
            std.debug.print("\nModule Scan: Error - {}\n", .{err});
            return;
        };
        defer {
            for (modules.items) |module| {
                module.deinit(self.allocator);
            }
            modules.deinit();
        }
        
        if (modules.items.len > 0) {
            try stdout.print("\nModules Found ({}):\n", .{modules.items.len});
            for (modules.items) |module| {
                try stdout.print("  {s}:\n", .{module.name});
                try stdout.print("    Path: {s}\n", .{module.path});
                if (module.target_dir) |target| {
                    try stdout.print("    Target Directory: {s}\n", .{target});
                }
            }
        }
    }
    
    pub fn listRepositories(self: *ConfigurationManager) !void {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        
        var config_with_repos = self.config_mgr.loadConfig() catch |err| switch (err) {
            error.FileNotFound => {
                try stdout.print("Configuration file not found. Use --init-config to create one.\n", .{});
                return;
            },
            else => return err,
        };
        defer config_with_repos.deinit();
        
        if (config_with_repos.repositories.count() == 0) {
            std.debug.print("No repositories configured.\n", .{});
            std.debug.print("Use --add-repo to add a repository.\n", .{});
            return;
        }
        
        std.debug.print("Configured Repositories ({}):\n", .{config_with_repos.repositories.count()});
        std.debug.print("============================\n\n", .{});
        
        var git_operations = git_ops.GitOperations.init(self.allocator);
        
        var iterator = config_with_repos.repositories.iterator();
        while (iterator.next()) |entry| {
            const repo = entry.value_ptr.*;
            const exists = blk: {
                std.fs.cwd().access(repo.path, .{}) catch break :blk false;
                break :blk true;
            };
            const is_git = if (exists) git_operations.isGitRepository(repo.path) else false;
            
            std.debug.print("{s}:\n", .{repo.name});
            std.debug.print("  Path: {s}\n", .{repo.path});
            std.debug.print("  Status: {s}\n", .{if (is_git) "✓ Ready" else if (exists) "⚠ Directory exists but not a git repository" else "✗ Path not found"});
            std.debug.print("  Remote: {s}\n", .{repo.remote});
            std.debug.print("  Branch: {s}\n", .{repo.branch});
            std.debug.print("  Auto Commit: {s}\n", .{if (repo.auto_commit) "enabled" else "disabled"});
            std.debug.print("\n", .{});
        }
    }
    
    pub fn showModuleInfo(self: *ConfigurationManager, module_name: ?[]const u8) !void {
        const cfg_mgr = try config.ConfigManager.init(self.allocator);
        defer cfg_mgr.deinit();
        
        var app_config = try cfg_mgr.loadConfig();
        defer app_config.deinit();
        
        const linking_config = app_config.config.linking;
        var scanner = module_scanner.ModuleScanner.init(self.allocator, linking_config.scan_depth, linking_config.ignore_patterns);
        
        var modules = scanner.scanForModules(".") catch |err| {
            std.debug.print("Error scanning for modules: {}\n", .{err});
            return;
        };
        defer {
            for (modules.items) |module| {
                module.deinit(self.allocator);
            }
            modules.deinit();
        }
        
        if (module_name) |name| {
            // Show specific module info
            for (modules.items) |module| {
                if (std.mem.eql(u8, module.name, name)) {
                    try self.showDetailedModuleInfo(&module);
                    return;
                }
            }
            std.debug.print("Module '{s}' not found.\n", .{name});
        } else {
            // Show all modules
            if (modules.items.len == 0) {
                std.debug.print("No modules found in current directory.\n", .{});
                return;
            }
            
            std.debug.print("Available Modules ({}):\n", .{modules.items.len});
            std.debug.print("======================\n\n", .{});
            
            for (modules.items) |module| {
                try self.showDetailedModuleInfo(&module);
                std.debug.print("\n", .{});
            }
        }
    }
    
    fn showDetailedModuleInfo(self: *ConfigurationManager, module: *const module_scanner.ModuleInfo) !void {
        _ = self;
        
        std.debug.print("{s}:\n", .{module.name});
        std.debug.print("  Path: {s}\n", .{module.path});
        std.debug.print("  Config File: {s}\n", .{module.config_path});
        
        if (module.target_dir) |target| {
            std.debug.print("  Target Directory: {s}\n", .{target});
        }
        
        std.debug.print("  Ignore: {s}\n", .{if (module.ignore) "yes" else "no"});
    }
    
};