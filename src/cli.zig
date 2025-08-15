// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;
const process = std.process;

pub const ForceMode = enum {
    none,      // Not specified, use interactive mode
    default,   // --force without parameter, override conflicts but use defaults for prompts
    yes,       // --force yes, force all prompts to yes
    no,        // --force no, force all prompts to no
};

pub const Action = enum {
    link,
    unlink,
    relink,
    deploy,
    pull,
    push,
    config,
    add_repo,
    init_config,
    status,
    repos,
    info,
    push_all,
    pull_all,
    sync,
    init_repo,
    // Version information
    version,
};

pub const Args = struct {
    action: Action,
    packages: [][]const u8,
    source_dir: []const u8,
    target_dir: []const u8,
    verbose: bool,
    dry_run: bool,
    repository: ?[]const u8 = null,
    force: ForceMode = .none,
    
    // Track if user explicitly specified directories
    explicit_source_dir: bool = false,
    explicit_target_dir: bool = false,
    
    // Ignore patterns for link/unlink operations
    ignore_patterns: [][]const u8 = &.{},
    
    config_key: ?[]const u8 = null,
    repo_name: ?[]const u8 = null,
    repo_path: ?[]const u8 = null,
    repo_remote: ?[]const u8 = null,
    repo_branch: ?[]const u8 = null,
    module_name: ?[]const u8 = null,
    
};

pub fn parseArgs(allocator: std.mem.Allocator) !Args {
    var args_it = try process.argsWithAllocator(allocator);
    defer args_it.deinit();
    
    _ = args_it.next();
    
    var action = Action.link;
    var packages = std.ArrayList([]const u8).init(allocator);
    var source_dir: ?[]const u8 = null;
    var target_dir: ?[]const u8 = null;
    var explicit_source_dir = false;
    var explicit_target_dir = false;
    var verbose = false;
    var dry_run = false;
    var repository: ?[]const u8 = null;
    var force = ForceMode.none;
    
    // Ignore patterns for link/unlink operations
    var ignore_patterns = std.ArrayList([]const u8).init(allocator);
    
    // For handling --force option parsing
    var reprocess_arg: ?[]const u8 = null;
    
    var config_key: ?[]const u8 = null;
    var repo_name: ?[]const u8 = null;
    var repo_path: ?[]const u8 = null;
    var repo_remote: ?[]const u8 = null;
    var repo_branch: ?[]const u8 = null;
    var module_name: ?[]const u8 = null;
    

    while (true) {
        const arg = if (reprocess_arg) |reprocess| blk: {
            reprocess_arg = null;
            break :blk reprocess;
        } else args_it.next() orelse break;
        if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--link")) {
            action = .link;
        } else if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--unlink")) {
            action = .unlink;
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--relink")) {
            action = .relink;
        } else if (std.mem.eql(u8, arg, "--deploy")) {
            action = .deploy;
        } else if (std.mem.eql(u8, arg, "--pull")) {
            action = .pull;
        } else if (std.mem.eql(u8, arg, "--push")) {
            action = .push;
        } else if (std.mem.eql(u8, arg, "--config")) {
            action = .config;
        } else if (std.mem.eql(u8, arg, "--add-repo")) {
            action = .add_repo;
        } else if (std.mem.eql(u8, arg, "--init-config")) {
            action = .init_config;
        } else if (std.mem.eql(u8, arg, "--status")) {
            action = .status;
        } else if (std.mem.eql(u8, arg, "--repos")) {
            action = .repos;
        } else if (std.mem.eql(u8, arg, "--info")) {
            action = .info;
        } else if (std.mem.eql(u8, arg, "--push-all")) {
            action = .push_all;
        } else if (std.mem.eql(u8, arg, "--pull-all")) {
            action = .pull_all;
        } else if (std.mem.eql(u8, arg, "--sync")) {
            action = .sync;
        } else if (std.mem.eql(u8, arg, "--init-repo")) {
            action = .init_repo;
        } else if (std.mem.eql(u8, arg, "--version")) {
            action = .version;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--simulate")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--dir")) {
            source_dir = args_it.next() orelse return error.MissingArgument;
            explicit_source_dir = true;
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--target")) {
            target_dir = args_it.next() orelse return error.MissingArgument;
            explicit_target_dir = true;
        } else if (std.mem.eql(u8, arg, "--repository")) {
            repository = args_it.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--force")) {
            // Check if next argument is a force mode (yes/no)
            const next_arg = args_it.next();
            if (next_arg) |mode| {
                if (std.mem.eql(u8, mode, "yes")) {
                    force = ForceMode.yes;
                } else if (std.mem.eql(u8, mode, "no")) {
                    force = ForceMode.no;
                } else if (std.mem.startsWith(u8, mode, "-")) {
                    // This is another option, not a force mode
                    force = ForceMode.default;
                    // Process this option in the next iteration
                    reprocess_arg = mode;
                } else {
                    // This appears to be a package name, not a force mode
                    force = ForceMode.default;
                    // Treat the argument as a package name
                    try packages.append(mode);
                }
            } else {
                // No argument after --force, use default behavior
                force = ForceMode.default;
            }
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--ignore")) {
            const pattern = args_it.next() orelse return error.MissingArgument;
            try ignore_patterns.append(pattern);
        } else if (std.mem.eql(u8, arg, "--name")) {
            repo_name = args_it.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "--path")) {
            repo_path = args_it.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "--remote")) {
            repo_remote = args_it.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "--branch")) {
            repo_branch = args_it.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "--module")) {
            module_name = args_it.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printHelp();
            process.exit(0);
        } else if (arg[0] == '-') {
            std.debug.print("Unknown option: {s}\n", .{arg});
            process.exit(1);
        } else {
            if (action == .config and config_key == null) {
                config_key = arg;
            } else {
                try packages.append(arg);
            }
        }
    }

    // For specific operations, packages are optional
    if (packages.items.len == 0 and (action == .link or action == .unlink or action == .relink)) {
        std.debug.print("Error: No packages specified\n", .{});
        std.debug.print("\nPackages are directory names containing files to link.\n", .{});
        printHelp();
        process.exit(1);
    }
    
    if (action == .add_repo) {
        if (repo_name == null or repo_path == null or repo_remote == null) {
            std.debug.print("Error: --add-repo requires --name, --path, and --remote\n", .{});
            process.exit(1);
        }
    }

    const cwd_path = try fs.cwd().realpathAlloc(allocator, ".");
    
    const final_source_dir = if (source_dir) |s| 
        try allocator.dupe(u8, s)
    else 
        try allocator.dupe(u8, cwd_path);
        
    const home_dir = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home_dir);
    
    const final_target_dir = if (target_dir) |t|
        try allocator.dupe(u8, t)
    else
        try allocator.dupe(u8, home_dir);
    
    allocator.free(cwd_path);
    
    return Args{
        .action = action,
        .packages = try packages.toOwnedSlice(),
        .source_dir = final_source_dir,
        .target_dir = final_target_dir,
        .verbose = verbose,
        .dry_run = dry_run,
        .repository = repository,
        .force = force,
        .ignore_patterns = try ignore_patterns.toOwnedSlice(),
        .explicit_source_dir = explicit_source_dir,
        .explicit_target_dir = explicit_target_dir,
        .config_key = config_key,
        .repo_name = repo_name,
        .repo_path = repo_path,
        .repo_remote = repo_remote,
        .repo_branch = repo_branch,
        .module_name = module_name,
    };
}

pub fn printVersion() void {
    const version = @import("version");
    const stdout = std.io.getStdOut().writer();
    
    stdout.print(
        \\ndmgr (Nocturne Dotfile Manager) {s}
        \\Git commit: {s}
        \\Built on: {s}
        \\Released under the MIT License: https://opensource.org/licenses/MIT
        \\
    , .{ version.version, version.commit, version.build_time }) catch {};
}

pub fn printHelp() void {
    const home = std.process.getEnvVarOwned(std.heap.page_allocator, "HOME") catch unreachable;
    defer std.heap.page_allocator.free(home);
    
    const stdout = std.io.getStdOut().writer();
    stdout.print(
        \\ndmgr - Nocturne Dotfile Manager
        \\A symlink farm manager with git integration
        \\
        \\Usage: ndmgr [OPTIONS] [PACKAGE...]
        \\
        \\Link/Unlink Operations:
        \\  -l, --link       Link packages (default)
        \\  -u, --unlink     Unlink packages
        \\  -r, --relink     Relink packages (unlink then link)
        \\  -i, --ignore PATTERN  Ignore files matching pattern (can be used multiple times)
        \\
        \\Basic Options:
        \\  -d, --dir DIR    Set source directory (default: current directory)
        \\  -t, --target DIR Set target directory (default: {s})
        \\  -f, --force [yes|no]  Force operation (optional: yes/no for prompts, default overrides conflicts)
        \\  -v, --verbose    Verbose output
        \\  -n, --simulate   Dry run (show what would be done)
        \\  -h, --help       Show this help message
        \\      --version    Show version information
        \\
        \\Git Operations & Repository Management:
        \\      --deploy     Deploy all discovered modules
        \\      --pull       Pull changes from git repositories
        \\      --push       Push changes to git repositories
        \\      --push-all   Push all configured repositories
        \\      --pull-all   Pull all configured repositories
        \\      --sync       Pull all repositories, then deploy all modules
        \\      --init-repo  Initialize a new git repository
        \\      --repository NAME    Specify repository for git operations
        \\      --add-repo           Add new repository (creates backup; requires --name, --path, --remote)
        \\      --name NAME          Repository name (for --add-repo)
        \\      --path PATH          Repository path (for --add-repo)
        \\      --remote URL         Repository remote URL (for --add-repo)
        \\      --branch BRANCH      Repository branch (for --add-repo, default: main)
        \\
        \\Configuration Management:
        \\      --config [KEY]       Show configuration (optionally specific key)
        \\      --init-config        Initialize configuration file (creates backup if repositories exist)
        \\
        \\Information Commands:
        \\      --status             Show system and repository status
        \\      --repos              List all configured repositories
        \\      --info [MODULE]      Show module information (all modules if no name specified)
        \\      --module MODULE      Module name (for --info)
        \\
    , .{home}) catch {};
}
