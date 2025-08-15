// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const fs = std.fs;
const module_scanner = @import("module_scanner.zig");

test "ModuleScanner.init creates scanner with correct parameters" {
    const allocator = testing.allocator;
    const ignore_patterns = &[_][]const u8{ "*.git", "node_modules" };
    
    const scanner = module_scanner.ModuleScanner.init(allocator, 3, ignore_patterns);
    
    try testing.expect(scanner.scan_depth == 3);
    try testing.expect(scanner.ignore_patterns.len == 2);
    try testing.expect(std.mem.eql(u8, scanner.ignore_patterns[0], "*.git"));
}

test "ModuleScanner.shouldIgnore matches patterns correctly" {
    const allocator = testing.allocator;
    const ignore_patterns = &[_][]const u8{ "*.git", "node_modules", "*.tmp" };
    
    var scanner = module_scanner.ModuleScanner.init(allocator, 3, ignore_patterns);
    
    try testing.expect(scanner.shouldIgnore(".git"));
    try testing.expect(scanner.shouldIgnore("node_modules"));
    try testing.expect(scanner.shouldIgnore("test.tmp"));
    try testing.expect(!scanner.shouldIgnore("src"));
    try testing.expect(!scanner.shouldIgnore("config"));
}

test "ModuleScanner.matchesPattern handles wildcards" {
    const allocator = testing.allocator;
    var scanner = module_scanner.ModuleScanner.init(allocator, 3, &[_][]const u8{});
    
    // Exact match
    try testing.expect(scanner.matchesPattern("test", "test"));
    try testing.expect(!scanner.matchesPattern("test", "other"));
    
    // Prefix wildcard
    try testing.expect(scanner.matchesPattern("file.tmp", "*.tmp"));
    try testing.expect(scanner.matchesPattern("test.tmp", "*.tmp"));
    try testing.expect(!scanner.matchesPattern("file.txt", "*.tmp"));
    
    // Suffix wildcard  
    try testing.expect(scanner.matchesPattern("temp_file", "temp*"));
    try testing.expect(!scanner.matchesPattern("file_temp", "temp*"));
}


test "ModuleScanner.validateModule validates module structure" {
    const allocator = testing.allocator;
    var scanner = module_scanner.ModuleScanner.init(allocator, 3, &[_][]const u8{});
    
    // Create test directory
    const test_dir = "test_module_validation";
    fs.cwd().makeDir(test_dir) catch {};
    defer fs.cwd().deleteTree(test_dir) catch {};
    
    // Create .ndmgr file
    const ndmgr_path = try std.fmt.allocPrint(allocator, "{s}/.ndmgr", .{test_dir});
    defer allocator.free(ndmgr_path);
    
    try fs.cwd().writeFile(.{ .sub_path = ndmgr_path, .data = "target_dir=/test\n" });
    
    var module = module_scanner.ModuleInfo{
        .name = try allocator.dupe(u8, "test"),
        .path = try allocator.dupe(u8, test_dir),
        .config_path = try allocator.dupe(u8, ndmgr_path),
    };
    defer module.deinit(allocator);
    
    // Should validate successfully
    try scanner.validateModule(&module);
    
    // Test with invalid path
    var invalid_module = module_scanner.ModuleInfo{
        .name = try allocator.dupe(u8, "invalid"),
        .path = try allocator.dupe(u8, "nonexistent_path"),
        .config_path = try allocator.dupe(u8, "nonexistent/.ndmgr"),
    };
    defer invalid_module.deinit(allocator);
    
    try testing.expectError(error.ModulePathNotFound, scanner.validateModule(&invalid_module));
}

test "ModuleScanner.sortModulesByName orders alphabetically" {
    const allocator = testing.allocator;
    var scanner = module_scanner.ModuleScanner.init(allocator, 3, &[_][]const u8{});
    
    const module_z = module_scanner.ModuleInfo{
        .name = try allocator.dupe(u8, "zsh_config"),
        .path = try allocator.dupe(u8, "/test/zsh_config"),
        .config_path = try allocator.dupe(u8, "/test/zsh_config/.ndmgr"),
    };
    
    const module_a = module_scanner.ModuleInfo{
        .name = try allocator.dupe(u8, "bash_config"),
        .path = try allocator.dupe(u8, "/test/bash_config"),
        .config_path = try allocator.dupe(u8, "/test/bash_config/.ndmgr"),
    };
    
    var modules = [_]module_scanner.ModuleInfo{ module_z, module_a };
    
    const sorted = try scanner.sortModulesByName(&modules);
    defer {
        allocator.free(sorted);
        for (modules) |module| {
            module.deinit(allocator);
        }
    }
    
    // Should be sorted alphabetically
    try testing.expect(std.mem.eql(u8, sorted[0].name, "bash_config"));
    try testing.expect(std.mem.eql(u8, sorted[1].name, "zsh_config"));
}

test "ModuleInfo.deinit frees all allocated memory" {
    const allocator = testing.allocator;
    
    var module = module_scanner.ModuleInfo{
        .name = try allocator.dupe(u8, "test"),
        .path = try allocator.dupe(u8, "/test/path"),
        .config_path = try allocator.dupe(u8, "/test/path/.ndmgr"),
        .target_dir = try allocator.dupe(u8, "/custom/target"),
    };
    
    // This should not leak memory
    module.deinit(allocator);
}

test "ModuleScanner.parseModuleFile parses target_dir correctly" {
    const allocator = testing.allocator;
    var scanner = module_scanner.ModuleScanner.init(allocator, 3, &[_][]const u8{});
    
    // Create test directory
    const test_dir = "test_target_dir_parsing";
    fs.cwd().makeDir(test_dir) catch {};
    defer fs.cwd().deleteTree(test_dir) catch {};
    
    // Create .ndmgr file with target_dir
    const ndmgr_path = try std.fmt.allocPrint(allocator, "{s}/.ndmgr", .{test_dir});
    defer allocator.free(ndmgr_path);
    
    const config_content = "target_dir=/opt/custom/configs\nignore=true\n";
    try fs.cwd().writeFile(.{ .sub_path = ndmgr_path, .data = config_content });
    
    const module = try scanner.parseModuleFile(ndmgr_path, test_dir, "test_target_dir");
    defer module.deinit(allocator);
    
    // Check that target_dir and ignore were parsed correctly
    try testing.expect(module.target_dir != null);
    try testing.expectEqualStrings("/opt/custom/configs", module.target_dir.?);
    try testing.expect(module.ignore == true);
}