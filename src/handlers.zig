// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;
const cli = @import("cli.zig");
const linker = @import("linker.zig");
const config = @import("config.zig");
const module_scanner = @import("module_scanner.zig");
const repository_manager = @import("repository_manager.zig");
const config_manager = @import("config_manager.zig");
const git_operations = @import("git_operations.zig");
const git_operation_handler = @import("git_operation_handler.zig");
const config_loader = @import("config_loader.zig");
const error_reporter = @import("error_reporter.zig");
const path_utils = @import("path_utils.zig");
const deployment_handler = @import("deployment_handler.zig");
const handler_utils = @import("handler_utils.zig");
const constants = @import("constants.zig");

pub fn handleDeploy(allocator: std.mem.Allocator, args: cli.Args) !void {
    var deploy_handler = deployment_handler.DeploymentHandler.init(allocator);
    _ = try deploy_handler.deploy(args);
}

pub fn handlePull(allocator: std.mem.Allocator, args: cli.Args) !void {
    try handler_utils.withGitHandler(allocator, args, .pull_only, "Pulling updates");
}

pub fn handlePush(allocator: std.mem.Allocator, args: cli.Args) !void {
    try handler_utils.withGitHandler(allocator, args, .push_only, "Pushing changes");
}


pub fn handleConfig(allocator: std.mem.Allocator, args: cli.Args) !void {
    try handler_utils.withConfigManager(allocator, args, showConfigurationHelper);
}

fn showConfigurationHelper(cfg_manager: *config_manager.ConfigurationManager, args: cli.Args) !void {
    try cfg_manager.showConfiguration(args.config_key);
}

pub fn handleAddRepo(allocator: std.mem.Allocator, args: cli.Args) !void {
    try handler_utils.withConfigManager(allocator, args, addRepositoryHelper);
}

fn addRepositoryHelper(cfg_manager: *config_manager.ConfigurationManager, args: cli.Args) !void {
    const name = args.repo_name orelse unreachable; // Validated in parseArgs
    const path = args.repo_path orelse unreachable;
    const remote = args.repo_remote orelse unreachable;
    const branch = args.repo_branch;
    
    try cfg_manager.addRepository(name, path, remote, branch);
}

pub fn handleInitConfig(allocator: std.mem.Allocator, args: cli.Args) !void {
    _ = args;
    
    try handler_utils.withConfigManagerNoArgs(allocator, initConfigHelper);
}

fn initConfigHelper(cfg_manager: *config_manager.ConfigurationManager) !void {
    try cfg_manager.initializeConfiguration();
}

pub fn handleStatus(allocator: std.mem.Allocator, args: cli.Args) !void {
    _ = args; // might use verbose flag in the future
    
    try handler_utils.withConfigManagerNoArgs(allocator, showSystemStatusHelper);
}

fn showSystemStatusHelper(cfg_manager: *config_manager.ConfigurationManager) !void {
    try cfg_manager.showSystemStatus();
}

pub fn handleRepos(allocator: std.mem.Allocator, args: cli.Args) !void {
    _ = args; // might use verbose flag in the future
    
    try handler_utils.withConfigManagerNoArgs(allocator, listRepositoriesHelper);
}

fn listRepositoriesHelper(cfg_manager: *config_manager.ConfigurationManager) !void {
    try cfg_manager.listRepositories();
}

pub fn handleInfo(allocator: std.mem.Allocator, args: cli.Args) !void {
    try handler_utils.withConfigManager(allocator, args, showModuleInfoHelper);
}

fn showModuleInfoHelper(cfg_manager: *config_manager.ConfigurationManager, args: cli.Args) !void {
    try cfg_manager.showModuleInfo(args.module_name);
}


pub fn handlePushAll(allocator: std.mem.Allocator, args: cli.Args) !void {
    try handler_utils.withGitHandlerAll(allocator, args, .push_only, "Pushing");
}

pub fn handlePullAll(allocator: std.mem.Allocator, args: cli.Args) !void {
    try handler_utils.withGitHandlerAll(allocator, args, .pull_only, "Pulling");
}

pub fn handleSync(allocator: std.mem.Allocator, args: cli.Args) !void {
    
    std.debug.print("Sync operation: Pull all repositories, then deploy all modules\n", .{});
    
    // Step 1: Pull all repositories
    std.debug.print("Step 1: Pulling all repositories...\n", .{});
    
    try handlePullAll(allocator, args);
    
    // Step 2: Deploy all modules
    std.debug.print("Step 2: Deploying all modules...\n", .{});
    
    // Create a deploy args structure
    var deploy_args = args;
    deploy_args.action = .deploy;
    
    try handleDeploy(allocator, deploy_args);
    
    std.debug.print("Sync operation completed successfully\n", .{});
}

pub fn handleInitRepo(allocator: std.mem.Allocator, args: cli.Args) !void {
    _ = args;
    
    const cwd_path = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd_path);
    
    std.debug.print("Initializing git repository in {s}...\n", .{cwd_path});
    
    // Check if already a git repository
    var git_ops = git_operations.GitOperations.init(allocator);
    if (git_ops.isGitRepository(cwd_path)) {
        std.debug.print("Warning: Current directory is already a git repository.\n", .{});
        return;
    }
    
    // Initialize git repository
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "init" },
        .cwd = cwd_path,
    }) catch |err| {
        error_reporter.ErrorReporter.reportGitInitError(err);
        return;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    if (result.term != .Exited or result.term.Exited != 0) {
        error_reporter.ErrorReporter.reportGitInitFailed(result.stderr);
        return;
    }
    
    std.debug.print("Initialized git repository in {s}\n", .{cwd_path});
    
    std.debug.print("Repository initialization complete\n", .{});
}

pub fn handleSimpleUnlink(allocator: std.mem.Allocator, package_name: []const u8, verbose: bool) !void {
    const stdout = std.io.getStdOut().writer();
    if (verbose) try stdout.print("Simple unlink mode: processing module '{s}'\n", .{package_name});
    
    // Check if the module exists in current directory  
    const stat = fs.cwd().statFile(package_name) catch |err| switch (err) {
        error.FileNotFound => {
            if (verbose) {
                try stdout.print("Module '{s}' not found in current directory\n", .{package_name});
            }
            return;
        },
        else => return err,
    };
    
    var buf: [fs.max_path_bytes]u8 = undefined;
    if (std.posix.readlink(package_name, &buf)) |link_target| {
        // Case 1: Module is a symbolic link in current directory - just remove it
        if (verbose) {
            try stdout.print("Removing symbolic link: {s} -> {s}\n", .{ package_name, link_target });
        }
        
        fs.cwd().deleteFile(package_name) catch |err| {
            error_reporter.ErrorReporter.reportSymlinkRemovalError(package_name, err);
            return;
        };
        
        if (verbose) {
            try stdout.print("Successfully removed symbolic link: {s}\n", .{package_name});
        }
    } else |_| {
        if (stat.kind == .directory) {
            // Case 2: Module is a directory - look for .ndmgr file and remove from target
            if (verbose) {
                try stdout.print("Module '{s}' is a directory, looking for .ndmgr configuration\n", .{package_name});
            }
            
            try handleDirectoryUnlink(allocator, package_name, verbose);
        } else {
            error_reporter.ErrorReporter.reportInvalidModuleType(package_name);
        }
    }
}

fn handleDirectoryUnlink(allocator: std.mem.Allocator, module_dir: []const u8, verbose: bool) !void {
    // Look for .ndmgr file in the module directory
    const ndmgr_path = try fs.path.join(allocator, &.{ module_dir, constants.MODULE_CONFIG_FILE });
    defer allocator.free(ndmgr_path);
    
    var target_dir: []const u8 = undefined;
    var target_dir_owned: ?[]const u8 = null;
    defer if (target_dir_owned) |owned| allocator.free(owned);
    
    if (fs.cwd().readFileAlloc(allocator, ndmgr_path, 4096)) |content| {
        defer allocator.free(content);
        
        if (verbose) {
            std.debug.print("Found .ndmgr configuration file\n", .{});
        }
        
        // Parse the .ndmgr file for target_dir
        var line_iterator = std.mem.splitScalar(u8, content, '\n');
        var custom_target: ?[]const u8 = null;
        
        while (line_iterator.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            
            if (std.mem.indexOf(u8, trimmed, "=")) |equals_pos| {
                const key = std.mem.trim(u8, trimmed[0..equals_pos], " \t");
                const value = std.mem.trim(u8, trimmed[equals_pos + 1..], " \t\"");
                
                if (std.mem.eql(u8, key, constants.CONFIG_KEY_TARGET_DIR)) {
                    custom_target = value;
                    break;
                }
            }
        }
        
        if (custom_target) |custom| {
            // Handle tilde expansion
            target_dir_owned = path_utils.PathUtils.expandTilde(allocator, custom) catch {
                error_reporter.ErrorReporter.reportTildeExpansionError();
                return;
            };
            target_dir = target_dir_owned.?;
            
            if (verbose) {
                std.debug.print("Using custom target directory from .ndmgr: {s}\n", .{target_dir});
            }
        } else {
            target_dir_owned = path_utils.PathUtils.getHomeDirectory(allocator) catch {
                error_reporter.ErrorReporter.reportHomeDirectoryError();
                return;
            };
            target_dir = target_dir_owned.?;
            
            if (verbose) {
                std.debug.print("No custom target found, using default: {s}\n", .{target_dir});
            }
        }
    } else |_| {
        target_dir_owned = path_utils.PathUtils.getHomeDirectory(allocator) catch {
            error_reporter.ErrorReporter.reportHomeDirectoryError();
            return;
        };
        target_dir = target_dir_owned.?;
        
        if (verbose) {
            std.debug.print("No .ndmgr file found, using default target: {s}\n", .{target_dir});
        }
    }
    
    try removeSymlinksFromTarget(allocator, module_dir, target_dir, verbose);
}

fn removeSymlinksFromTarget(allocator: std.mem.Allocator, module_name: []const u8, target_dir: []const u8, verbose: bool) !void {
    // Get current working directory to build expected relative paths
    const cwd_path = try fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);
    
    const abs_module_path = try fs.path.join(allocator, &.{ cwd_path, module_name });
    defer allocator.free(abs_module_path);
    
    if (verbose) {
        std.debug.print("Searching for symlinks in target directory {s} pointing to {s}\n", .{ target_dir, abs_module_path });
    }
    
    var removed_count: u32 = 0;
    try removeSymlinksRecursive(allocator, target_dir, abs_module_path, &removed_count, verbose);
    
    if (removed_count == 0) {
        if (verbose) {
            std.debug.print("No symlinks found pointing to module '{s}' in target directory {s} (searched recursively)\n", .{ module_name, target_dir });
        }
    } else {
        if (verbose) {
            std.debug.print("Removed {} symlink(s) pointing to module '{s}' from target directory {s}\n", .{ removed_count, module_name, target_dir });
        }
    }
}

fn removeSymlinksRecursive(allocator: std.mem.Allocator, current_dir: []const u8, module_path: []const u8, removed_count: *u32, verbose: bool) !void {
    var dir_handle = fs.cwd().openDir(current_dir, .{ .iterate = true }) catch |err| {
        if (verbose) {
            std.debug.print("Warning: Cannot open directory {s}: {}\n", .{ current_dir, err });
        }
        return;
    };
    defer dir_handle.close();
    
    var iterator = dir_handle.iterate();
    
    while (try iterator.next()) |entry| {
        const entry_path = try fs.path.join(allocator, &.{ current_dir, entry.name });
        defer allocator.free(entry_path);
        
        if (entry.kind == .sym_link) {
            // Check if this symlink points to our module
            var buf: [fs.max_path_bytes]u8 = undefined;
            const link_target = std.posix.readlink(entry_path, &buf) catch {
                if (verbose) {
                    std.debug.print("Warning: Could not read symlink {s}\n", .{entry_path});
                }
                continue;
            };
            
            // Check if this symlink points to our module
            var points_to_module = false;
            
            if (fs.path.isAbsolute(link_target)) {
                points_to_module = std.mem.startsWith(u8, link_target, module_path);
            } else {
                // Relative path - resolve it from the symlink's directory
                const target_parent = fs.path.dirname(entry_path) orelse current_dir;
                const joined_path = try fs.path.join(allocator, &.{ target_parent, link_target });
                defer allocator.free(joined_path);
                
                const resolved_target = fs.cwd().realpathAlloc(allocator, joined_path) catch |err| {
                    if (verbose) {
                        std.debug.print("Warning: Could not resolve symlink target {s}: {}\n", .{ link_target, err });
                    }
                    continue;
                };
                defer allocator.free(resolved_target);
                
                // Check if the resolved path starts with our module path
                points_to_module = std.mem.startsWith(u8, resolved_target, module_path);
            }
            
            if (verbose) {
                std.debug.print("Checking symlink: {s} -> {s}, Points to module: {}\n", .{ entry_path, link_target, points_to_module });
            }
            
            if (points_to_module) {
                fs.cwd().deleteFile(entry_path) catch |err| {
                    if (verbose) {
                        std.debug.print("Warning: Could not remove symlink {s}: {}\n", .{ entry_path, err });
                    }
                    continue;
                };
                
                removed_count.* += 1;
                if (verbose) {
                    std.debug.print("Removed symlink: {s} -> {s}\n", .{ entry_path, link_target });
                }
            }
        } else if (entry.kind == .directory) {
            // Recursively search subdirectories
            try removeSymlinksRecursive(allocator, entry_path, module_path, removed_count, verbose);
        }
    }
}