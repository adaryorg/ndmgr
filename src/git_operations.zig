// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const config = @import("config.zig");

pub const GitError = error{
    GitCommandFailed,
    InvalidRepository,
    MergeConflict,
};

pub const GitOperations = struct {
    allocator: Allocator,
    verbose: bool = false,
    conflict_resolution: config.ConflictResolution = .ask,
    
    pub fn init(allocator: Allocator) GitOperations {
        return .{
            .allocator = allocator,
        };
    }
    
    pub fn isGitRepository(self: *GitOperations, path: []const u8) bool {
        const git_dir = std.fmt.allocPrint(self.allocator, "{s}/.git", .{path}) catch return false;
        defer self.allocator.free(git_dir);
        
        const stat = fs.cwd().statFile(git_dir) catch return false;
        return stat.kind == .directory or stat.kind == .file;
    }
    
    pub fn pullRepository(self: *GitOperations, repo_path: []const u8, branch: ?[]const u8) !void {
        if (!self.isGitRepository(repo_path)) {
            return GitError.InvalidRepository;
        }
        
        if (self.verbose) {
            std.debug.print("Pulling repository: {s}\n", .{repo_path});
        }
        
        // Check if repository has uncommitted changes
        const has_changes = try self.hasChanges(repo_path);
        
        if (has_changes) {
            if (self.verbose) {
                std.debug.print("Repository has uncommitted changes, handling according to conflict resolution: {s}\n", .{@tagName(self.conflict_resolution)});
            }
            
            switch (self.conflict_resolution) {
                .ask => {
                    std.debug.print("Repository has uncommitted changes. How do you want to proceed?\n", .{});
                    std.debug.print("  1) Commit local changes and merge (local)\n", .{});
                    std.debug.print("  2) Discard local changes and use remote (remote)\n", .{});
                    std.debug.print("  3) Cancel operation\n", .{});
                    std.debug.print("Choice [1-3]: ", .{});
                    
                    var buffer: [1024]u8 = undefined;
    var file_reader = std.fs.File.stdin().reader(&buffer);
    const stdin = &file_reader.interface;
                    const input = stdin.takeDelimiterExclusive('\n') catch return error.InvalidInput;
                    const trimmed = std.mem.trim(u8, input, " \t\n\r");
                    
                    if (std.mem.eql(u8, trimmed, "1")) {
                        try self.handleLocalConflictResolution(repo_path, branch);
                    } else if (std.mem.eql(u8, trimmed, "2")) {
                        try self.handleRemoteConflictResolution(repo_path, branch);
                    } else {
                        std.debug.print("Operation cancelled\n", .{});
                        return;
                    }
                },
                .local => {
                    try self.handleLocalConflictResolution(repo_path, branch);
                },
                .remote => {
                    try self.handleRemoteConflictResolution(repo_path, branch);
                },
            }
        } else {
            // No local changes, do a normal pull
            try self.performPull(repo_path, branch);
        }
        
        if (self.verbose) {
            std.debug.print("Pull operation completed successfully\n", .{});
        }
    }
    
    fn handleLocalConflictResolution(self: *GitOperations, repo_path: []const u8, branch: ?[]const u8) !void {
        if (self.verbose) {
            std.debug.print("Committing local changes before pull\n", .{});
        }
        
        // Commit local changes
        try self.commitChanges(repo_path, "Local changes before pull", true);
        
        // Now perform the pull
        try self.performPull(repo_path, branch);
    }
    
    fn handleRemoteConflictResolution(self: *GitOperations, repo_path: []const u8, branch: ?[]const u8) !void {
        if (self.verbose) {
            std.debug.print("Discarding local changes and pulling from remote\n", .{});
        }
        
        // Reset working directory to HEAD (discard local changes)
        const reset_result = try self.runGitCommandInRepo(repo_path, &[_][]const u8{ "reset", "--hard", "HEAD" });
        defer reset_result.deinit(self.allocator);
        
        if (reset_result.exit_code != 0) {
            if (self.verbose) {
                std.debug.print("Git reset failed: {s}\n", .{reset_result.stderr});
            }
            return GitError.GitCommandFailed;
        }
        
        // Clean untracked files
        const clean_result = try self.runGitCommandInRepo(repo_path, &[_][]const u8{ "clean", "-fd" });
        defer clean_result.deinit(self.allocator);
        
        if (clean_result.exit_code != 0) {
            if (self.verbose) {
                std.debug.print("Git clean failed: {s}\n", .{clean_result.stderr});
            }
            return GitError.GitCommandFailed;
        }
        
        // Now perform the pull
        try self.performPull(repo_path, branch);
    }
    
    fn performPull(self: *GitOperations, repo_path: []const u8, branch: ?[]const u8) !void {
        var pull_args = std.array_list.AlignedManaged([]const u8, null).init(self.allocator);
        defer pull_args.deinit();
        
        try pull_args.append("git");
        try pull_args.append("-C");
        try pull_args.append(repo_path);
        try pull_args.append("pull");
        
        if (branch) |b| {
            try pull_args.append("origin");
            try pull_args.append(b);
        }
        
        const result = try self.runGitCommand(pull_args.items);
        defer result.deinit(self.allocator);
        
        if (result.exit_code != 0) {
            if (self.verbose) {
                std.debug.print("Git pull failed: {s}\n", .{result.stderr});
            }
            return GitError.GitCommandFailed;
        }
        
        if (self.verbose) {
            std.debug.print("Pull successful\n", .{});
        }
    }
    
    pub fn pushRepository(self: *GitOperations, repo_path: []const u8, branch: ?[]const u8, force: bool) !void {
        if (!self.isGitRepository(repo_path)) {
            return GitError.InvalidRepository;
        }
        
        if (self.verbose) {
            std.debug.print("Pushing repository: {s}\n", .{repo_path});
        }
        
        var push_args = std.array_list.AlignedManaged([]const u8, null).init(self.allocator);
        defer push_args.deinit();
        
        try push_args.append("git");
        try push_args.append("-C");
        try push_args.append(repo_path);
        try push_args.append("push");
        
        if (force) {
            try push_args.append("--force");
        }
        
        try push_args.append("origin");
        
        if (branch) |b| {
            try push_args.append(b);
        }
        
        const result = try self.runGitCommand(push_args.items);
        defer result.deinit(self.allocator);
        
        if (result.exit_code != 0) {
            if (self.verbose) {
                std.debug.print("Git push failed: {s}\n", .{result.stderr});
            }
            return GitError.GitCommandFailed;
        }
        
        if (self.verbose) {
            std.debug.print("Push successful\n", .{});
        }
    }
    
    pub fn cloneRepository(self: *GitOperations, remote_url: []const u8, local_path: []const u8, branch: ?[]const u8) !void {
        if (self.verbose) {
            std.debug.print("Cloning repository: {s} to {s}\n", .{ remote_url, local_path });
        }
        
        var clone_args = std.array_list.AlignedManaged([]const u8, null).init(self.allocator);
        defer clone_args.deinit();
        
        try clone_args.append("git");
        try clone_args.append("clone");
        
        if (branch) |b| {
            try clone_args.append("-b");
            try clone_args.append(b);
        }
        
        try clone_args.append(remote_url);
        try clone_args.append(local_path);
        
        const result = try self.runGitCommand(clone_args.items);
        defer result.deinit(self.allocator);
        
        if (result.exit_code != 0) {
            if (self.verbose) {
                std.debug.print("Git clone failed: {s}\n", .{result.stderr});
            }
            return GitError.GitCommandFailed;
        }
        
        if (self.verbose) {
            std.debug.print("Clone successful\n", .{});
        }
    }
    
    pub fn hasChanges(self: *GitOperations, repo_path: []const u8) !bool {
        if (!self.isGitRepository(repo_path)) {
            return GitError.InvalidRepository;
        }
        
        // Check for any changes (staged, unstaged, or untracked)
        const status_result = try self.runGitCommandInRepo(repo_path, &[_][]const u8{ "status", "--porcelain" });
        defer status_result.deinit(self.allocator);
        
        if (status_result.exit_code != 0) {
            return GitError.GitCommandFailed;
        }
        
        // If git status --porcelain returns any output, there are changes
        return std.mem.trim(u8, status_result.stdout, " \t\n\r").len > 0;
    }
    
    pub fn commitChanges(self: *GitOperations, repo_path: []const u8, message: []const u8, add_all: bool) !void {
        if (!self.isGitRepository(repo_path)) {
            return GitError.InvalidRepository;
        }
        
        if (self.verbose) {
            std.debug.print("Committing changes in: {s}\n", .{repo_path});
        }
        
        // Add files if requested
        if (add_all) {
            const add_result = try self.runGitCommandInRepo(repo_path, &[_][]const u8{ "add", "." });
            defer add_result.deinit(self.allocator);
            
            if (add_result.exit_code != 0) {
                return GitError.GitCommandFailed;
            }
        }
        
        // Commit changes
        const commit_result = try self.runGitCommandInRepo(repo_path, &[_][]const u8{ "commit", "-m", message });
        defer commit_result.deinit(self.allocator);
        
        if (commit_result.exit_code != 0) {
            if (std.mem.indexOf(u8, commit_result.stdout, "nothing to commit") != null) {
                if (self.verbose) {
                    std.debug.print("No changes to commit in {s}\n", .{repo_path});
                }
                return;
            }
            return GitError.GitCommandFailed;
        }
        
        if (self.verbose) {
            std.debug.print("Commit successful\n", .{});
        }
    }
    
    pub fn switchBranch(self: *GitOperations, repo_path: []const u8, branch: []const u8, create: bool) !void {
        if (!self.isGitRepository(repo_path)) {
            return GitError.InvalidRepository;
        }
        
        if (self.verbose) {
            std.debug.print("Switching to branch: {s} in {s}\n", .{ branch, repo_path });
        }
        
        var checkout_args = std.array_list.AlignedManaged([]const u8, null).init(self.allocator);
        defer checkout_args.deinit();
        
        try checkout_args.append("checkout");
        if (create) {
            try checkout_args.append("-b");
        }
        try checkout_args.append(branch);
            
        const result = try self.runGitCommandInRepo(repo_path, checkout_args.items);
        defer result.deinit(self.allocator);
        
        if (result.exit_code != 0) {
            return GitError.GitCommandFailed;
        }
        
        if (self.verbose) {
            std.debug.print("Branch switched successfully\n", .{});
        }
    }
    
    // Helper methods
    
    const CommandResult = struct {
        exit_code: u8,
        stdout: []const u8,
        stderr: []const u8,
        
        pub fn deinit(self: CommandResult, allocator: std.mem.Allocator) void {
            allocator.free(self.stdout);
            allocator.free(self.stderr);
        }
    };
    
    fn runGitCommand(self: *GitOperations, args: []const []const u8) !CommandResult {
        var process = std.process.Child.init(args, self.allocator);
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Pipe;
        
        try process.spawn();
        
        const stdout = try process.stdout.?.readToEndAlloc(self.allocator, 1024 * 1024);
        const stderr = try process.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024);
        
        const result = try process.wait();
        const exit_code: u8 = switch (result) {
            .Exited => |code| @intCast(code),
            else => 1,
        };
        
        return CommandResult{
            .exit_code = exit_code,
            .stdout = stdout,
            .stderr = stderr,
        };
    }
    
    fn runGitCommandInRepo(self: *GitOperations, repo_path: []const u8, args: []const []const u8) !CommandResult {
        var full_args = std.array_list.AlignedManaged([]const u8, null).init(self.allocator);
        defer full_args.deinit();
        
        try full_args.append("git");
        try full_args.append("-C");
        try full_args.append(repo_path);
        
        for (args) |arg| {
            try full_args.append(arg);
        }
        
        return self.runGitCommand(full_args.items);
    }
};