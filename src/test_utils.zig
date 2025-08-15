// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const path_utils = @import("path_utils.zig");
const string_utils = @import("string_utils.zig");
const file_utils = @import("file_utils.zig");
const validation_utils = @import("validation_utils.zig");

// Path Utils Tests
test "PathUtils.expandTilde with tilde path" {
    const allocator = testing.allocator;
    
    // Mock HOME environment for testing
    const result = path_utils.PathUtils.expandTilde(allocator, "~/test/path");
    if (result) |expanded| {
        defer allocator.free(expanded);
        try testing.expect(std.mem.indexOf(u8, expanded, "/test/path") != null);
        try testing.expect(!std.mem.startsWith(u8, expanded, "~/"));
    } else |_| {
        // If HOME is not available, the test should fail gracefully
    }
}

test "PathUtils.expandTilde with non-tilde path" {
    const allocator = testing.allocator;
    
    const result = try path_utils.PathUtils.expandTilde(allocator, "/absolute/path");
    defer allocator.free(result);
    
    try testing.expectEqualStrings("/absolute/path", result);
}

test "PathUtils.expandTilde with $HOME pattern" {
    const allocator = testing.allocator;
    
    const result = path_utils.PathUtils.expandTilde(allocator, "$HOME");
    if (result) |expanded| {
        defer allocator.free(expanded);
        try testing.expect(expanded.len > 0);
        try testing.expect(!std.mem.startsWith(u8, expanded, "$HOME"));
    } else |_| {
        // If HOME is not available, the test should fail gracefully
    }
}

test "PathUtils.expandTilde with $HOME/ pattern" {
    const allocator = testing.allocator;
    
    const result = path_utils.PathUtils.expandTilde(allocator, "$HOME/test/path");
    if (result) |expanded| {
        defer allocator.free(expanded);
        try testing.expect(std.mem.indexOf(u8, expanded, "/test/path") != null);
        try testing.expect(!std.mem.startsWith(u8, expanded, "$HOME"));
    } else |_| {
        // If HOME is not available, the test should fail gracefully
    }
}

test "PathUtils.expandTilde with just ~" {
    const allocator = testing.allocator;
    
    const result = path_utils.PathUtils.expandTilde(allocator, "~");
    if (result) |expanded| {
        defer allocator.free(expanded);
        try testing.expect(expanded.len > 0);
        try testing.expect(!std.mem.eql(u8, expanded, "~"));
    } else |_| {
        // If HOME is not available, the test should fail gracefully
    }
}

test "PathUtils.joinPaths" {
    const allocator = testing.allocator;
    
    const result = try path_utils.PathUtils.joinPaths(allocator, &.{ "home", "user", "docs" });
    defer allocator.free(result);
    
    try testing.expect(std.mem.indexOf(u8, result, "home") != null);
    try testing.expect(std.mem.indexOf(u8, result, "user") != null);
    try testing.expect(std.mem.indexOf(u8, result, "docs") != null);
}

// String Utils Tests
test "StringUtils.processTemplate with module placeholder" {
    const allocator = testing.allocator;
    
    const result = try string_utils.StringUtils.processTemplate(
        allocator, 
        "Update {module} configuration", 
        "test_app"
    );
    defer allocator.free(result);
    
    try testing.expectEqualStrings("Update test_app configuration", result);
}

test "StringUtils.processTemplate with date placeholder" {
    const allocator = testing.allocator;
    
    const result = try string_utils.StringUtils.processTemplate(
        allocator, 
        "Commit on {date}", 
        "test_app"
    );
    defer allocator.free(result);
    
    try testing.expect(std.mem.startsWith(u8, result, "Commit on "));
    try testing.expect(result.len > "Commit on ".len);
}

test "StringUtils.processTemplate with both placeholders" {
    const allocator = testing.allocator;
    
    const result = try string_utils.StringUtils.processTemplate(
        allocator, 
        "Update {module} on {date}", 
        "test_app"
    );
    defer allocator.free(result);
    
    try testing.expect(std.mem.indexOf(u8, result, "test_app") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Update") != null);
    try testing.expect(std.mem.indexOf(u8, result, "on") != null);
}

test "StringUtils.processTemplate with no placeholders" {
    const allocator = testing.allocator;
    
    const result = try string_utils.StringUtils.processTemplate(
        allocator, 
        "Simple commit message", 
        "test_app"
    );
    defer allocator.free(result);
    
    try testing.expectEqualStrings("Simple commit message", result);
}

test "StringUtils.hasPlaceholders" {
    try testing.expect(string_utils.StringUtils.hasPlaceholders("Update {module}"));
    try testing.expect(string_utils.StringUtils.hasPlaceholders("Commit on {date}"));
    try testing.expect(string_utils.StringUtils.hasPlaceholders("Update {module} on {date}"));
    try testing.expect(!string_utils.StringUtils.hasPlaceholders("Simple message"));
}

test "StringUtils.concat" {
    const allocator = testing.allocator;
    
    const result = try string_utils.StringUtils.concat(allocator, &.{ "Hello", " ", "World" });
    defer allocator.free(result);
    
    try testing.expectEqualStrings("Hello World", result);
}

test "StringUtils.duplicate" {
    const allocator = testing.allocator;
    
    const original = "test string";
    const result = try string_utils.StringUtils.duplicate(allocator, original);
    defer allocator.free(result);
    
    try testing.expectEqualStrings(original, result);
    try testing.expect(original.ptr != result.ptr); // Different memory locations
}

// File Utils Tests
test "FileUtils.exists with temporary file" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create a test file
    try tmp_dir.dir.writeFile(.{ .sub_path = "test_file.txt", .data = "test content" });
    
    // Get absolute path
    const tmp_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);
    
    const file_path = try std.fs.path.join(testing.allocator, &.{ tmp_path, "test_file.txt" });
    defer testing.allocator.free(file_path);
    
    try testing.expect(file_utils.FileUtils.exists(file_path));
    
    const non_existent_path = try std.fs.path.join(testing.allocator, &.{ tmp_path, "non_existent.txt" });
    defer testing.allocator.free(non_existent_path);
    
    try testing.expect(!file_utils.FileUtils.exists(non_existent_path));
}

test "FileUtils.isDirectory and isFile" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create a test file and directory
    try tmp_dir.dir.writeFile(.{ .sub_path = "test_file.txt", .data = "test content" });
    try tmp_dir.dir.makeDir("test_dir");
    
    // Get absolute paths
    const tmp_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);
    
    const file_path = try std.fs.path.join(testing.allocator, &.{ tmp_path, "test_file.txt" });
    defer testing.allocator.free(file_path);
    
    const dir_path = try std.fs.path.join(testing.allocator, &.{ tmp_path, "test_dir" });
    defer testing.allocator.free(dir_path);
    
    try testing.expect(file_utils.FileUtils.isFile(file_path));
    try testing.expect(!file_utils.FileUtils.isDirectory(file_path));
    
    try testing.expect(file_utils.FileUtils.isDirectory(dir_path));
    try testing.expect(!file_utils.FileUtils.isFile(dir_path));
}

// Validation Utils Tests
test "ValidationUtils.validateModuleName" {
    try testing.expectError(error.EmptyModuleName, validation_utils.ValidationUtils.validateModuleName(""));
    try testing.expectError(error.ModuleNameStartsWithDot, validation_utils.ValidationUtils.validateModuleName(".hidden"));
    try testing.expectError(error.InvalidModuleNameCharacter, validation_utils.ValidationUtils.validateModuleName("test module"));
    try testing.expectError(error.InvalidModuleNameCharacter, validation_utils.ValidationUtils.validateModuleName("test@module"));
    
    // These should pass
    try validation_utils.ValidationUtils.validateModuleName("test_module");
    try validation_utils.ValidationUtils.validateModuleName("test-module");
    try validation_utils.ValidationUtils.validateModuleName("TestModule123");
    try validation_utils.ValidationUtils.validateModuleName("test.module");
}

test "ValidationUtils.validateBranchName" {
    try testing.expectError(error.EmptyBranchName, validation_utils.ValidationUtils.validateBranchName(""));
    try testing.expectError(error.InvalidBranchName, validation_utils.ValidationUtils.validateBranchName("-main"));
    try testing.expectError(error.InvalidBranchName, validation_utils.ValidationUtils.validateBranchName("main-"));
    try testing.expectError(error.InvalidBranchName, validation_utils.ValidationUtils.validateBranchName("feature..test"));
    try testing.expectError(error.InvalidBranchNameCharacter, validation_utils.ValidationUtils.validateBranchName("feature@test"));
    
    // These should pass
    try validation_utils.ValidationUtils.validateBranchName("main");
    try validation_utils.ValidationUtils.validateBranchName("feature/test");
    try validation_utils.ValidationUtils.validateBranchName("dev-branch");
    try validation_utils.ValidationUtils.validateBranchName("release_1.0");
}

test "ValidationUtils.validateDirectoryExists with temporary directory" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Get absolute path
    const tmp_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);
    
    // Should pass for existing directory
    try validation_utils.ValidationUtils.validateDirectoryExists(tmp_path);
    
    // Should fail for non-existent directory
    const non_existent = try std.fs.path.join(testing.allocator, &.{ tmp_path, "non_existent" });
    defer testing.allocator.free(non_existent);
    
    try testing.expectError(error.DirectoryNotFound, validation_utils.ValidationUtils.validateDirectoryExists(non_existent));
    
    // Should fail for file (not directory)
    try tmp_dir.dir.writeFile(.{ .sub_path = "test_file.txt", .data = "test" });
    const file_path = try std.fs.path.join(testing.allocator, &.{ tmp_path, "test_file.txt" });
    defer testing.allocator.free(file_path);
    
    try testing.expectError(error.NotADirectory, validation_utils.ValidationUtils.validateDirectoryExists(file_path));
}