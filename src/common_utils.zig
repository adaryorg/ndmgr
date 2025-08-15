// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;

/// Common path validation logic used across multiple modules
pub fn validatePath(path: []const u8) !void {
    if (path.len == 0) {
        return error.EmptyPath;
    }
    
    // Check for null bytes
    if (std.mem.indexOfScalar(u8, path, 0) != null) {
        return error.InvalidPath;
    }
}

/// Check if a directory exists and is accessible
pub fn directoryExists(path: []const u8) bool {
    fs.cwd().access(path, .{}) catch return false;
    const stat = fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

/// Check if a file exists (any kind)
pub fn fileExists(path: []const u8) bool {
    fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Common string duplication pattern
pub fn duplicateString(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    return allocator.dupe(u8, str);
}

/// Common pattern for checking string prefixes
pub fn hasPrefix(str: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, str, prefix);
}

/// Common pattern for checking string suffixes
pub fn hasSuffix(str: []const u8, suffix: []const u8) bool {
    return std.mem.endsWith(u8, str, suffix);
}

/// Join paths with proper handling
pub fn joinPaths(allocator: std.mem.Allocator, paths: []const []const u8) ![]u8 {
    return fs.path.join(allocator, paths);
}

