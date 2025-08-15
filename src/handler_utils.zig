// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const config_manager = @import("config_manager.zig");
const git_operation_handler = @import("git_operation_handler.zig");
const repository_manager = @import("repository_manager.zig");
const cli = @import("cli.zig");

/// Helper function to execute code with a ConfigurationManager instance
/// Automatically handles initialization and cleanup
pub fn withConfigManager(allocator: std.mem.Allocator, args: cli.Args, comptime func: fn(*config_manager.ConfigurationManager, cli.Args) anyerror!void) !void {
    var cfg_manager = try config_manager.ConfigurationManager.init(allocator);
    defer cfg_manager.deinit();
    
    try func(&cfg_manager, args);
}

/// Helper function to execute code with a ConfigurationManager instance (no args version)
pub fn withConfigManagerNoArgs(allocator: std.mem.Allocator, comptime func: fn(*config_manager.ConfigurationManager) anyerror!void) !void {
    var cfg_manager = try config_manager.ConfigurationManager.init(allocator);
    defer cfg_manager.deinit();
    
    try func(&cfg_manager);
}

/// Helper function to execute git operations with a GitOperationHandler
pub fn withGitHandler(allocator: std.mem.Allocator, args: cli.Args, operation_type: repository_manager.SyncOperation, description: []const u8) !void {
    var git_handler = git_operation_handler.GitOperationHandler.init(allocator);
    try git_handler.handleRepoOperation(args, operation_type, description);
}

/// Helper function to execute git operations on all repositories
pub fn withGitHandlerAll(allocator: std.mem.Allocator, args: cli.Args, operation_type: repository_manager.SyncOperation, description: []const u8) !void {
    var git_handler = git_operation_handler.GitOperationHandler.init(allocator);
    try git_handler.handleRepoOperationAll(args, operation_type, description);
}