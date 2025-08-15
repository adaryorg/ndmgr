// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");

/// Simple glob pattern matching utility
/// Supports wildcards (*) at start, end, or both
pub fn matchesPattern(name: []const u8, pattern: []const u8) bool {
    // Match everything
    if (std.mem.eql(u8, pattern, "*")) {
        return true;
    }
    
    // Exact match
    if (std.mem.eql(u8, name, pattern)) {
        return true;
    }
    
    // Wildcard patterns
    if (std.mem.endsWith(u8, pattern, "*")) {
        const prefix = pattern[0..pattern.len - 1];
        return std.mem.startsWith(u8, name, prefix);
    }
    
    if (std.mem.startsWith(u8, pattern, "*")) {
        const suffix = pattern[1..];
        return std.mem.endsWith(u8, name, suffix);
    }
    
    // Contains pattern (middle wildcard) - simplified version
    if (std.mem.indexOf(u8, pattern, "*")) |star_pos| {
        const prefix = pattern[0..star_pos];
        const suffix = pattern[star_pos + 1..];
        
        if (prefix.len == 0 and suffix.len == 0) {
            return true; // Just "*"
        }
        if (prefix.len == 0) {
            return std.mem.endsWith(u8, name, suffix);
        }
        if (suffix.len == 0) {
            return std.mem.startsWith(u8, name, prefix);
        }
        
        // Both prefix and suffix exist
        return std.mem.startsWith(u8, name, prefix) and std.mem.endsWith(u8, name, suffix) and name.len >= prefix.len + suffix.len;
    }
    
    return false;
}

// Test the pattern matching utility
test "pattern matching utility" {
    const testing = std.testing;
    
    // Exact match
    try testing.expect(matchesPattern("file.txt", "file.txt"));
    try testing.expect(!matchesPattern("file.txt", "other.txt"));
    
    // Wildcard patterns
    try testing.expect(matchesPattern("file.txt", "*.txt"));
    try testing.expect(matchesPattern("file.txt", "file.*"));
    try testing.expect(matchesPattern("file.txt", "*"));
    try testing.expect(matchesPattern("prefixfile", "*file"));
    
    // No match
    try testing.expect(!matchesPattern("file.txt", "*.log"));
    try testing.expect(!matchesPattern("file.txt", "other.*"));
}