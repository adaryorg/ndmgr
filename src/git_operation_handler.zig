// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const config = @import("config.zig");
const config_manager = @import("config_manager.zig");
const repository_manager = @import("repository_manager.zig");
const cli = @import("cli.zig");

pub const GitOperationHandler = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) GitOperationHandler {
        return .{ .allocator = allocator };
    }
    
    pub fn handleRepoOperation(self: *GitOperationHandler, args: cli.Args, operation: repository_manager.SyncOperation, operation_name: []const u8) !void {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        
        // Load configuration
        const cfg_mgr = try config.ConfigManager.init(self.allocator);
        defer cfg_mgr.deinit();
        
        var app_config = try cfg_mgr.loadConfig();
        defer app_config.deinit();
        
        // Initialize repository manager
        var repo_manager = repository_manager.RepositoryManager.init(self.allocator);
        defer repo_manager.deinit();
        
        repo_manager.verbose = args.verbose;
        try repo_manager.loadRepositories(&app_config);
        
        if (args.verbose) {
            try stdout.print("{s} from git repositories\n", .{operation_name});
        }
        
        if (args.repository) |specific_repo| {
            try self.handleSingleRepository(&repo_manager, specific_repo, operation, stdout);
        } else {
            try self.handleAllRepositories(&repo_manager, operation, stdout);
        }
        
        if (args.verbose) {
            try stdout.print("{s} operation completed successfully\n", .{operation_name});
        }
    }
    
    pub fn handleRepoOperationAll(self: *GitOperationHandler, args: cli.Args, operation: repository_manager.SyncOperation, operation_name: []const u8) !void {
        var cfg_manager = try config_manager.ConfigurationManager.init(self.allocator);
        defer cfg_manager.deinit();
        
        var config_with_repos = cfg_manager.config_mgr.loadConfig() catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("Error: Configuration file not found. Use --init-config to create one.\n", .{});
                return;
            },
            else => return err,
        };
        defer config_with_repos.deinit();
        
        if (config_with_repos.repositories.count() == 0) {
            std.debug.print("Warning: No repositories configured. Use --add-repo to add repositories.\n", .{});
            return;
        }
        
        std.debug.print("{s} all repositories...\n", .{operation_name});
        
        var repo_manager = repository_manager.RepositoryManager.init(self.allocator);
        defer repo_manager.deinit();
        
        repo_manager.verbose = args.verbose;
        try repo_manager.loadRepositories(&config_with_repos);
        
        const results = try repo_manager.syncAllRepositories(operation, null);
        defer {
            for (results) |*result| {
                result.deinit(self.allocator);
            }
            self.allocator.free(results);
        }
        
        // Display results
        var successful: u32 = 0;
        var failed: u32 = 0;
        
        for (results) |result| {
            if (result.success) {
                successful += 1;
                if (args.verbose) {
                    std.debug.print("{s} {s}: {s}\n", .{ operation_name, result.repository_name, result.message });
                }
            } else {
                failed += 1;
                const lowercase_op = std.ascii.allocLowerString(self.allocator, operation_name) catch operation_name;
                defer if (!std.mem.eql(u8, lowercase_op, operation_name)) self.allocator.free(lowercase_op);
                std.debug.print("Error: Failed to {s} {s}: {s}\n", .{ lowercase_op, result.repository_name, result.message });
            }
        }
        
        std.debug.print("{s} completed: {} successful, {} failed\n", .{ operation_name, successful, failed });
    }
    
    fn handleSingleRepository(self: *GitOperationHandler, repo_manager: *repository_manager.RepositoryManager, specific_repo: []const u8, operation: repository_manager.SyncOperation, stdout: anytype) !void {
        _ = self;
        const result = try repo_manager.syncRepository(specific_repo, operation);
        defer {
            var mutable_result = result;
            mutable_result.deinit(repo_manager.allocator);
        }
        
        if (result.success) {
            try stdout.print("✓ {s}: {s}\n", .{ result.repository_name, result.message });
        } else {
            try stdout.print("✗ {s}: {s}\n", .{ result.repository_name, result.message });
            std.process.exit(1);
        }
    }
    
    fn handleAllRepositories(self: *GitOperationHandler, repo_manager: *repository_manager.RepositoryManager, operation: repository_manager.SyncOperation, stdout: anytype) !void {
        _ = self;
        _ = stdout;
        const results = try repo_manager.syncAllRepositories(operation, null);
        defer {
            for (results) |*result| {
                result.deinit(repo_manager.allocator);
            }
            repo_manager.allocator.free(results);
        }
        
        repo_manager.printSyncStats(results);
        
        // Check if any failed
        for (results) |result| {
            if (!result.success) {
                std.process.exit(1);
            }
        }
    }
};