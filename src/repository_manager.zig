// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;
const config = @import("config.zig");
const git_ops = @import("git_operations.zig");
const string_utils = @import("string_utils.zig");
const Allocator = std.mem.Allocator;

pub const SyncOperation = enum {
    pull_only,
    push_only,
    pull_then_push,
    sync_bidirectional,
};

pub const SyncResult = struct {
    repository_name: []const u8,
    success: bool,
    message: []const u8,
    
    pub fn deinit(self: *SyncResult, allocator: Allocator) void {
        allocator.free(self.message);
    }
};

pub const SyncStats = struct {
    total_repositories: u32 = 0,
    successful_syncs: u32 = 0,
    failed_syncs: u32 = 0,
    repositories_skipped: u32 = 0,
    total_commits_pulled: u32 = 0,
    total_commits_pushed: u32 = 0,
};

pub const RepositoryManager = struct {
    allocator: Allocator,
    git_ops: git_ops.GitOperations,
    repositories: std.StringHashMap(config.Repository),
    verbose: bool = false,
    conflict_resolution: config.ConflictResolution = .ask,
    commit_message_template: []const u8 = "ndmgr: update {module} on {date}",
    
    pub fn init(allocator: Allocator) RepositoryManager {
        return .{
            .allocator = allocator,
            .git_ops = git_ops.GitOperations.init(allocator),
            .repositories = std.StringHashMap(config.Repository).init(allocator),
        };
    }
    
    pub fn deinit(self: *RepositoryManager) void {
        self.repositories.deinit();
    }
    
    pub fn loadRepositories(self: *RepositoryManager, config_with_repos: *const config.ConfigWithRepositories) !void {
        var iterator = config_with_repos.repositories.iterator();
        while (iterator.next()) |entry| {
            try self.repositories.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        
        self.git_ops.verbose = self.verbose;
        self.git_ops.conflict_resolution = config_with_repos.config.git.conflict_resolution;
        self.commit_message_template = config_with_repos.config.git.commit_message_template;
    }
    
    pub fn addRepository(self: *RepositoryManager, repo: config.Repository) !void {
        try self.repositories.put(repo.name, repo);
    }
    
    pub fn getRepository(self: *RepositoryManager, name: []const u8) ?config.Repository {
        return self.repositories.get(name);
    }
    
    pub fn listRepositories(self: *RepositoryManager) []const []const u8 {
        var names = std.ArrayList([]const u8).init(self.allocator);
        var iterator = self.repositories.iterator();
        
        while (iterator.next()) |entry| {
            names.append(entry.key_ptr.*) catch continue;
        }
        
        return names.toOwnedSlice() catch &[_][]const u8{};
    }
    
    pub fn syncRepository(self: *RepositoryManager, repo_name: []const u8, operation: SyncOperation) !SyncResult {
        const repo = self.repositories.get(repo_name) orelse {
            return SyncResult{
                .repository_name = repo_name,
                .success = false,
                .message = try self.allocator.dupe(u8, "Repository not found in configuration"),
            };
        };
        
        if (self.verbose) {
            std.debug.print("Syncing repository: {s} ({s})\n", .{ repo_name, @tagName(operation) });
        }
        
        // Ensure repository exists locally
        if (!self.git_ops.isGitRepository(repo.path)) {
            if (self.verbose) {
                std.debug.print("Repository not found locally, cloning: {s}\n", .{repo.remote});
            }
            
            self.git_ops.cloneRepository(repo.remote, repo.path, if (std.mem.eql(u8, repo.branch, "")) null else repo.branch) catch |err| {
                const error_msg = try std.fmt.allocPrint(self.allocator, "Failed to clone repository: {}", .{err});
                return SyncResult{
                    .repository_name = repo_name,
                    .success = false,
                    .message = error_msg,
                };
            };
        }
        
        if (repo.branch.len > 0 and !std.mem.eql(u8, repo.branch, "")) {
            self.git_ops.switchBranch(repo.path, repo.branch, false) catch {
                if (self.verbose) {
                    std.debug.print("Branch {s} doesn't exist, creating it\n", .{repo.branch});
                }
                self.git_ops.switchBranch(repo.path, repo.branch, true) catch |switch_err| {
                    const error_msg = try std.fmt.allocPrint(self.allocator, "Failed to switch/create branch {s}: {}", .{ repo.branch, switch_err });
                    return SyncResult{
                        .repository_name = repo_name,
                        .success = false,
                        .message = error_msg,
                    };
                };
            };
        }
        
        var success_msg = std.ArrayList(u8).init(self.allocator);
        var has_error = false;
        
        // Perform sync operations based on the operation type
        switch (operation) {
            .pull_only, .pull_then_push, .sync_bidirectional => {
                self.git_ops.pullRepository(repo.path, repo.branch) catch |err| {
                    has_error = true;
                    try success_msg.writer().print("Pull failed: {}. ", .{err});
                };
                
                if (!has_error) {
                    try success_msg.writer().print("Pull successful. ", .{});
                }
            },
            .push_only => {},
        }
        
        // Handle push operations
        switch (operation) {
            .push_only, .pull_then_push, .sync_bidirectional => {
                // Check if repository has uncommitted changes and auto_commit is enabled
                if (repo.auto_commit) {
                    const has_changes = self.git_ops.hasChanges(repo.path) catch |err| blk: {
                        if (self.verbose) {
                            std.debug.print("Warning: Could not check for changes in {s}: {}\n", .{ repo.path, err });
                        }
                        break :blk false;
                    };
                    
                    if (has_changes) {
                        if (self.verbose) {
                            std.debug.print("Changes detected in {s}, committing automatically\n", .{repo.path});
                        }
                        
                        // Generate commit message from template
                        const commit_message = try string_utils.StringUtils.processTemplate(
                            self.allocator, 
                            self.commit_message_template, 
                            repo.name
                        );
                        defer self.allocator.free(commit_message);
                        
                        self.git_ops.commitChanges(repo.path, commit_message, true) catch |err| {
                            has_error = true;
                            try success_msg.writer().print("Auto-commit failed: {}. ", .{err});
                        };
                        
                        if (!has_error and self.verbose) {
                            try success_msg.writer().print("Auto-commit successful. ", .{});
                        }
                    } else if (self.verbose) {
                        std.debug.print("No changes to commit in {s}\n", .{repo.path});
                    }
                }
                
                // Attempt to push (only if auto-commit didn't fail)
                if (!has_error) {
                    self.git_ops.pushRepository(repo.path, if (std.mem.eql(u8, repo.branch, "")) null else repo.branch, false) catch |err| {
                        has_error = true;
                        try success_msg.writer().print("Push failed: {}. ", .{err});
                    };
                    
                    if (!has_error) {
                        try success_msg.writer().print("Push successful. ", .{});
                    }
                }
            },
            .pull_only => {},
        }
        
        if (success_msg.items.len == 0) {
            try success_msg.writer().print("No operations performed.", .{});
        }
        
        return SyncResult{
            .repository_name = repo_name,
            .success = !has_error,
            .message = try success_msg.toOwnedSlice(),
        };
    }
    
    pub fn syncAllRepositories(self: *RepositoryManager, operation: SyncOperation, filter: ?[]const u8) ![]SyncResult {
        var results = std.ArrayList(SyncResult).init(self.allocator);
        var iterator = self.repositories.iterator();
        
        while (iterator.next()) |entry| {
            const repo_name = entry.key_ptr.*;
            
            // Apply filter if provided
            if (filter) |f| {
                if (std.mem.indexOf(u8, repo_name, f) == null) {
                    continue;
                }
            }
            
            const result = try self.syncRepository(repo_name, operation);
            try results.append(result);
        }
        
        return try results.toOwnedSlice();
    }
    
    pub fn isRepositoryClean(self: *RepositoryManager, repo_name: []const u8) !bool {
        const repo = self.repositories.get(repo_name) orelse return error.RepositoryNotFound;
        return self.git_ops.isGitRepository(repo.path);
    }
    
    pub fn commitToRepository(self: *RepositoryManager, repo_name: []const u8, message: []const u8, add_all: bool) !void {
        const repo = self.repositories.get(repo_name) orelse return error.RepositoryNotFound;
        
        // Format commit message with template if needed
        const formatted_message = try string_utils.StringUtils.processTemplate(self.allocator, message, repo_name);
        defer self.allocator.free(formatted_message);
        
        try self.git_ops.commitChanges(repo.path, formatted_message, add_all);
    }
    
    pub fn createBranchInRepository(self: *RepositoryManager, repo_name: []const u8, branch_name: []const u8) !void {
        const repo = self.repositories.get(repo_name) orelse return error.RepositoryNotFound;
        try self.git_ops.switchBranch(repo.path, branch_name, true);
    }
    
    pub fn switchBranchInRepository(self: *RepositoryManager, repo_name: []const u8, branch_name: []const u8) !void {
        const repo = self.repositories.get(repo_name) orelse return error.RepositoryNotFound;
        try self.git_ops.switchBranch(repo.path, branch_name, false);
    }
    
    pub fn printSyncStats(self: *RepositoryManager, results: []const SyncResult) void {
        var stats = SyncStats{};
        stats.total_repositories = @intCast(results.len);
        
        for (results) |result| {
            if (result.success) {
                stats.successful_syncs += 1;
            } else {
                stats.failed_syncs += 1;
            }
        }
        
        std.debug.print("\nSync Statistics:\n", .{});
        std.debug.print("  Total repositories: {}\n", .{stats.total_repositories});
        std.debug.print("  Successful syncs: {}\n", .{stats.successful_syncs});
        std.debug.print("  Failed syncs: {}\n", .{stats.failed_syncs});
        
        if (self.verbose) {
            std.debug.print("\nDetailed Results:\n", .{});
            for (results) |result| {
                const status = if (result.success) "✓" else "✗";
                std.debug.print("  {s} {s}: {s}\n", .{ status, result.repository_name, result.message });
            }
        }
    }
    
};