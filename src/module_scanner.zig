// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;
const path_analyzer = @import("path_analyzer.zig");
const pattern_utils = @import("pattern_utils.zig");
const constants = @import("constants.zig");

pub const ModuleInfo = struct {
    name: []const u8,
    path: []const u8,
    config_path: []const u8,
    target_dir: ?[]const u8 = null,
    ignore: bool = false,
    
    pub fn deinit(self: ModuleInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.path);
        allocator.free(self.config_path);
        if (self.target_dir) |target| allocator.free(target);
    }
};

pub const ModuleScanner = struct {
    allocator: std.mem.Allocator,
    scan_depth: u32,
    ignore_patterns: []const []const u8,
    
    pub fn init(allocator: std.mem.Allocator, scan_depth: u32, ignore_patterns: []const []const u8) ModuleScanner {
        return ModuleScanner{
            .allocator = allocator,
            .scan_depth = scan_depth,
            .ignore_patterns = ignore_patterns,
        };
    }
    
    pub fn scanForModules(self: *ModuleScanner, base_path: []const u8) !std.array_list.AlignedManaged(ModuleInfo, null) {
        var modules = std.array_list.AlignedManaged(ModuleInfo, null).init(self.allocator);
        
        try self.scanDirectory(base_path, &modules, 0);
        
        return modules;
    }
    
    fn scanDirectory(self: *ModuleScanner, dir_path: []const u8, modules: *std.array_list.AlignedManaged(ModuleInfo, null), depth: u32) !void {
        if (depth >= self.scan_depth) return;
        
        var dir = fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (self.shouldIgnore(entry.name)) continue;
            
            const entry_path = try fs.path.join(self.allocator, &.{ dir_path, entry.name });
            defer self.allocator.free(entry_path);
            
            switch (entry.kind) {
                .directory => {
                    // Check for .ndmgr file in this directory
                    const ndmgr_file = try fs.path.join(self.allocator, &.{ entry_path, constants.MODULE_CONFIG_FILE });
                    defer self.allocator.free(ndmgr_file);
                    
                    if (path_analyzer.pathExists(ndmgr_file)) {
                        const module_info = try self.parseModuleFile(ndmgr_file, entry_path, entry.name);
                        try modules.append(module_info);
                    } else {
                        // Continue scanning subdirectories
                        try self.scanDirectory(entry_path, modules, depth + 1);
                    }
                },
                else => continue,
            }
        }
    }
    
    pub fn shouldIgnore(self: *ModuleScanner, name: []const u8) bool {
        for (self.ignore_patterns) |pattern| {
            if (self.matchesPattern(name, pattern)) {
                return true;
            }
        }
        return false;
    }
    
    pub fn matchesPattern(self: *ModuleScanner, name: []const u8, pattern: []const u8) bool {
        _ = self;
        return pattern_utils.matchesPattern(name, pattern);
    }
    
    pub fn parseModuleFile(self: *ModuleScanner, config_path: []const u8, module_path: []const u8, module_name: []const u8) !ModuleInfo {
        const content = fs.cwd().readFileAlloc(self.allocator, config_path, 4096) catch |err| switch (err) {
            error.FileNotFound => return error.ModuleConfigNotFound,
            else => return err,
        };
        defer self.allocator.free(content);
        
        var info = ModuleInfo{
            .name = try self.allocator.dupe(u8, module_name),
            .path = try self.allocator.dupe(u8, module_path),
            .config_path = try self.allocator.dupe(u8, config_path),
        };
        
        // Parse simple key=value format for now
        var line_iterator = std.mem.splitScalar(u8, content, '\n');
        while (line_iterator.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            
            if (std.mem.indexOf(u8, trimmed, "=")) |equals_pos| {
                const key = std.mem.trim(u8, trimmed[0..equals_pos], " \t");
                const value = std.mem.trim(u8, trimmed[equals_pos + 1..], " \t\"");
                
                if (std.mem.eql(u8, key, constants.CONFIG_KEY_TARGET_DIR)) {
                    info.target_dir = try self.allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, constants.CONFIG_KEY_IGNORE)) {
                    info.ignore = std.mem.eql(u8, value, constants.BOOL_TRUE);
                }
            }
        }
        
        return info;
    }
    
    
    pub fn validateModule(self: *ModuleScanner, module: *const ModuleInfo) !void {
        _ = self;
        
        // Validate module path exists
        if (!path_analyzer.pathExists(module.path)) {
            return error.ModulePathNotFound;
        }
        
        // Validate module is a directory
        if (!path_analyzer.isDirectory(module.path)) {
            return error.ModulePathNotDirectory;
        }
        
        // Validate config file exists
        if (!path_analyzer.pathExists(module.config_path)) {
            return error.ModuleConfigNotFound;
        }
    }
    
    pub fn checkModuleConflicts(self: *ModuleScanner, module: *const ModuleInfo, target_base: []const u8) !?ConflictInfo {
        
        const target_path = if (module.target_dir) |target_dir|
            try self.allocator.dupe(u8, target_dir)
        else
            try self.allocator.dupe(u8, target_base);
        defer self.allocator.free(target_path);
        
        const module_target = try fs.path.join(self.allocator, &.{ target_path, module.name });
        defer self.allocator.free(module_target);
        
        if (!path_analyzer.pathExists(module_target)) {
            return null; // No conflict
        }
        
        const path_info = try path_analyzer.analyzePath(self.allocator, module_target);
        defer path_info.deinit(self.allocator);
        
        if (path_info.is_symlink) {
            if (path_info.symlink_target) |target| {
                // Check if symlink points to our module
                const canonical_module = try path_analyzer.canonicalizePath(self.allocator, module.path);
                defer self.allocator.free(canonical_module);
                
                const canonical_target = try path_analyzer.canonicalizePath(self.allocator, target);
                defer self.allocator.free(canonical_target);
                
                if (std.mem.eql(u8, canonical_module, canonical_target)) {
                    return null; // Already correctly linked
                }
            }
            
            return ConflictInfo{
                .conflict_type = .existing_symlink,
                .path = try self.allocator.dupe(u8, module_target),
                .target = if (path_info.symlink_target) |t| try self.allocator.dupe(u8, t) else null,
            };
        } else if (path_info.kind == .directory) {
            return ConflictInfo{
                .conflict_type = .existing_directory,
                .path = try self.allocator.dupe(u8, module_target),
                .target = null,
            };
        } else {
            return ConflictInfo{
                .conflict_type = .existing_file,
                .path = try self.allocator.dupe(u8, module_target),
                .target = null,
            };
        }
    }
    
    pub fn sortModulesByName(self: *ModuleScanner, modules: []ModuleInfo) ![]ModuleInfo {
        // Simple alphabetical sort since we no longer have dependencies
        var sorted = std.array_list.AlignedManaged(ModuleInfo, null).init(self.allocator);
        
        for (modules) |module| {
            try sorted.append(module);
        }
        
        // Sort alphabetically by name
        const sorted_slice = try sorted.toOwnedSlice();
        std.mem.sort(ModuleInfo, sorted_slice, {}, compareModuleNames);
        
        return sorted_slice;
    }
    
    fn compareModuleNames(context: void, a: ModuleInfo, b: ModuleInfo) bool {
        _ = context;
        return std.mem.order(u8, a.name, b.name) == .lt;
    }
};

pub const ConflictType = enum {
    existing_symlink,
    existing_directory,
    existing_file,
};

pub const ConflictInfo = struct {
    conflict_type: ConflictType,
    path: []const u8,
    target: ?[]const u8 = null,
    
    pub fn deinit(self: ConflictInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        if (self.target) |target| {
            allocator.free(target);
        }
    }
};