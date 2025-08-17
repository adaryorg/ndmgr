// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;
const cli = @import("cli.zig");
const linker = @import("linker.zig");
const config = @import("config.zig");
const error_reporter = @import("error_reporter.zig");
const handlers = @import("handlers.zig");
const module_config = @import("module_config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try cli.parseArgs(allocator);
    defer args.deinit(allocator);
    
    var config_mgr = try config.ConfigManager.init(allocator);
    defer config_mgr.deinit();
    
    var config_with_repos = try config_mgr.loadConfig();
    defer config_with_repos.deinit();
    
    // Handle special operations first
    switch (args.action) {
        .version => {
            cli.printVersion();
            return;
        },
        .deploy => return handlers.handleDeploy(allocator, args),
        .pull => return handlers.handlePull(allocator, args),
        .push => return handlers.handlePush(allocator, args),
        .config => return handlers.handleConfig(allocator, args),
        .add_repo => return handlers.handleAddRepo(allocator, args),
        .init_config => return handlers.handleInitConfig(allocator, args),
        .status => return handlers.handleStatus(allocator, args),
        .repos => return handlers.handleRepos(allocator, args),
        .info => return handlers.handleInfo(allocator, args),
        .push_all => return handlers.handlePushAll(allocator, args),
        .pull_all => return handlers.handlePullAll(allocator, args),
        .sync => return handlers.handleSync(allocator, args),
        .init_repo => return handlers.handleInitRepo(allocator, args),
        else => {}, // Continue with link/unlink operations
    }
    
    // Handle simple unlink mode: -D <module> without explicit paths
    if (args.action == .unlink and args.packages.len > 0) {
        if (!args.explicit_source_dir and !args.explicit_target_dir) {
            // This is simple unlink - handle both symlink and directory cases
            for (args.packages) |package| {
                try handlers.handleSimpleUnlink(allocator, package, args.verbose);
            }
            return;
        }
    }
    
    for (args.packages) |package| {
        const package_dir = try fs.path.join(allocator, &.{ args.source_dir, package });
        defer allocator.free(package_dir);
        
        const abs_package_dir = try fs.cwd().realpathAlloc(allocator, package_dir);
        defer allocator.free(abs_package_dir);
        
        const effective_target_dir = module_config.getEffectiveTargetDir(allocator, package_dir) catch |err| switch (err) {
            error.FileNotFound => null,
            else => blk: {
                if (args.verbose) std.debug.print("Warning: Error reading .ndmgr file for {s}: {}\n", .{package, err});
                break :blk null;
            },
        } orelse try allocator.dupe(u8, args.target_dir);
        defer allocator.free(effective_target_dir);
        
        if (args.verbose and !std.mem.eql(u8, effective_target_dir, args.target_dir)) {
            std.debug.print("Using custom target directory for {s}: {s}\n", .{package, effective_target_dir});
        }
        
        const abs_target_dir = try fs.cwd().realpathAlloc(allocator, effective_target_dir);
        defer allocator.free(abs_target_dir);

        if (args.dry_run) {
            std.debug.print("Dry run: would process package {s}\n", .{package});
            continue;
        }

        // Create unified linker options from config
        const linking_config = config_with_repos.config.linking;
        const linking_options = linker.LinkerOptions{
            .verbose = args.verbose,
            .ignore_patterns = args.ignore_patterns,
            .conflict_resolution = switch (args.force) {
                .yes => linker.ConflictResolution.replace,     // Force yes means replace all conflicts 
                .default => linker.ConflictResolution.replace, // Basic --force means replace conflicts
                .no => linker.ConflictResolution.skip,         // Force no means skip conflicts
                .none => switch (linking_config.conflict_resolution) {
                    .fail => linker.ConflictResolution.fail,
                    .skip => linker.ConflictResolution.skip,
                    .adopt => linker.ConflictResolution.adopt,
                    .replace => linker.ConflictResolution.replace,
                },
            },
            .tree_folding = switch (linking_config.tree_folding) {
                .directory => linker.TreeFoldingStrategy.directory,
                .aggressive => linker.TreeFoldingStrategy.aggressive,
            },
            .backup_conflicts = switch (args.force) {
                .yes, .default => false,  // Disable backups for force modes
                .no, .none => linking_config.backup_conflicts,
            },
            .backup_suffix = linking_config.backup_suffix,
            .force = args.force,
        };
        
        // Initialize linker with unified options
        var pkg_linker = linker.Linker.init(allocator, abs_package_dir, abs_target_dir, linking_options) catch |err| {
            error_reporter.ErrorReporter.reportLinkerInitError(package, err);
            continue;
        };

        switch (args.action) {
            .link => {
                if (args.verbose) std.debug.print("Linking package: {s}\n", .{package});
                pkg_linker.link() catch |err| switch (err) {
                    error.ConflictDetected => {
                        std.debug.print("Use --force to override existing files.\n", .{});
                        std.process.exit(1);
                    },
                    else => return err,
                };
                if (args.verbose and args.ignore_patterns.len > 0) pkg_linker.printStats();
            },
            .unlink => {
                if (args.verbose) std.debug.print("Unlinking package: {s}\n", .{package});
                try pkg_linker.unlink();
            },
            .relink => {
                if (args.verbose) std.debug.print("Relinking package: {s}\n", .{package});
                try pkg_linker.unlink();
                pkg_linker.link() catch |err| switch (err) {
                    error.ConflictDetected => {
                        std.debug.print("Use --force to override existing files.\n", .{});
                        std.process.exit(1);
                    },
                    else => return err,
                };
                if (args.verbose and args.ignore_patterns.len > 0) pkg_linker.printStats();
            },
            .deploy, .pull, .push, .config, .add_repo, .init_config, .status, .repos, .info, .push_all, .pull_all, .sync, .init_repo, .version => unreachable, // These are handled earlier
        }
    }
}

