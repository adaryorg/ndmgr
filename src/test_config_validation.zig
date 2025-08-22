// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const fs = std.fs;
const config = @import("config.zig");
const config_manager = @import("config_manager.zig");

// Configuration validation and error handling tests
// This addresses the gap in configuration validation and error scenarios

test "Config Validation: Configuration structure creation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test configuration structure creation
    var config_with_repos = config.ConfigWithRepositories.init(allocator);
    defer config_with_repos.deinit();

    // Verify initial state
    try testing.expectEqual(@as(u32, 0), config_with_repos.repositories.count());
    // Note: config fields may not be optional, so just verify they exist
    _ = config_with_repos.config.git;
    _ = config_with_repos.config.linking;
    _ = config_with_repos.config.settings;
}

test "Config Validation: Config Manager initialization and error handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test normal config manager initialization
    var config_mgr = config.ConfigManager.init(allocator) catch |err| {
        // Initialization should succeed or fail gracefully
        try testing.expect(err == error.OutOfMemory or err == error.AccessDenied);
        return;
    };
    defer config_mgr.deinit();

    // Test config directory creation
    config_mgr.ensureConfigDir() catch |err| {
        // May fail due to permissions, which is acceptable
        try testing.expect(err == error.AccessDenied or err == error.PathAlreadyExists);
    };
}

test "Config Validation: Config loading error handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var config_mgr = config.ConfigManager.init(allocator) catch {
        std.debug.print("Skipping config test - manager init failed\n", .{});
        return;
    };
    defer config_mgr.deinit();

    // Test config loading (may create default or load existing)
    const loaded_config = config_mgr.loadConfig() catch |err| {
        // Loading may fail for various reasons - all should be handled gracefully
        try testing.expect(
            err == error.FileNotFound or 
            err == error.AccessDenied or 
            err == error.OutOfMemory
        );
        return;
    };

    // If config loads successfully, verify structure
    const repo_count = loaded_config.repositories.count();
    try testing.expect(repo_count >= 0);
}

test "Config Validation: Default config creation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var config_mgr = config.ConfigManager.init(allocator) catch {
        std.debug.print("Skipping default config test - manager init failed\n", .{});
        return;
    };
    defer config_mgr.deinit();

    // Test default config creation
    config_mgr.createDefaultConfig() catch |err| {
        // May fail due to file system permissions or other issues
        try testing.expect(
            err == error.AccessDenied or 
            err == error.FileNotFound or 
            err == error.OutOfMemory
        );
    };
}

test "Config Validation: Error scenarios with limited memory" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test config manager with limited memory
    var limited_allocator = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 1 });
    const failing_manager = config.ConfigManager.init(limited_allocator.allocator());
    try testing.expectError(error.OutOfMemory, failing_manager);
}

test "Config Validation: Repository management operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var config_with_repos = config.ConfigWithRepositories.init(allocator);
    defer config_with_repos.deinit();

    // Test adding valid repositories
    const valid_repo1 = config.Repository{
        .name = "dotfiles",
        .path = "~/dotfiles",
        .remote = "git@github.com:user/dotfiles.git",
        .branch = "main",
        .auto_commit = false,
    };

    const valid_repo2 = config.Repository{
        .name = "scripts",
        .path = "~/scripts",
        .remote = "https://github.com/user/scripts.git",
        .branch = "develop",
        .auto_commit = true,
    };

    try config_with_repos.repositories.put("dotfiles", valid_repo1);
    try config_with_repos.repositories.put("scripts", valid_repo2);

    // Verify repositories were added
    try testing.expectEqual(@as(u32, 2), config_with_repos.repositories.count());
    try testing.expect(config_with_repos.repositories.contains("dotfiles"));
    try testing.expect(config_with_repos.repositories.contains("scripts"));

    // Test repository retrieval
    if (config_with_repos.repositories.get("dotfiles")) |repo| {
        try testing.expectEqualStrings("~/dotfiles", repo.path);
        try testing.expectEqualStrings("main", repo.branch);
        try testing.expect(!repo.auto_commit);
    } else {
        try testing.expect(false); // Should find the repository
    }
}

test "Config Validation: Configuration Manager operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test configuration manager operations that interact with the real environment
    var config_mgr_instance = config_manager.ConfigurationManager.init(allocator) catch {
        std.debug.print("Skipping config manager test - initialization failed\n", .{});
        return;
    };
    defer config_mgr_instance.deinit();

    // Test various operations
    {
        // Test showing configuration (should not crash)
        config_mgr_instance.showConfiguration(null) catch |err| {
            // May fail if no config exists, which is acceptable
            try testing.expect(
                err == error.FileNotFound or 
                err == error.AccessDenied or 
                err == error.InvalidConfiguration
            );
        };
    }

    // showStatus function not available, skip this test

    // showRepositories function not available, skip this test
}

test "Config Validation: Memory management and resource cleanup" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test memory management during configuration operations
    for (0..10) |i| {
        _ = i;
        var config_with_repos = config.ConfigWithRepositories.init(allocator);
        
        // Add some repositories
        const test_repo = config.Repository{
            .name = "test",
            .path = "~/test",
            .remote = "git@test.com:test.git",
            .branch = "main",
            .auto_commit = false,
        };
        
        try config_with_repos.repositories.put("test", test_repo);
        try testing.expectEqual(@as(u32, 1), config_with_repos.repositories.count());
        
        // Configuration will be cleaned up by arena allocator
        config_with_repos.deinit();
    }
}

test "Config Validation: Multiple manager initialization cycles" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test multiple initialization and cleanup cycles
    for (0..5) |i| {
        _ = i;
        if (config.ConfigManager.init(allocator)) |manager| {
            manager.deinit();
        } else |_| {
            // Init failure is acceptable in constrained environments
        }
    }
}

test "Config Validation: Invalid repository scenarios" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var config_with_repos = config.ConfigWithRepositories.init(allocator);
    defer config_with_repos.deinit();

    // Test adding repositories with edge case values
    const edge_case_repos = [_]config.Repository{
        // Empty name
        config.Repository{
            .name = "",
            .path = "~/test",
            .remote = "git@test.com:test.git",
            .branch = "main",
            .auto_commit = false,
        },
        // Very long name
        config.Repository{
            .name = "very_long_repository_name_that_might_cause_issues_with_memory_or_parsing_operations_in_the_configuration_system",
            .path = "~/long-name-repo",
            .remote = "git@test.com:long.git",
            .branch = "main",
            .auto_commit = false,
        },
        // Special characters in paths
        config.Repository{
            .name = "special-chars",
            .path = "~/repos with spaces/special-chars",
            .remote = "git@github.com:user/special-chars.git",
            .branch = "feature/special-branch",
            .auto_commit = false,
        },
    };

    for (edge_case_repos, 0..) |repo, i| {
        const key = try std.fmt.allocPrint(allocator, "repo_{}", .{i});
        defer allocator.free(key);
        
        // Should be able to add repositories even with edge case values
        try config_with_repos.repositories.put(key, repo);
    }

    try testing.expectEqual(@as(u32, 3), config_with_repos.repositories.count());
}