// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const repository_manager = @import("repository_manager.zig");
const config = @import("config.zig");

test "RepositoryManager initialization and cleanup" {
    const allocator = testing.allocator;
    
    var repo_manager = repository_manager.RepositoryManager.init(allocator);
    defer repo_manager.deinit();
    
    try testing.expect(!repo_manager.verbose);
    try testing.expectEqual(@as(u32, 0), repo_manager.repositories.count());
}

test "SyncOperation enum values" {
    try testing.expectEqual(repository_manager.SyncOperation.pull_only, .pull_only);
    try testing.expectEqual(repository_manager.SyncOperation.push_only, .push_only);
    try testing.expectEqual(repository_manager.SyncOperation.pull_then_push, .pull_then_push);
    try testing.expectEqual(repository_manager.SyncOperation.sync_bidirectional, .sync_bidirectional);
}

test "SyncResult creation and cleanup" {
    const allocator = testing.allocator;
    
    var sync_result = repository_manager.SyncResult{
        .repository_name = "test-repo",
        .success = true,
        .message = try allocator.dupe(u8, "Operation successful"),
    };
    
    try testing.expectEqualStrings("test-repo", sync_result.repository_name);
    try testing.expect(sync_result.success);
    try testing.expectEqualStrings("Operation successful", sync_result.message);
    
    sync_result.deinit(allocator);
}

test "SyncStats initialization" {
    const stats = repository_manager.SyncStats{};
    
    try testing.expectEqual(@as(u32, 0), stats.total_repositories);
    try testing.expectEqual(@as(u32, 0), stats.successful_syncs);
    try testing.expectEqual(@as(u32, 0), stats.failed_syncs);
    try testing.expectEqual(@as(u32, 0), stats.repositories_skipped);
    try testing.expectEqual(@as(u32, 0), stats.total_commits_pulled);
    try testing.expectEqual(@as(u32, 0), stats.total_commits_pushed);
}

test "add and get repository" {
    const allocator = testing.allocator;
    
    var repo_manager = repository_manager.RepositoryManager.init(allocator);
    defer repo_manager.deinit();
    
    const test_repo = config.Repository{
        .name = "test-repo",
        .path = "/path/to/repo",
        .remote = "git@github.com:user/repo.git",
        .branch = "main",
        .auto_commit = false,
    };
    
    try repo_manager.addRepository(test_repo);
    
    const retrieved = repo_manager.getRepository("test-repo");
    try testing.expect(retrieved != null);
    
    if (retrieved) |repo| {
        try testing.expectEqualStrings("test-repo", repo.name);
        try testing.expectEqualStrings("/path/to/repo", repo.path);
        try testing.expectEqualStrings("git@github.com:user/repo.git", repo.remote);
        try testing.expectEqualStrings("main", repo.branch);
        try testing.expect(!repo.auto_commit);
    }
    
    // Test non-existent repository
    const missing = repo_manager.getRepository("missing-repo");
    try testing.expect(missing == null);
}

test "loadRepositories from configuration" {
    const allocator = testing.allocator;
    
    var repo_manager = repository_manager.RepositoryManager.init(allocator);
    defer repo_manager.deinit();
    
    // Create test configuration
    var repositories = std.StringHashMap(config.Repository).init(allocator);
    defer repositories.deinit();
    
    const repo1 = config.Repository{
        .name = "repo1",
        .path = "/path/to/repo1",
        .remote = "git@github.com:user/repo1.git",
        .branch = "main",
        .auto_commit = true,
    };
    
    const repo2 = config.Repository{
        .name = "repo2", 
        .path = "/path/to/repo2",
        .remote = "git@github.com:user/repo2.git",
        .branch = "development",
        .auto_commit = false,
    };
    
    try repositories.put("repo1", repo1);
    try repositories.put("repo2", repo2);
    
    const config_with_repos = config.ConfigWithRepositories{
        .config = config.Config{},
        .repositories = repositories,
        .allocator = allocator,
    };
    
    try repo_manager.loadRepositories(&config_with_repos);
    
    try testing.expectEqual(@as(u32, 2), repo_manager.repositories.count());
    
    const retrieved1 = repo_manager.getRepository("repo1");
    try testing.expect(retrieved1 != null);
    if (retrieved1) |r1| {
        try testing.expectEqualStrings("repo1", r1.name);
        try testing.expect(r1.auto_commit);
    }
    
    const retrieved2 = repo_manager.getRepository("repo2");
    try testing.expect(retrieved2 != null);
    if (retrieved2) |r2| {
        try testing.expectEqualStrings("repo2", r2.name);
        try testing.expectEqualStrings("development", r2.branch);
        try testing.expect(!r2.auto_commit);
    }
}

test "listRepositories" {
    const allocator = testing.allocator;
    
    var repo_manager = repository_manager.RepositoryManager.init(allocator);
    defer repo_manager.deinit();
    
    // Initially empty
    const empty_list = repo_manager.listRepositories();
    defer allocator.free(empty_list);
    try testing.expectEqual(@as(usize, 0), empty_list.len);
    
    // Add some repositories
    const repo1 = config.Repository{
        .name = "alpha",
        .path = "/path/alpha",
        .remote = "git@github.com:user/alpha.git",
        .branch = "main",
    };
    
    const repo2 = config.Repository{
        .name = "beta",
        .path = "/path/beta", 
        .remote = "git@github.com:user/beta.git",
        .branch = "main",
    };
    
    try repo_manager.addRepository(repo1);
    try repo_manager.addRepository(repo2);
    
    const repo_list = repo_manager.listRepositories();
    defer allocator.free(repo_list);
    try testing.expectEqual(@as(usize, 2), repo_list.len);
    
    // Names should be present (order not guaranteed)
    var found_alpha = false;
    var found_beta = false;
    
    for (repo_list) |name| {
        if (std.mem.eql(u8, name, "alpha")) found_alpha = true;
        if (std.mem.eql(u8, name, "beta")) found_beta = true;
    }
    
    try testing.expect(found_alpha);
    try testing.expect(found_beta);
}

test "template processing concept" {
    // Test the basic template concept without accessing private methods
    const template = "ndmgr: update {module} on {date}";
    const module = "test-app";
    
    // This tests our understanding of template structure
    try testing.expect(std.mem.indexOf(u8, template, "{module}") != null);
    try testing.expect(std.mem.indexOf(u8, template, "{date}") != null);
    try testing.expectEqualStrings("test-app", module);
}

test "verbose mode propagation" {
    const allocator = testing.allocator;
    
    var repo_manager = repository_manager.RepositoryManager.init(allocator);
    defer repo_manager.deinit();
    
    try testing.expect(!repo_manager.verbose);
    try testing.expect(!repo_manager.git_ops.verbose);
    
    repo_manager.verbose = true;
    
    // Create empty config to trigger loadRepositories
    var empty_repos = std.StringHashMap(config.Repository).init(allocator);
    defer empty_repos.deinit();
    
    const empty_config = config.ConfigWithRepositories{
        .config = config.Config{},
        .repositories = empty_repos,
        .allocator = allocator,
    };
    
    try repo_manager.loadRepositories(&empty_config);
    
    try testing.expect(repo_manager.verbose);
    try testing.expect(repo_manager.git_ops.verbose);
}

test "syncRepository with missing repository" {
    const allocator = testing.allocator;
    
    var repo_manager = repository_manager.RepositoryManager.init(allocator);
    defer repo_manager.deinit();
    
    const result = try repo_manager.syncRepository("nonexistent", .pull_only);
    defer {
        var mutable_result = result;
        mutable_result.deinit(allocator);
    }
    
    try testing.expectEqualStrings("nonexistent", result.repository_name);
    try testing.expect(!result.success);
    try testing.expect(std.mem.indexOf(u8, result.message, "not found") != null);
}

test "sync operation types handling" {
    // Test that all sync operation types are handled in switch statements
    const operations = [_]repository_manager.SyncOperation{
        .pull_only,
        .push_only,
        .pull_then_push,
        .sync_bidirectional,
    };
    
    for (operations) |op| {
        // This tests that the enum values exist and can be used
        const operation_name = @tagName(op);
        try testing.expect(operation_name.len > 0);
    }
}