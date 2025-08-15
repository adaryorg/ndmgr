// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const cli = @import("cli.zig");

pub const FileUtils = struct {
    /// Creates a directory if it doesn't exist
    pub fn ensureDirectory(path: []const u8) !void {
        fs.cwd().makeDir(path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
    
    /// Creates a directory tree (like mkdir -p)
    pub fn ensureDirectoryTree(path: []const u8) !void {
        fs.cwd().makePath(path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
    
    /// Checks if a file or directory exists
    pub fn exists(path: []const u8) bool {
        _ = fs.cwd().statFile(path) catch return false;
        return true;
    }
    
    /// Gets file statistics
    pub fn getStats(path: []const u8) !fs.File.Stat {
        return try fs.cwd().statFile(path);
    }
    
    /// Checks if path is a directory
    pub fn isDirectory(path: []const u8) bool {
        const stat = fs.cwd().statFile(path) catch return false;
        return stat.kind == .directory;
    }
    
    /// Checks if path is a regular file
    pub fn isFile(path: []const u8) bool {
        const stat = fs.cwd().statFile(path) catch return false;
        return stat.kind == .file;
    }
    
    /// Checks if path is a symbolic link
    pub fn isSymlink(path: []const u8) bool {
        const stat = fs.cwd().statFile(path) catch return false;
        return stat.kind == .sym_link;
    }
    
    /// Removes a file if it exists
    pub fn removeFile(path: []const u8) !void {
        fs.cwd().deleteFile(path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }
    
    /// Removes a directory tree
    pub fn removeDirectoryTree(path: []const u8) !void {
        fs.cwd().deleteTree(path) catch |err| switch (err) {
            error.NotDir => {},
            else => return err,
        };
    }
    
    /// Removes a file or directory (auto-detects type)
    pub fn remove(path: []const u8) !void {
        const stat = fs.cwd().statFile(path) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        
        switch (stat.kind) {
            .directory => try removeDirectoryTree(path),
            else => try removeFile(path),
        }
    }
    
    /// Renames/moves a file or directory
    pub fn rename(old_path: []const u8, new_path: []const u8) !void {
        try fs.cwd().rename(old_path, new_path);
    }
    
    /// Creates a backup of a file by appending a suffix
    pub fn createBackup(allocator: Allocator, path: []const u8, suffix: []const u8) ![]const u8 {
        return createBackupWithOptions(allocator, path, suffix, .none);
    }
    
    /// Creates a backup of a file by appending a suffix with force option
    pub fn createBackupWithOptions(allocator: Allocator, path: []const u8, suffix: []const u8, force: cli.ForceMode) ![]const u8 {
        const final_suffix = if (suffix.len > 0 and suffix[0] == '.') 
            suffix 
        else 
            try std.mem.concat(allocator, u8, &.{ ".", suffix });
        defer if (final_suffix.ptr != suffix.ptr) allocator.free(final_suffix);
        
        const backup_path = try std.mem.concat(allocator, u8, &.{ path, final_suffix });
        errdefer allocator.free(backup_path);
        
        // Check if backup already exists
        if (exists(backup_path)) {
            const should_replace = try getUserChoice(
                "Do you want to replace the existing backup? [y/N]: ",
                false, // default to no
                force
            );
            
            if (should_replace) {
                try remove(backup_path);
                std.debug.print("Existing backup replaced.\n", .{});
            } else {
                std.debug.print("Operation cancelled to preserve existing backup.\n", .{});
                return error.BackupConflict;
            }
        }
        
        fs.cwd().rename(path, backup_path) catch |err| {
            std.debug.print("Failed to create backup: {s} -> {s}\n", .{ path, backup_path });
            std.debug.print("Error: {}\n", .{err});
            return err;
        };
        
        return backup_path;
    }
    
    /// Reads a symbolic link target
    pub fn readSymlink(path: []const u8, buffer: []u8) ![]const u8 {
        return try std.posix.readlink(path, buffer);
    }
    
    /// Creates a symbolic link
    pub fn createSymlink(target: []const u8, link_path: []const u8) !void {
        try std.posix.symlink(target, link_path);
    }
    
    /// Writes string content to a file
    pub fn writeFile(path: []const u8, content: []const u8) !void {
        try fs.cwd().writeFile(.{ .sub_path = path, .data = content });
    }
    
    /// Checks file/directory access permissions
    pub fn checkAccess(path: []const u8, mode: fs.File.OpenMode) !void {
        try fs.cwd().access(path, .{ .mode = mode });
    }
    
    /// Gets user choice for interactive prompts with force mode support
    /// Returns the default if force is .default, yes if force is .yes, no if force is .no
    fn getUserChoice(prompt: []const u8, default_choice: bool, force: cli.ForceMode) !bool {
        switch (force) {
            .none => {
                // Interactive mode: ask user
                std.debug.print("{s}", .{prompt});
                
                var buffer: [10]u8 = undefined;
                const stdin = std.io.getStdIn().reader();
                if (stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) |input| {
                    if (input) |response| {
                        const trimmed = std.mem.trim(u8, response, " \t\r\n");
                        if (std.mem.eql(u8, trimmed, "y") or std.mem.eql(u8, trimmed, "Y") or std.mem.eql(u8, trimmed, "yes")) {
                            return true;
                        } else if (std.mem.eql(u8, trimmed, "n") or std.mem.eql(u8, trimmed, "N") or std.mem.eql(u8, trimmed, "no")) {
                            return false;
                        } else if (trimmed.len == 0) {
                            // Empty input, use default
                            return default_choice;
                        } else {
                            // Invalid input, use default
                            return default_choice;
                        }
                    }
                } else |_| {
                    std.debug.print("Failed to read user input. Using default.\n", .{});
                    return default_choice;
                }
                return default_choice;
            },
            .default => {
                // Use default choice for prompts when --force is used without parameter
                const choice_str = if (default_choice) "yes" else "no";
                std.debug.print("{s}(auto: {s})\n", .{ prompt, choice_str });
                return default_choice;
            },
            .yes => {
                // Force yes
                std.debug.print("{s}(forced: yes)\n", .{prompt});
                return true;
            },
            .no => {
                // Force no
                std.debug.print("{s}(forced: no)\n", .{prompt});
                return false;
            },
        }
    }
};