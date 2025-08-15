// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const linker = @import("linker.zig");
const file_utils = @import("file_utils.zig");
const pattern_utils = @import("pattern_utils.zig");

pub const TreeAnalysis = struct {
    allocator: Allocator,
    foldable_dirs: std.StringHashMap(bool),

    pub fn init(allocator: Allocator) TreeAnalysis {
        return .{
            .allocator = allocator,
            .foldable_dirs = std.StringHashMap(bool).init(allocator),
        };
    }

    pub fn deinit(self: *TreeAnalysis) void {
        var iterator = self.foldable_dirs.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.foldable_dirs.deinit();
    }
};

pub const TreeAnalyzer = struct {
    allocator: Allocator,
    source_dir: []const u8,
    target_dir: []const u8,
    tree_folding_strategy: linker.TreeFoldingStrategy,
    conflict_resolution: linker.ConflictResolution,
    ignore_patterns: []const []const u8,
    
    pub fn init(allocator: Allocator, source_dir: []const u8, target_dir: []const u8, strategy: linker.TreeFoldingStrategy, conflict_resolution: linker.ConflictResolution, ignore_patterns: []const []const u8) TreeAnalyzer {
        return .{
            .allocator = allocator,
            .source_dir = source_dir,
            .target_dir = target_dir,
            .tree_folding_strategy = strategy,
            .conflict_resolution = conflict_resolution,
            .ignore_patterns = ignore_patterns,
        };
    }
    
    pub fn analyzeTreeStructure(self: *TreeAnalyzer, dir: fs.Dir, relative_path: []const u8) !TreeAnalysis {
        var analysis = TreeAnalysis.init(self.allocator);
        
        // Always perform analysis - both directory and aggressive strategies need it
        try self.analyzeDirectoryForFolding(dir, relative_path, &analysis);
        return analysis;
    }
    
    fn analyzeDirectoryForFolding(self: *TreeAnalyzer, dir: fs.Dir, relative_path: []const u8, analysis: *TreeAnalysis) !void {
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (self.shouldIgnore(entry.name)) continue;

            const entry_relative_path = if (relative_path.len == 0) 
                try self.allocator.dupe(u8, entry.name)
            else 
                try fs.path.join(self.allocator, &.{ relative_path, entry.name });
            defer self.allocator.free(entry_relative_path);

            if (entry.kind == .directory) {
                const target_path = try fs.path.join(self.allocator, &.{ self.target_dir, entry_relative_path });
                defer self.allocator.free(target_path);

                // Check if this directory can be folded (symlinked as a whole)
                const can_fold = try self.canFoldDirectory(target_path);
                try analysis.foldable_dirs.put(try self.allocator.dupe(u8, entry_relative_path), can_fold);

                if (!can_fold) {
                    // Recursively analyze subdirectories
                    const source_subdir_path = try fs.path.join(self.allocator, &.{ self.source_dir, entry_relative_path });
                    defer self.allocator.free(source_subdir_path);
                    
                    var subdir = try fs.openDirAbsolute(source_subdir_path, .{ .iterate = true });
                    defer subdir.close();
                    
                    try self.analyzeDirectoryForFolding(subdir, entry_relative_path, analysis);
                }
            }
        }
    }
    
    fn canFoldDirectory(self: *const TreeAnalyzer, target_path: []const u8) !bool {
        const stat = fs.cwd().statFile(target_path) catch |err| switch (err) {
            error.FileNotFound => return true, // Both strategies can fold if target doesn't exist
            else => return err,
        };

        // For adopt strategy, allow folding of directories that match the module being processed
        // This enables directory-level adoption instead of file-by-file adoption
        if (self.conflict_resolution == .adopt and stat.kind == .directory) {
            // Only allow folding if this directory appears to be the main conflict point
            // (heuristic: directory name matches part of the source path)
            const dir_name = fs.path.basename(target_path);
            if (std.mem.indexOf(u8, self.source_dir, dir_name) != null) {
                return true;
            }
        }

        switch (self.tree_folding_strategy) {
            .directory => {
                // Directory strategy: Conservative approach
                return self.canFoldDirectoryConservative(stat);
            },
            .aggressive => {
                // Aggressive strategy: Enhanced analysis
                return self.canFoldDirectoryAggressive(target_path, stat);
            },
        }
    }

    fn canFoldDirectoryConservative(self: *const TreeAnalyzer, stat: fs.File.Stat) bool {
        _ = self;
        // Conservative: only fold if target is symlink, never if it's a regular directory
        switch (stat.kind) {
            .sym_link => return true,
            .directory => return false, // Never fold existing directories
            else => return false,
        }
    }

    pub fn canFoldDirectoryAggressive(self: *const TreeAnalyzer, target_path: []const u8, stat: fs.File.Stat) !bool {
        switch (stat.kind) {
            .sym_link => return true, // Always fold symlinks
            .directory => {
                // Aggressive: Analyze directory content for safe folding opportunities
                return self.analyzeDirectoryForAggressiveFolding(target_path);
            },
            else => return false, // Never fold files or other types
        }
    }

    fn analyzeDirectoryForAggressiveFolding(self: *const TreeAnalyzer, target_path: []const u8) !bool {
        var target_dir = fs.openDirAbsolute(target_path, .{ .iterate = true }) catch return false;
        defer target_dir.close();

        var iterator = target_dir.iterate();
        var total_entries: u32 = 0;
        var symlink_entries: u32 = 0;
        var compatible_symlinks: u32 = 0;

        while (try iterator.next()) |entry| {
            if (self.shouldIgnoreForAnalysis(entry.name)) continue;
            
            total_entries += 1;

            if (entry.kind == .sym_link) {
                symlink_entries += 1;
                
                // Check if symlink points to compatible source
                const entry_path = try fs.path.join(self.allocator, &.{ target_path, entry.name });
                defer self.allocator.free(entry_path);
                
                if (try self.isCompatibleSymlink(entry_path)) {
                    compatible_symlinks += 1;
                }
            }
        }

        // Aggressive folding criteria:
        if (total_entries == 0) {
            return true; // Empty directory - safe to fold
        }
        
        if (symlink_entries == total_entries and compatible_symlinks == symlink_entries) {
            // All entries are compatible symlinks pointing to our source tree
            return true;
        }
        
        // TODO: Add more sophisticated heuristics in the future:
        // - Pattern recognition for common config structures
        // - Depth analysis for deeply nested directories  
        // - Content similarity analysis
        
        return false; // Mixed content - too risky to fold
    }

    fn shouldIgnoreForAnalysis(self: *const TreeAnalyzer, name: []const u8) bool {
        // Check against configured ignore patterns
        for (self.ignore_patterns) |pattern| {
            if (pattern_utils.matchesPattern(name, pattern)) {
                return true;
            }
        }
        return false;
    }

    fn isCompatibleSymlink(self: *const TreeAnalyzer, symlink_path: []const u8) !bool {
        var buf: [fs.max_path_bytes]u8 = undefined;
        const link_target = file_utils.FileUtils.readSymlink(symlink_path, &buf) catch return false;
        
        const abs_link_target = fs.cwd().realpathAlloc(self.allocator, link_target) catch return false;
        defer self.allocator.free(abs_link_target);
        
        const abs_source = try fs.cwd().realpathAlloc(self.allocator, self.source_dir);
        defer self.allocator.free(abs_source);
        
        return std.mem.startsWith(u8, abs_link_target, abs_source);
    }
    
    fn shouldIgnore(self: *TreeAnalyzer, name: []const u8) bool {
        // Check against configured ignore patterns
        for (self.ignore_patterns) |pattern| {
            if (pattern_utils.matchesPattern(name, pattern)) {
                return true;
            }
        }
        return false;
    }
};