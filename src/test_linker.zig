// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const linker = @import("linker.zig");
const fs = std.fs;

test "Linker initialization" {
    const allocator = testing.allocator;
    
    // Create temporary test directories
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create source and target directories
    try tmp_dir.dir.makePath("source");
    try tmp_dir.dir.makePath("target");
    
    // Get absolute paths
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    
    const source_dir = try fs.path.join(allocator, &.{ tmp_path, "source" });
    defer allocator.free(source_dir);
    
    const target_dir = try fs.path.join(allocator, &.{ tmp_path, "target" });
    defer allocator.free(target_dir);
    
    const options = linker.LinkerOptions{};
    
    const test_linker = try linker.Linker.init(allocator, source_dir, target_dir, options);
    
    try testing.expect(test_linker.allocator.ptr == allocator.ptr);
    try testing.expectEqualStrings(source_dir, test_linker.source_dir);
    try testing.expectEqualStrings(target_dir, test_linker.target_dir);
    try testing.expect(test_linker.options.verbose == false);
}

test "Linker verbose setting" {
    const allocator = testing.allocator;
    
    // Create temporary test directories
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create source and target directories
    try tmp_dir.dir.makePath("source");
    try tmp_dir.dir.makePath("target");
    
    // Get absolute paths
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    
    const source_dir = try fs.path.join(allocator, &.{ tmp_path, "source" });
    defer allocator.free(source_dir);
    
    const target_dir = try fs.path.join(allocator, &.{ tmp_path, "target" });
    defer allocator.free(target_dir);
    
    const options = linker.LinkerOptions{ .verbose = true };
    
    const test_linker = try linker.Linker.init(allocator, source_dir, target_dir, options);
    try testing.expect(test_linker.options.verbose == true);
}

test "Linker with temporary directories" {
    const allocator = testing.allocator;
    
    // Create temporary test directories
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create source directory structure
    try tmp_dir.dir.makePath("source/test_package");
    try tmp_dir.dir.writeFile(.{ .sub_path = "source/test_package/test_file.txt", .data = "test content" });
    
    // Create target directory
    try tmp_dir.dir.makePath("target");
    
    // Get absolute paths
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    
    const source_path = try fs.path.join(allocator, &.{ tmp_path, "source", "test_package" });
    defer allocator.free(source_path);
    
    const target_path = try fs.path.join(allocator, &.{ tmp_path, "target" });
    defer allocator.free(target_path);
    
    // Test linker initialization with real paths
    const options = linker.LinkerOptions{};
    const test_linker = try linker.Linker.init(allocator, source_path, target_path, options);
    
    try testing.expectEqualStrings(source_path, test_linker.source_dir);
    try testing.expectEqualStrings(target_path, test_linker.target_dir);
}

test "Linker error handling for invalid target directory" {
    const allocator = testing.allocator;
    
    // Create temporary test directories
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create source directory but NOT target directory
    try tmp_dir.dir.makePath("source");
    
    // Get absolute paths
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    
    const source_dir = try fs.path.join(allocator, &.{ tmp_path, "source" });
    defer allocator.free(source_dir);
    
    const target_dir = try fs.path.join(allocator, &.{ tmp_path, "nonexistent_target" });
    defer allocator.free(target_dir);
    
    const options = linker.LinkerOptions{};
    
    // This should fail because target directory doesn't exist
    const result = linker.Linker.init(allocator, source_dir, target_dir, options);
    try testing.expectError(error.DirectoryNotFound, result);
}