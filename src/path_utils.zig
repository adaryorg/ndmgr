// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const common = @import("common_utils.zig");
const constants = @import("constants.zig");

pub const PathUtils = struct {
    /// Expands tilde (~) and $HOME to the user's home directory
    pub fn expandTilde(allocator: Allocator, path: []const u8) ![]const u8 {
        // Handle $HOME pattern
        if (std.mem.eql(u8, path, "$HOME")) {
            return std.process.getEnvVarOwned(allocator, constants.ENV_HOME) catch {
                return error.TildeExpansionFailed;
            };
        }
        
        // Handle $HOME/ pattern
        if (std.mem.startsWith(u8, path, "$HOME/")) {
            const home = std.process.getEnvVarOwned(allocator, constants.ENV_HOME) catch {
                return error.TildeExpansionFailed;
            };
            defer allocator.free(home);
            
            return try std.fmt.allocPrint(allocator, "{s}{s}", .{ home, path[5..] });
        }
        
        // Handle ~ pattern (just ~)
        if (std.mem.eql(u8, path, "~")) {
            return std.process.getEnvVarOwned(allocator, constants.ENV_HOME) catch {
                return error.TildeExpansionFailed;
            };
        }
        
        // Handle ~/ pattern
        if (common.hasPrefix(path, constants.TILDE_PREFIX)) {
            const home = std.process.getEnvVarOwned(allocator, constants.ENV_HOME) catch {
                return error.TildeExpansionFailed;
            };
            defer allocator.free(home);
            
            return try std.fmt.allocPrint(allocator, "{s}{s}", .{ home, path[1..] });
        }
        
        // No expansion needed
        return try common.duplicateString(allocator, path);
    }
    
    /// Gets the user's home directory
    pub fn getHomeDirectory(allocator: Allocator) ![]const u8 {
        return std.process.getEnvVarOwned(allocator, constants.ENV_HOME) catch error.NoHomeDirectory;
    }
    
    /// Joins path components using the platform's path separator
    pub fn joinPaths(allocator: Allocator, paths: []const []const u8) ![]const u8 {
        return try common.joinPaths(allocator, paths);
    }
    
    /// Creates a path relative to the user's home directory
    pub fn makeHomePath(allocator: Allocator, relative_path: []const u8) ![]const u8 {
        const home = try getHomeDirectory(allocator);
        defer allocator.free(home);
        
        return try joinPaths(allocator, &.{ home, relative_path });
    }
    
    /// Creates the default config directory path following XDG Base Directory specification
    /// First tries $XDG_CONFIG_HOME/ndmgr, falls back to $HOME/.config/ndmgr
    pub fn getDefaultConfigDir(allocator: Allocator) ![]const u8 {
        // First try XDG_CONFIG_HOME/ndmgr
        if (std.process.getEnvVarOwned(allocator, constants.ENV_XDG_CONFIG_HOME)) |xdg_config_home| {
            defer allocator.free(xdg_config_home);
            return try joinPaths(allocator, &.{ xdg_config_home, constants.APP_CONFIG_DIR });
        } else |_| {
            // Fall back to $HOME/.config/ndmgr
            const config_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ constants.CONFIG_DIR_NAME, constants.APP_CONFIG_DIR });
            defer allocator.free(config_path);
            return try makeHomePath(allocator, config_path);
        }
    }
    
    /// Validates that a directory exists and is accessible
    pub fn validateDirectory(path: []const u8) !void {
        if (!common.directoryExists(path)) {
            return error.DirectoryNotFound;
        }
    }
    
    /// Validates that a directory exists and is writable
    pub fn validateWritableDirectory(path: []const u8) !void {
        try validateDirectory(path);
        
        fs.cwd().access(path, .{ .mode = .write_only }) catch |err| switch (err) {
            error.PermissionDenied => return error.DirectoryNotWritable,
            else => return err,
        };
    }
    
    /// Expands tilde and validates a target directory
    pub fn validateAndExpandTargetDirectory(allocator: Allocator, target_dir: []const u8) ![]const u8 {
        const expanded_target = try expandTilde(allocator, target_dir);
        errdefer allocator.free(expanded_target);
        
        try validateWritableDirectory(expanded_target);
        
        return expanded_target;
    }
};