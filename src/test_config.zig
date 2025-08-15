// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const config = @import("config.zig");

test "Config initialization and cleanup" {
    const allocator = testing.allocator;
    
    var test_config = config.ConfigWithRepositories.init(allocator);
    defer test_config.deinit();
    
    try testing.expect(test_config.repositories.count() == 0);
    try testing.expect(test_config.config.deployment.scan_depth == 3);
    try testing.expect(test_config.config.deployment.backup_existing == true);
}

test "ConflictResolution enum values" {
    try testing.expect(config.ConflictResolution.local == .local);
    try testing.expect(config.ConflictResolution.remote == .remote);
    try testing.expect(config.ConflictResolution.ask == .ask);
}

test "ConflictAction enum values" {
    try testing.expect(config.ConflictAction.ask == .ask);
    try testing.expect(config.ConflictAction.adopt == .adopt);
    try testing.expect(config.ConflictAction.skip == .skip);
    try testing.expect(config.ConflictAction.replace == .replace);
}

test "Repository struct initialization" {
    const test_repo = config.Repository{
        .name = "test",
        .path = "/home/user/dotfiles",
        .remote = "origin",
        .branch = "main",
        .auto_commit = true,
    };
    
    try testing.expectEqualStrings("test", test_repo.name);
    try testing.expectEqualStrings("/home/user/dotfiles", test_repo.path);
    try testing.expectEqualStrings("origin", test_repo.remote);
    try testing.expectEqualStrings("main", test_repo.branch);
    try testing.expect(test_repo.auto_commit == true);
}

test "GitConfig default values" {
    const git_config = config.GitConfig{};
    
    try testing.expect(git_config.conflict_resolution == .ask);
    try testing.expectEqualStrings("ndmgr: update {module} on {date}", git_config.commit_message_template);
}

test "DeploymentConfig default values" {
    const deploy_config = config.DeploymentConfig{};
    
    try testing.expect(deploy_config.scan_depth == 3);
    try testing.expect(deploy_config.backup_existing == true);
    try testing.expect(deploy_config.existing_directory == .ask);
    try testing.expect(deploy_config.existing_symlink == .ask);
}

test "Settings default values" {
    const settings = config.Settings{};
    
    try testing.expectEqualStrings("$HOME", settings.default_target);
    try testing.expect(settings.verbose == false);
}

test "Config validation - empty config" {
    const allocator = testing.allocator;
    var test_config = config.ConfigWithRepositories.init(allocator);
    defer test_config.deinit();
    
    // Empty config should be valid
    try config.ConfigManager.validateConfig(&test_config);
}

test "Config validation - invalid repository" {
    const allocator = testing.allocator;
    var test_config = config.ConfigWithRepositories.init(allocator);
    defer test_config.deinit();
    
    // Add invalid repository (empty name)
    const invalid_repo = config.Repository{
        .name = "",  // Invalid: empty name
        .path = "/home/user/dotfiles",
        .remote = "origin",
        .branch = "main",
    };
    
    const key = try allocator.dupe(u8, "test");
    defer allocator.free(key);
    try test_config.repositories.put(key, invalid_repo);
    
    try testing.expectError(error.InvalidRepositoryName, config.ConfigManager.validateConfig(&test_config));
}