// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const testing = std.testing;
const cli = @import("cli.zig");

test "Action enum values" {
    try testing.expect(cli.Action.link == .link);
    try testing.expect(cli.Action.unlink == .unlink);
    try testing.expect(cli.Action.relink == .relink);
}

test "Args struct initialization" {
    const allocator = testing.allocator;
    var packages = [_][]const u8{ "test1", "test2" };
    const source_dir = try allocator.dupe(u8, "/home/user/dotfiles");
    defer allocator.free(source_dir);
    const target_dir = try allocator.dupe(u8, "/home/user");
    defer allocator.free(target_dir);
    
    const args = cli.Args{
        .action = cli.Action.link,
        .packages = &packages,
        .source_dir = source_dir,
        .target_dir = target_dir,
        .verbose = true,
        .dry_run = false,
    };
    
    try testing.expect(args.action == .link);
    try testing.expect(args.packages.len == 2);
    try testing.expectEqualStrings("test1", args.packages[0]);
    try testing.expectEqualStrings("test2", args.packages[1]);
    try testing.expectEqualStrings("/home/user/dotfiles", args.source_dir);
    try testing.expectEqualStrings("/home/user", args.target_dir);
    try testing.expect(args.verbose == true);
    try testing.expect(args.dry_run == false);
}