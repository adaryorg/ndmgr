// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;
const constants = @import("constants.zig");
const path_utils = @import("path_utils.zig");

/// Module configuration parsed from .ndmgr files
pub const ModuleConfig = struct {
    description: ?[]const u8 = null,
    target_dir: ?[]const u8 = null,
    
    pub fn deinit(self: *ModuleConfig, allocator: std.mem.Allocator) void {
        if (self.description) |desc| allocator.free(desc);
        if (self.target_dir) |target| allocator.free(target);
    }
};

/// Parse a .ndmgr configuration file
/// Returns null if file doesn't exist, ModuleConfig if parsing succeeds
pub fn parseModuleConfig(allocator: std.mem.Allocator, module_path: []const u8) !?ModuleConfig {
    const ndmgr_path = try fs.path.join(allocator, &.{ module_path, constants.MODULE_CONFIG_FILE });
    defer allocator.free(ndmgr_path);
    
    const content = fs.cwd().readFileAlloc(allocator, ndmgr_path, 4096) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(content);
    
    var config = ModuleConfig{};
    
    // Simple key=value parser (same as handlers.zig for consistency)
    var line_iterator = std.mem.splitScalar(u8, content, '\n');
    
    while (line_iterator.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        
        if (std.mem.indexOf(u8, trimmed, "=")) |equals_pos| {
            const key = std.mem.trim(u8, trimmed[0..equals_pos], " \t");
            const value = std.mem.trim(u8, trimmed[equals_pos + 1..], " \t\"");
            
            if (std.mem.eql(u8, key, "target_dir")) {
                config.target_dir = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "description")) {
                config.description = try allocator.dupe(u8, value);
            }
        }
    }
    
    return config;
}

/// Get the effective target directory for a module
/// Returns the custom target from .ndmgr file if exists, otherwise returns null
pub fn getEffectiveTargetDir(allocator: std.mem.Allocator, module_path: []const u8) !?[]const u8 {
    var config = parseModuleConfig(allocator, module_path) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    } orelse return null;
    defer config.deinit(allocator);
    
    if (config.target_dir) |target| {
        // Expand tilde and environment variables
        const expanded = try path_utils.PathUtils.expandTilde(allocator, target);
        return expanded;
    }
    
    return null;
}