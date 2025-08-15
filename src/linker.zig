// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const pattern_utils = @import("pattern_utils.zig");
const tree_analyzer = @import("tree_analyzer.zig");
const path_utils = @import("path_utils.zig");
const file_utils = @import("file_utils.zig");
const validation_utils = @import("validation_utils.zig");
const cli = @import("cli.zig");

pub const ConflictResolution = enum {
    fail,           // Fail on conflicts (default)
    skip,           // Skip conflicting files
    adopt,          // Move existing files and create symlinks
    replace,        // Replace existing files with symlinks (force mode)
};

pub const TreeFoldingStrategy = enum {
    directory,      // Create directory symlinks when possible
    aggressive,     // More aggressive folding for common patterns
};

pub const LinkerOptions = struct {
    verbose: bool = false,
    ignore_patterns: []const []const u8 = &.{},
    conflict_resolution: ConflictResolution = .fail,
    tree_folding: TreeFoldingStrategy = .directory,
    backup_conflicts: bool = true,
    backup_suffix: []const u8 = "bkp",
    force: cli.ForceMode = .none,
};

pub const LinkingStats = struct {
    files_linked: u32 = 0,
    dirs_linked: u32 = 0,
    files_skipped: u32 = 0,
    conflicts_resolved: u32 = 0,
    files_adopted: u32 = 0,
    backups_created: u32 = 0,
};


pub const Linker = struct {
    allocator: Allocator,
    source_dir: []const u8,
    target_dir: []const u8,
    options: LinkerOptions,
    stats: LinkingStats,

    pub fn init(allocator: Allocator, source_dir: []const u8, target_dir: []const u8, options: LinkerOptions) !Linker {
        try validation_utils.ValidationUtils.validateTargetDirectory(target_dir);
        
        return .{
            .allocator = allocator,
            .source_dir = source_dir,
            .target_dir = target_dir,
            .options = options,
            .stats = .{},
        };
    }


    pub fn link(self: *Linker) !void {
        var source = try fs.openDirAbsolute(self.source_dir, .{ .iterate = true });
        defer source.close();

        // First pass: analyze directory structure for optimal tree folding
        var analyzer = tree_analyzer.TreeAnalyzer.init(self.allocator, self.source_dir, self.target_dir, self.options.tree_folding, self.options.conflict_resolution, self.options.ignore_patterns);
        var tree_analysis = try analyzer.analyzeTreeStructure(source, "");
        defer tree_analysis.deinit();

        // Second pass: perform linking with tree folding optimization
        try self.linkDirectoryWithTreeFolding(source, self.source_dir, self.target_dir, &tree_analysis);
    }


    fn linkDirectoryWithTreeFolding(self: *Linker, dir: fs.Dir, source_path: []const u8, target_path: []const u8, analysis: *tree_analyzer.TreeAnalysis) anyerror!void {
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (try self.shouldIgnore(entry.name)) {
                self.stats.files_skipped += 1;
                continue;
            }

            const source_item = try path_utils.PathUtils.joinPaths(self.allocator, &.{ source_path, entry.name });
            defer self.allocator.free(source_item);

            const target_item = try path_utils.PathUtils.joinPaths(self.allocator, &.{ target_path, entry.name });
            defer self.allocator.free(target_item);

            switch (entry.kind) {
                .directory => {
                    try self.handleDirectoryWithFolding(source_item, target_item, analysis);
                },
                .file, .sym_link => {
                    try self.createSymlink(source_item, target_item);
                },
                else => {},
            }
        }
    }

    fn handleDirectoryWithFolding(self: *Linker, source_path: []const u8, target_path: []const u8, analysis: *tree_analyzer.TreeAnalysis) anyerror!void {
        // Extract relative path for analysis lookup
        const relative_path = source_path[self.source_dir.len + 1..];
        
        // Check if this directory should be folded
        const should_fold = analysis.foldable_dirs.get(relative_path) orelse false;
        
        if (should_fold) {
            try self.createDirectorySymlink(source_path, target_path);
        } else {
            try self.handleDirectoryRecursive(source_path, target_path, analysis);
        }
    }

    fn createDirectorySymlink(self: *Linker, source_path: []const u8, target_path: []const u8) anyerror!void {
        const stat = fs.cwd().statFile(target_path) catch |err| switch (err) {
            error.FileNotFound => {
                const relative_source = try self.makeRelativePath(source_path, target_path);
                defer self.allocator.free(relative_source);
                try file_utils.FileUtils.createSymlink(relative_source, target_path);
                if (self.options.verbose) {
                    std.debug.print("Created directory symlink: {s} -> {s}\n", .{ target_path, relative_source });
                }
                self.stats.dirs_linked += 1;
                return;
            },
            else => return err,
        };

        if (stat.kind == .sym_link) {
            var buf: [fs.max_path_bytes]u8 = undefined;
            if (file_utils.FileUtils.readSymlink(target_path, &buf)) |existing_target| {
                const expected_relative = try self.makeRelativePath(source_path, target_path);
                defer self.allocator.free(expected_relative);
                
                if (std.mem.eql(u8, existing_target, expected_relative)) {
                    if (self.options.verbose) {
                        std.debug.print("Directory symlink already correct: {s} -> {s}\n", .{ target_path, existing_target });
                    }
                    return; // Already correctly linked, nothing to do
                }
            } else |_| {
                // Could not read symlink, fall through to further handling
            }
        }

        // For adopt conflict resolution, handle directory adoption
        if (self.options.conflict_resolution == .adopt and stat.kind == .directory) {
            try self.adoptExistingDirectory(source_path, target_path);
            return;
        }

        // For aggressive tree folding, check if we can safely replace the existing target
        if (self.options.tree_folding == .aggressive) {
            // Create analyzer to check if this target can be folded
            var analyzer = tree_analyzer.TreeAnalyzer.init(self.allocator, self.source_dir, self.target_dir, self.options.tree_folding, self.options.conflict_resolution, self.options.ignore_patterns);
            const can_fold = analyzer.canFoldDirectoryAggressive(target_path, stat) catch false;
            
            if (can_fold) {
                // Safe to replace - remove existing and create symlink
                try file_utils.FileUtils.remove(target_path);
                const relative_source = try self.makeRelativePath(source_path, target_path);
                defer self.allocator.free(relative_source);
                try file_utils.FileUtils.createSymlink(relative_source, target_path);
                if (self.options.verbose) {
                    std.debug.print("Aggressive folding: Replaced directory with symlink: {s} -> {s}\n", .{ target_path, relative_source });
                }
                self.stats.dirs_linked += 1;
                return;
            }
        }

        // Fall back to normal conflict handling
        try self.handleExistingTarget(source_path, target_path, stat);
    }

    fn handleDirectoryRecursive(self: *Linker, source_path: []const u8, target_path: []const u8, analysis: *tree_analyzer.TreeAnalysis) anyerror!void {
        fs.cwd().makeDir(target_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        // Recursively link contents
        var source_subdir = try fs.openDirAbsolute(source_path, .{ .iterate = true });
        defer source_subdir.close();
        
        try self.linkDirectoryWithTreeFolding(source_subdir, source_path, target_path, analysis);
    }

    fn createSymlink(self: *Linker, source_path: []const u8, target_path: []const u8) !void {
        const stat = fs.cwd().statFile(target_path) catch |err| switch (err) {
            error.FileNotFound => {
                const relative_source = try self.makeRelativePath(source_path, target_path);
                defer self.allocator.free(relative_source);
                try file_utils.FileUtils.createSymlink(relative_source, target_path);
                if (self.options.verbose) {
                    std.debug.print("Created symlink: {s} -> {s}\n", .{ target_path, relative_source });
                }
                self.stats.files_linked += 1;
                return;
            },
            else => return err,
        };

        if (stat.kind == .sym_link) {
            var buf: [fs.max_path_bytes]u8 = undefined;
            if (file_utils.FileUtils.readSymlink(target_path, &buf)) |existing_target| {
                const expected_relative = try self.makeRelativePath(source_path, target_path);
                defer self.allocator.free(expected_relative);
                
                if (std.mem.eql(u8, existing_target, expected_relative)) {
                    if (self.options.verbose) {
                        std.debug.print("Symlink already correct: {s} -> {s}\n", .{ target_path, existing_target });
                    }
                    return; // Already correctly linked, nothing to do
                }
            } else |_| {
                // Could not read symlink, fall through to conflict handling
            }
        }

        try self.handleExistingTarget(source_path, target_path, stat);
    }

    fn handleExistingTarget(self: *Linker, source_path: []const u8, target_path: []const u8, stat: fs.File.Stat) !void {
        switch (self.options.conflict_resolution) {
            .fail => {
                std.debug.print("Conflict: {s} already exists\n", .{target_path});
                return error.ConflictDetected;
            },
            .skip => {
                if (self.options.verbose) {
                    std.debug.print("Skipped: {s} (conflict)\n", .{target_path});
                }
                self.stats.files_skipped += 1;
                return;
            },
            .adopt => {
                try self.adoptExistingFile(source_path, target_path, stat);
            },
            .replace => {
                try self.replaceExistingFile(source_path, target_path, stat);
            },
        }
    }

    fn adoptExistingFile(self: *Linker, source_path: []const u8, target_path: []const u8, stat: fs.File.Stat) !void {
        if (stat.kind == .directory) {
            try self.adoptExistingDirectory(source_path, target_path);
        } else {
            try self.adoptExistingRegularFile(source_path, target_path);
        }
    }

    fn adoptExistingRegularFile(self: *Linker, source_path: []const u8, target_path: []const u8) !void {
        if (self.options.backup_conflicts) {
            const backup_path = try file_utils.FileUtils.createBackupWithOptions(self.allocator, target_path, self.options.backup_suffix, self.options.force);
            defer self.allocator.free(backup_path);
            self.stats.backups_created += 1;
            if (self.options.verbose) {
                std.debug.print("Backed up: {s} -> {s}\n", .{ target_path, backup_path });
            }
        } else {
            try file_utils.FileUtils.remove(target_path);
        }

        // Create symlink
        const relative_source = try self.makeRelativePath(source_path, target_path);
        defer self.allocator.free(relative_source);
        try file_utils.FileUtils.createSymlink(relative_source, target_path);
        if (self.options.verbose) {
            std.debug.print("Adopted file: {s} -> {s}\n", .{ target_path, relative_source });
        }
        
        self.stats.files_adopted += 1;
        self.stats.conflicts_resolved += 1;
    }

    fn adoptExistingDirectory(self: *Linker, source_path: []const u8, target_path: []const u8) !void {
        // True adoption: move target content into source, then replace target with symlink
        
        if (self.options.verbose) {
            std.debug.print("Adopting directory: moving target content to source and replacing with symlink\n", .{});
        }
        
        try self.mergeDirectoryIntoSource(target_path, source_path);
        
        if (self.options.backup_conflicts) {
            const backup_path = file_utils.FileUtils.createBackupWithOptions(self.allocator, target_path, self.options.backup_suffix, self.options.force) catch |err| switch (err) {
                error.BackupConflict => {
                    std.debug.print("Directory adoption cancelled due to backup conflict: {s}\n", .{target_path});
                    return error.BackupConflict;
                },
                else => {
                    std.debug.print("Failed to backup directory before adoption: {s}\n", .{target_path});
                    return err;
                },
            };
            defer self.allocator.free(backup_path);
            self.stats.backups_created += 1;
            if (self.options.verbose) {
                std.debug.print("Backed up directory: {s} -> {s}\n", .{ target_path, backup_path });
            }
        }
        
        try file_utils.FileUtils.remove(target_path);
        
        const relative_source = try self.makeRelativePath(source_path, target_path);
        defer self.allocator.free(relative_source);
        try file_utils.FileUtils.createSymlink(relative_source, target_path);
        
        if (self.options.verbose) {
            std.debug.print("Adopted directory: {s} -> {s}\n", .{ target_path, relative_source });
        }
        
        self.stats.dirs_linked += 1;
        self.stats.conflicts_resolved += 1;
    }

    fn mergeDirectoryIntoSource(self: *Linker, target_dir: []const u8, source_dir: []const u8) anyerror!void {
        var target_directory = fs.openDirAbsolute(target_dir, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return, // Target doesn't exist, nothing to merge
            else => return err,
        };
        defer target_directory.close();

        var iterator = target_directory.iterate();
        while (try iterator.next()) |entry| {
            const target_item_path = try path_utils.PathUtils.joinPaths(self.allocator, &.{ target_dir, entry.name });
            defer self.allocator.free(target_item_path);
            
            const source_item_path = try path_utils.PathUtils.joinPaths(self.allocator, &.{ source_dir, entry.name });
            defer self.allocator.free(source_item_path);
            
            switch (entry.kind) {
                .directory => {
                    try self.mergeDirectoryItemIntoSource(target_item_path, source_item_path);
                },
                .file, .sym_link => {
                    try self.mergeFileIntoSource(target_item_path, source_item_path);
                },
                else => {}, // Skip other file types
            }
        }
    }

    fn mergeDirectoryItemIntoSource(self: *Linker, target_item: []const u8, source_item: []const u8) anyerror!void {
        const source_exists = file_utils.FileUtils.exists(source_item);
        
        if (!source_exists) {
            // Non-conflicting directory: copy entire tree from target to source
            try self.copyDirectoryTree(target_item, source_item);
            if (self.options.verbose) {
                std.debug.print("Merged directory: {s} -> {s}\n", .{ target_item, source_item });
            }
        } else {
            // Conflicting directory: recursively merge contents
            try self.mergeDirectoryIntoSource(target_item, source_item);
        }
    }

    fn mergeFileIntoSource(self: *Linker, target_file: []const u8, source_file: []const u8) anyerror!void {
        const source_exists = file_utils.FileUtils.exists(source_file);
        
        if (!source_exists) {
            // Non-conflicting file: copy from target to source
            try self.copyFile(target_file, source_file);
            if (self.options.verbose) {
                std.debug.print("Merged file: {s} -> {s}\n", .{ target_file, source_file });
            }
        } else {
            // Conflicting file: source module wins, nothing to do
            if (self.options.verbose) {
                std.debug.print("Conflict resolved (source wins): {s}\n", .{ source_file });
            }
        }
    }

    fn copyDirectoryTree(self: *Linker, source_path: []const u8, dest_path: []const u8) anyerror!void {
        // Ensure destination directory exists
        try file_utils.FileUtils.ensureDirectoryTree(dest_path);
        
        var source_dir = try fs.openDirAbsolute(source_path, .{ .iterate = true });
        defer source_dir.close();
        
        var iterator = source_dir.iterate();
        while (try iterator.next()) |entry| {
            const source_item = try path_utils.PathUtils.joinPaths(self.allocator, &.{ source_path, entry.name });
            defer self.allocator.free(source_item);
            
            const dest_item = try path_utils.PathUtils.joinPaths(self.allocator, &.{ dest_path, entry.name });
            defer self.allocator.free(dest_item);
            
            switch (entry.kind) {
                .directory => {
                    try self.copyDirectoryTree(source_item, dest_item);
                },
                .file => {
                    try self.copyFile(source_item, dest_item);
                },
                .sym_link => {
                    try self.copySymlink(source_item, dest_item);
                },
                else => {}, // Skip other file types
            }
        }
    }

    fn copyFile(self: *Linker, source_path: []const u8, dest_path: []const u8) anyerror!void {
        _ = self; // Suppress unused parameter warning
        
        // Ensure destination directory exists
        const dest_dir = fs.path.dirname(dest_path) orelse ".";
        try file_utils.FileUtils.ensureDirectoryTree(dest_dir);
        
        // Copy file content
        try fs.cwd().copyFile(source_path, fs.cwd(), dest_path, .{});
    }

    fn copySymlink(self: *Linker, source_path: []const u8, dest_path: []const u8) anyerror!void {
        _ = self; // Suppress unused parameter warning
        
        var buf: [fs.max_path_bytes]u8 = undefined;
        const link_target = try file_utils.FileUtils.readSymlink(source_path, &buf);
        
        // Ensure destination directory exists
        const dest_dir = fs.path.dirname(dest_path) orelse ".";
        try file_utils.FileUtils.ensureDirectoryTree(dest_dir);
        
        // Create symlink at destination
        try file_utils.FileUtils.createSymlink(link_target, dest_path);
    }

    fn replaceExistingFile(self: *Linker, source_path: []const u8, target_path: []const u8, stat: fs.File.Stat) !void {
        _ = stat;
        
        if (self.options.backup_conflicts) {
            const backup_path = try file_utils.FileUtils.createBackupWithOptions(self.allocator, target_path, self.options.backup_suffix, self.options.force);
            defer self.allocator.free(backup_path);
            self.stats.backups_created += 1;
            if (self.options.verbose) {
                std.debug.print("Backed up: {s} -> {s}\n", .{ target_path, backup_path });
            }
        } else {
            try file_utils.FileUtils.remove(target_path);
        }
        
        const relative_source = try self.makeRelativePath(source_path, target_path);
        defer self.allocator.free(relative_source);
        try file_utils.FileUtils.createSymlink(relative_source, target_path);
        
        if (self.options.verbose) {
            std.debug.print("Replaced: {s} -> {s}\n", .{ target_path, relative_source });
        }
        
        self.stats.files_linked += 1;
        self.stats.conflicts_resolved += 1;
    }

    fn makeRelativePath(self: *Linker, source_path: []const u8, target_path: []const u8) ![]const u8 {
        const target_dir = fs.path.dirname(target_path) orelse ".";
        
        // Split both paths into components
        var source_components = std.ArrayList([]const u8).init(self.allocator);
        defer source_components.deinit();
        var target_components = std.ArrayList([]const u8).init(self.allocator);
        defer target_components.deinit();
        
        var source_iter = fs.path.componentIterator(source_path) catch return self.allocator.dupe(u8, source_path);
        while (source_iter.next()) |component| {
            if (component.name.len > 0 and !std.mem.eql(u8, component.name, ".")) {
                try source_components.append(component.name);
            }
        }
        
        var target_iter = fs.path.componentIterator(target_dir) catch return self.allocator.dupe(u8, source_path);
        while (target_iter.next()) |component| {
            if (component.name.len > 0 and !std.mem.eql(u8, component.name, ".")) {
                try target_components.append(component.name);
            }
        }
        
        // Find common prefix
        var common_prefix_len: usize = 0;
        const min_len = @min(source_components.items.len, target_components.items.len);
        while (common_prefix_len < min_len and 
               std.mem.eql(u8, source_components.items[common_prefix_len], target_components.items[common_prefix_len])) {
            common_prefix_len += 1;
        }
        
        // Build relative path
        var relative_parts = std.ArrayList([]const u8).init(self.allocator);
        defer relative_parts.deinit();
        
        const up_levels = target_components.items.len - common_prefix_len;
        for (0..up_levels) |_| {
            try relative_parts.append("..");
        }
        
        for (source_components.items[common_prefix_len..]) |component| {
            try relative_parts.append(component);
        }
        
        // Join the parts
        if (relative_parts.items.len == 0) {
            return self.allocator.dupe(u8, ".");
        }
        
        return path_utils.PathUtils.joinPaths(self.allocator, relative_parts.items);
    }

    pub fn shouldIgnore(self: *const Linker, name: []const u8) !bool {
        // Always ignore .ndmgr configuration files
        if (std.mem.eql(u8, name, ".ndmgr")) {
            return true;
        }

        // Check against ignore patterns
        for (self.options.ignore_patterns) |pattern| {
            if (try self.matchesPattern(name, pattern)) {
                return true;
            }
        }

        return false;
    }

    fn matchesPattern(self: *const Linker, name: []const u8, pattern: []const u8) !bool {
        _ = self;
        return pattern_utils.matchesPattern(name, pattern);
    }

    pub fn unlink(self: *Linker) !void {
        var source = try fs.openDirAbsolute(self.source_dir, .{ .iterate = true });
        defer source.close();

        try self.unlinkDirectory(source, self.source_dir, self.target_dir);
    }

    fn unlinkDirectory(self: *Linker, dir: fs.Dir, source_path: []const u8, target_path: []const u8) anyerror!void {
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (try self.shouldIgnore(entry.name)) continue;

            const source_item = try path_utils.PathUtils.joinPaths(self.allocator, &.{ source_path, entry.name });
            defer self.allocator.free(source_item);

            const target_item = try path_utils.PathUtils.joinPaths(self.allocator, &.{ target_path, entry.name });
            defer self.allocator.free(target_item);

            switch (entry.kind) {
                .directory => {
                    try self.unlinkDirectoryTarget(source_item, target_item);
                },
                .file, .sym_link => {
                    try self.removeSymlink(source_item, target_item);
                },
                else => {},
            }
        }
    }

    fn unlinkDirectoryTarget(self: *Linker, source_path: []const u8, target_path: []const u8) !void {
        var buf: [fs.max_path_bytes]u8 = undefined;
        const link_target = file_utils.FileUtils.readSymlink(target_path, &buf) catch |err| switch (err) {
            error.FileNotFound => return,
            error.NotLink => {
                const stat = fs.cwd().statFile(target_path) catch return;
                if (stat.kind == .directory) {
                    var source_subdir = try fs.openDirAbsolute(source_path, .{ .iterate = true });
                    defer source_subdir.close();
                    try self.unlinkDirectory(source_subdir, source_path, target_path);
                }
                return;
            },
            else => return err,
        };
        
        const expected_relative = try self.makeRelativePath(source_path, target_path);
        defer self.allocator.free(expected_relative);
        
        if (std.mem.eql(u8, link_target, expected_relative)) {
            try fs.cwd().deleteFile(target_path);
            if (self.options.verbose) {
                std.debug.print("Removed directory symlink: {s}\n", .{target_path});
            }
        }
    }

    fn removeSymlink(self: *Linker, source_path: []const u8, target_path: []const u8) !void {
        var buf: [fs.max_path_bytes]u8 = undefined;
        const link_target = file_utils.FileUtils.readSymlink(target_path, &buf) catch return;
        
        const expected_relative = try self.makeRelativePath(source_path, target_path);
        defer self.allocator.free(expected_relative);
        
        if (std.mem.eql(u8, link_target, expected_relative)) {
            try fs.cwd().deleteFile(target_path);
            if (self.options.verbose) {
                std.debug.print("Removed symlink: {s}\n", .{target_path});
            }
        }
    }

    pub fn printStats(self: *Linker) void {
        std.debug.print("\nLinking Statistics:\n", .{});
        std.debug.print("  Files linked: {}\n", .{self.stats.files_linked});
        std.debug.print("  Directories linked: {}\n", .{self.stats.dirs_linked});
        std.debug.print("  Files skipped: {}\n", .{self.stats.files_skipped});
        std.debug.print("  Conflicts resolved: {}\n", .{self.stats.conflicts_resolved});
        std.debug.print("  Files adopted: {}\n", .{self.stats.files_adopted});
        std.debug.print("  Backups created: {}\n", .{self.stats.backups_created});
    }
};

// Helper function to expand tilde and validate target directory
pub fn validateAndExpandTargetDirectory(allocator: Allocator, target_dir: []const u8, context: []const u8) ![]const u8 {
    _ = context; // Suppress unused parameter warning in tests
    return try path_utils.PathUtils.validateAndExpandTargetDirectory(allocator, target_dir);
}