// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;

pub fn isSymlink(path: []const u8) bool {
    var buf: [fs.max_path_bytes]u8 = undefined;
    _ = std.posix.readlink(path, &buf) catch return false;
    return true;
}

pub fn resolveSymlinkSource(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (!isSymlink(path)) return error.NotASymlink;
    
    var buf: [fs.max_path_bytes]u8 = undefined;
    const target = std.posix.readlink(path, &buf) catch return error.CannotReadSymlink;
    
    return allocator.dupe(u8, target);
}



pub fn isPathInRepository(path: []const u8, repo_path: []const u8) bool {
    // Normalize both paths for comparison
    const normalized_path = fs.path.resolve(std.heap.page_allocator, &.{path}) catch return false;
    defer std.heap.page_allocator.free(normalized_path);
    
    const normalized_repo = fs.path.resolve(std.heap.page_allocator, &.{repo_path}) catch return false;
    defer std.heap.page_allocator.free(normalized_repo);
    
    return std.mem.startsWith(u8, normalized_path, normalized_repo);
}

pub fn canonicalizePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    // Expand ~ to home directory
    if (std.mem.startsWith(u8, path, "~/")) {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch return error.NoHomeDirectory;
        defer allocator.free(home);
        
        return fs.path.join(allocator, &.{ home, path[2..] });
    }
    
    // If already absolute, just duplicate
    if (fs.path.isAbsolute(path)) {
        return allocator.dupe(u8, path);
    }
    
    // Convert relative to absolute
    return fs.cwd().realpathAlloc(allocator, path);
}

pub fn pathExists(path: []const u8) bool {
    fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn isDirectory(path: []const u8) bool {
    const stat = fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

pub fn isRegularFile(path: []const u8) bool {
    const stat = fs.cwd().statFile(path) catch return false;
    return stat.kind == .file;
}


pub const PathInfo = struct {
    exists: bool,
    kind: ?fs.File.Kind,
    is_symlink: bool,
    symlink_target: ?[]const u8,
    
    pub fn deinit(self: PathInfo, allocator: std.mem.Allocator) void {
        if (self.symlink_target) |target| {
            allocator.free(target);
        }
    }
};

pub fn analyzePath(allocator: std.mem.Allocator, path: []const u8) !PathInfo {
    var info = PathInfo{
        .exists = false,
        .kind = null,
        .is_symlink = false,
        .symlink_target = null,
    };
    
    // Check if path exists
    const stat = fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => {
            // Check if it might be a broken symlink
            info.is_symlink = isSymlink(path);
            if (info.is_symlink) {
                info.exists = true;
                info.kind = .sym_link;
                info.symlink_target = resolveSymlinkSource(allocator, path) catch null;
            }
            return info;
        },
        else => return err,
    };
    
    info.exists = true;
    info.kind = stat.kind;
    info.is_symlink = isSymlink(path);
    
    if (info.is_symlink) {
        info.symlink_target = resolveSymlinkSource(allocator, path) catch null;
    }
    
    return info;
}