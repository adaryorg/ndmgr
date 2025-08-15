// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");

pub const ErrorReporter = struct {
    pub fn reportError(comptime fmt: []const u8, args: anytype) void {
        std.debug.print("Error: " ++ fmt ++ "\n", args);
    }
    
    pub fn reportWarning(comptime fmt: []const u8, args: anytype) void {
        std.debug.print("Warning: " ++ fmt ++ "\n", args);
    }
    
    pub fn reportConfigNotFound() void {
        reportError("Configuration file not found. Use --init-config to create one.", .{});
    }
    
    pub fn reportNoRepositories() void {
        reportWarning("No repositories configured. Use --add-repo to add repositories.", .{});
    }
    
    pub fn reportLinkerInitError(package: []const u8, err: anytype) void {
        reportError("Failed to initialize linker for package {s}: {}", .{ package, err });
    }
    
    pub fn reportModuleDeployError(module: []const u8, err: anytype) void {
        reportError("Failed to deploy module {s}: {}", .{ module, err });
    }
    
    pub fn reportModuleConflictError(module: []const u8, err: anytype) void {
        reportError("Error checking conflicts for {s}: {}", .{ module, err });
    }
    
    pub fn reportScanningError(err: anytype) void {
        reportError("Error scanning for modules: {}", .{err});
    }
    
    pub fn reportSortingError(err: anytype) void {
        reportError("Error sorting modules: {}", .{err});
    }
    
    pub fn reportGitInitError(err: anytype) void {
        reportError("Error running git init: {}", .{err});
    }
    
    pub fn reportGitInitFailed(stderr: []const u8) void {
        reportError("Git init failed: {s}", .{stderr});
    }
    
    pub fn reportSymlinkRemovalError(package: []const u8, err: anytype) void {
        reportError("Could not remove symlink {s}: {}", .{ package, err });
    }
    
    pub fn reportInvalidModuleType(package: []const u8) void {
        reportError("'{s}' is neither a symbolic link nor a directory", .{package});
    }
    
    pub fn reportHomeDirectoryError() void {
        reportError("Unable to get HOME directory", .{});
    }
    
    pub fn reportTildeExpansionError() void {
        reportError("Unable to expand ~ in target_dir", .{});
    }
    
    pub fn reportConfigLoadError(err: anytype) void {
        reportError("Error loading configuration: {}", .{err});
    }
    
    pub fn reportConfigWriteError(err: anytype) void {
        reportError("Error opening config file for writing: {}", .{err});
    }
    
    pub fn reportModuleScanError(err: anytype) void {
        std.debug.print("\nModule Scan: Error - {}\n", .{err});
    }
};