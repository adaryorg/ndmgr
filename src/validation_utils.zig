// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;
const path_utils = @import("path_utils.zig");
const file_utils = @import("file_utils.zig");
const common = @import("common_utils.zig");

pub const ValidationUtils = struct {
    /// Validates that a directory exists
    pub fn validateDirectoryExists(path: []const u8) !void {
        if (!common.fileExists(path)) {
            return error.DirectoryNotFound;
        }
        if (!common.directoryExists(path)) {
            return error.NotADirectory;
        }
    }
    
    /// Validates that a directory is writable
    pub fn validateDirectoryWritable(path: []const u8) !void {
        try validateDirectoryExists(path);
        try file_utils.FileUtils.checkAccess(path, .write_only);
    }
    
    /// Validates a target directory for linking operations
    pub fn validateTargetDirectory(path: []const u8) !void {
        try validateDirectoryExists(path);
        
        file_utils.FileUtils.checkAccess(path, .write_only) catch |err| switch (err) {
            error.PermissionDenied => return error.TargetDirectoryNotWritable,
            else => return err,
        };
    }
    
    /// Validates a source directory for linking operations
    pub fn validateSourceDirectory(path: []const u8) !void {
        try validateDirectoryExists(path);
        
        file_utils.FileUtils.checkAccess(path, .read_only) catch |err| switch (err) {
            error.PermissionDenied => return error.SourceDirectoryNotReadable,
            else => return err,
        };
    }
    
    /// Validates that a file exists and is readable
    pub fn validateFileReadable(path: []const u8) !void {
        if (!file_utils.FileUtils.exists(path)) {
            return error.FileNotFound;
        }
        
        if (!file_utils.FileUtils.isFile(path)) {
            return error.NotAFile;
        }
        
        file_utils.FileUtils.checkAccess(path, .read_only) catch |err| switch (err) {
            error.PermissionDenied => return error.FileNotReadable,
            else => return err,
        };
    }
    
    /// Validates a repository path
    pub fn validateRepositoryPath(path: []const u8) !void {
        try validateDirectoryExists(path);
        
        // Check if it's a git repository by looking for .git directory
        const git_path = try std.fs.path.join(std.heap.page_allocator, &.{ path, ".git" });
        defer std.heap.page_allocator.free(git_path);
        
        if (!file_utils.FileUtils.exists(git_path)) {
            return error.NotAGitRepository;
        }
    }
    
    /// Validates a module name (basic validation)
    pub fn validateModuleName(name: []const u8) !void {
        if (name.len == 0) {
            return error.EmptyModuleName;
        }
        
        // Check for null bytes
        if (std.mem.indexOfScalar(u8, name, 0) != null) {
            return error.InvalidModuleNameCharacter;
        }
        
        // Check for invalid characters (basic validation)
        for (name) |char| {
            switch (char) {
                'a'...'z', 'A'...'Z', '0'...'9', '_', '-', '.' => {},
                else => return error.InvalidModuleNameCharacter,
            }
        }
        
        // Don't allow names starting with dot (hidden files)
        if (name[0] == '.') {
            return error.ModuleNameStartsWithDot;
        }
    }
    
    /// Validates a branch name (basic validation)
    pub fn validateBranchName(branch: []const u8) !void {
        if (branch.len == 0) {
            return error.EmptyBranchName;
        }
        
        // Basic git branch name validation
        if (common.hasPrefix(branch, "-") or common.hasSuffix(branch, "-")) {
            return error.InvalidBranchName;
        }
        
        if (std.mem.indexOf(u8, branch, "..") != null) {
            return error.InvalidBranchName;
        }
        
        for (branch) |char| {
            switch (char) {
                'a'...'z', 'A'...'Z', '0'...'9', '_', '-', '/', '.' => {},
                else => return error.InvalidBranchNameCharacter,
            }
        }
    }
};