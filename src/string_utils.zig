// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const StringUtils = struct {
    /// Template processing for commit messages and other string templates
    pub fn processTemplate(allocator: Allocator, template: []const u8, module: []const u8) ![]const u8 {
        if (std.mem.indexOf(u8, template, "{module}") == null and 
            std.mem.indexOf(u8, template, "{date}") == null) {
            return try allocator.dupe(u8, template);
        }
        
        var message = std.ArrayList(u8).init(allocator);
        defer message.deinit();
        
        var i: usize = 0;
        while (i < template.len) {
            if (template[i] == '{') {
                if (i + 8 <= template.len and std.mem.eql(u8, template[i..i+8], "{module}")) {
                    try message.appendSlice(module);
                    i += 8;
                } else if (i + 6 <= template.len and std.mem.eql(u8, template[i..i+6], "{date}")) {
                    // Get current timestamp and format as YYYY-MM-DD
                    const now = std.time.timestamp();
                    const epoch_secs = @as(u64, @intCast(now));
                    const days_since_epoch = @divFloor(epoch_secs, 86400);
                    
                    // Calculate approximate date (simplified)
                    // This is a rough approximation - not accounting for leap years
                    const year = 1970 + @divFloor(days_since_epoch, 365);
                    const remaining_days = @mod(days_since_epoch, 365);
                    const month = @min(12, 1 + @divFloor(remaining_days, 30));
                    const day = @min(31, 1 + @mod(remaining_days, 30));
                    
                    const date_str = try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{year, month, day});
                    defer allocator.free(date_str);
                    try message.appendSlice(date_str);
                    i += 6;
                } else {
                    try message.append(template[i]);
                    i += 1;
                }
            } else {
                try message.append(template[i]);
                i += 1;
            }
        }
        
        return try message.toOwnedSlice();
    }
    
    /// Checks if a template contains placeholders
    pub fn hasPlaceholders(template: []const u8) bool {
        return std.mem.indexOf(u8, template, "{module}") != null or 
               std.mem.indexOf(u8, template, "{date}") != null;
    }
    
    /// Simple string concatenation utility
    pub fn concat(allocator: Allocator, strings: []const []const u8) ![]const u8 {
        return try std.mem.concat(allocator, u8, strings);
    }
    
    /// Allocates and formats a string using printf-style formatting
    pub fn format(allocator: Allocator, comptime fmt: []const u8, args: anytype) ![]const u8 {
        return try std.fmt.allocPrint(allocator, fmt, args);
    }
    
    /// Duplicates a string
    pub fn duplicate(allocator: Allocator, string: []const u8) ![]const u8 {
        return try allocator.dupe(u8, string);
    }
};