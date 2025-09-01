// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const fs = std.fs;
const cli = @import("cli.zig");
const linker = @import("linker.zig");
const config = @import("config.zig");
const module_scanner = @import("module_scanner.zig");
const error_reporter = @import("error_reporter.zig");

pub const DeploymentResult = struct {
    deployed_count: u32,
    total_count: u32,
    
    pub fn isFullSuccess(self: DeploymentResult) bool {
        return self.deployed_count == self.total_count;
    }
};

pub const DeploymentHandler = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) DeploymentHandler {
        return .{
            .allocator = allocator,
        };
    }
    
    pub fn deploy(self: *DeploymentHandler, args: cli.Args) !DeploymentResult {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        try stdout.print("Starting module deployment...\n", .{});
        
        var setup_data = try self.setupDeployment(args);
        defer self.cleanupSetup(&setup_data);
        
        var modules = try self.scanAndValidateModules(args, &setup_data);
        defer self.cleanupModules(&modules);
        
        if (modules.items.len == 0) {
            try stdout.print("Warning: No modules found in {s}\n", .{args.source_dir});
            return DeploymentResult{ .deployed_count = 0, .total_count = 0 };
        }
        
        // Sort modules
        const sorted_modules = try self.sortModules(&modules, &setup_data.scanner);
        defer self.allocator.free(sorted_modules);
        
        const result = try self.deployModules(args, sorted_modules, &setup_data);
        
        try self.reportResults(result);
        
        return result;
    }
    
    const SetupData = struct {
        cfg_mgr: config.ConfigManager,
        app_config: config.ConfigWithRepositories,
        scanner: module_scanner.ModuleScanner,
        
        pub fn deinit(self: *SetupData) void {
            self.app_config.deinit();
            self.cfg_mgr.deinit();
        }
    };
    
    fn setupDeployment(self: *DeploymentHandler, args: cli.Args) !SetupData {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        const cfg_mgr = try config.ConfigManager.init(self.allocator);
        errdefer cfg_mgr.deinit();
        
        var app_config = try cfg_mgr.loadConfig();
        errdefer app_config.deinit();
        
        const linking_config = app_config.config.linking;
        const scanner = module_scanner.ModuleScanner.init(
            self.allocator,
            linking_config.scan_depth,
            linking_config.ignore_patterns,
        );
        
        if (args.verbose) {
            try stdout.print("Scanning for modules in: {s}\n", .{args.source_dir});
            try stdout.print("Target directory: {s}\n", .{args.target_dir});
        }
        
        return SetupData{
            .cfg_mgr = cfg_mgr,
            .app_config = app_config,
            .scanner = scanner,
        };
    }
    
    fn cleanupSetup(self: *DeploymentHandler, setup_data: *SetupData) void {
        _ = self;
        setup_data.deinit();
    }
    
    fn scanAndValidateModules(self: *DeploymentHandler, args: cli.Args, setup_data: *SetupData) !std.array_list.AlignedManaged(module_scanner.ModuleInfo, null) {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        // Scan for modules
        var modules = setup_data.scanner.scanForModules(args.source_dir) catch |err| {
            error_reporter.ErrorReporter.reportScanningError(err);
            return err;
        };
        errdefer {
            for (modules.items) |module| {
                module.deinit(self.allocator);
            }
            modules.deinit();
        }
        
        try stdout.print("Found {} modules to deploy\n", .{modules.items.len});
        if (args.verbose) {
            for (modules.items) |module| {
                try stdout.print("  - {s} ({s})\n", .{ module.name, module.path });
            }
        }
        
        // Validate all modules
        for (modules.items) |*module| {
            setup_data.scanner.validateModule(module) catch |err| {
                std.debug.print("Invalid module {s}: {}\n", .{ module.name, err });
                continue;
            };
        }
        
        return modules;
    }
    
    fn cleanupModules(self: *DeploymentHandler, modules: *std.array_list.AlignedManaged(module_scanner.ModuleInfo, null)) void {
        for (modules.items) |module| {
            module.deinit(self.allocator);
        }
        modules.deinit();
    }
    
    fn sortModules(self: *DeploymentHandler, modules: *std.array_list.AlignedManaged(module_scanner.ModuleInfo, null), scanner: *module_scanner.ModuleScanner) ![]const module_scanner.ModuleInfo {
        _ = self;
        return scanner.sortModulesByName(modules.items) catch |err| {
            error_reporter.ErrorReporter.reportSortingError(err);
            return err;
        };
    }
    
    fn deployModules(self: *DeploymentHandler, args: cli.Args, sorted_modules: []const module_scanner.ModuleInfo, setup_data: *SetupData) !DeploymentResult {
        var deployed_count: u32 = 0;
        
        for (sorted_modules) |module| {
            const success = try self.deploySingleModule(args, module, setup_data);
            if (success) deployed_count += 1;
        }
        
        return DeploymentResult{
            .deployed_count = deployed_count,
            .total_count = @intCast(sorted_modules.len),
        };
    }
    
    fn deploySingleModule(self: *DeploymentHandler, args: cli.Args, module: module_scanner.ModuleInfo, setup_data: *SetupData) !bool {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        
        // Check if module should be ignored
        if (module.ignore) {
            if (args.verbose) {
                try stdout.print("Skipping module: {s} (ignore=true)\n", .{module.name});
            }
            return true; // Return true to not count as failure, but don't deploy
        }
        
        if (args.verbose) {
            try stdout.print("\nDeploying module: {s}\n", .{module.name});
            if (module.target_dir) |custom_target| {
                try stdout.print("  Using custom target: {s}\n", .{custom_target});
            }
        }
        
        if (args.dry_run) {
            try stdout.print("Dry run: would deploy module {s} from {s}\n", .{ module.name, module.path });
            return true;
        }
        
        // Check for conflicts
        if (try self.checkModuleConflicts(args, module, setup_data)) {
            return false; // Skip module due to conflicts
        }
        
        // Deploy the module
        return try self.performModuleLinking(args, module, setup_data);
    }
    
    fn checkModuleConflicts(self: *DeploymentHandler, args: cli.Args, module: module_scanner.ModuleInfo, setup_data: *SetupData) !bool {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        var scanner = setup_data.scanner;
        
        const conflict = scanner.checkModuleConflicts(&module, args.target_dir) catch |err| {
            std.debug.print("Error checking conflicts for {s}: {}\n", .{ module.name, err });
            return true; // Skip module due to error
        };
        
        if (conflict) |conf| {
            defer conf.deinit(self.allocator);
            
            if (args.force == .none) {
                try stdout.print("Conflict detected for module {s}:\n", .{module.name});
                try stdout.print("  Type: {}\n", .{conf.conflict_type});
                try stdout.print("  Path: {s}\n", .{conf.path});
                if (conf.target) |target| {
                    try stdout.print("  Target: {s}\n", .{target});
                }
                try stdout.print("  Use --force to override or resolve manually\n", .{});
                return true; // Skip module due to conflict
            }
        }
        
        return false; // No conflicts or force enabled
    }
    
    fn performModuleLinking(self: *DeploymentHandler, args: cli.Args, module: module_scanner.ModuleInfo, setup_data: *SetupData) !bool {
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        const target_dir_raw = if (module.target_dir) |custom_target| custom_target else args.target_dir;
        const target_dir = linker.validateAndExpandTargetDirectory(self.allocator, target_dir_raw, module.name) catch |err| {
            if (args.verbose) {
                try stdout.print("Skipping module {s} due to target directory issue: {}\n", .{ module.name, err });
            }
            return false;
        };
        defer self.allocator.free(target_dir);
        
        const abs_target_dir = try fs.cwd().realpathAlloc(self.allocator, target_dir);
        defer self.allocator.free(abs_target_dir);
        
        const abs_module_path = try fs.cwd().realpathAlloc(self.allocator, module.path);
        defer self.allocator.free(abs_module_path);
        
        // Use unified linker for deployment with configuration values
        const linking_config = setup_data.app_config.config.linking;
        const linking_options = linker.LinkerOptions{
            .ignore_patterns = linking_config.ignore_patterns,
            .conflict_resolution = switch (linking_config.conflict_resolution) {
                .fail => linker.ConflictResolution.fail,
                .skip => linker.ConflictResolution.skip,
                .adopt => linker.ConflictResolution.adopt,
                .replace => linker.ConflictResolution.replace,
            },
            .tree_folding = switch (linking_config.tree_folding) {
                .directory => linker.TreeFoldingStrategy.directory,
                .aggressive => linker.TreeFoldingStrategy.aggressive,
            },
            .verbose = args.verbose,
            .backup_conflicts = linking_config.backup_conflicts,
            .backup_suffix = linking_config.backup_suffix,
            .force = args.force,
        };
        
        var pkg_linker = linker.Linker.init(self.allocator, abs_module_path, abs_target_dir, linking_options) catch |err| {
            std.debug.print("Error: Failed to initialize linker for module {s}: {}\n", .{ module.name, err });
            return false;
        };
        
        // Link the module
        pkg_linker.link() catch |err| {
            std.debug.print("Error: Failed to deploy module {s}: {}\n", .{ module.name, err });
            return false;
        };
        
        if (args.verbose) {
            try stdout.print("Successfully deployed module: {s}\n", .{module.name});
        }
        
        return true;
    }
    
    fn reportResults(self: *DeploymentHandler, result: DeploymentResult) !void {
        _ = self;
        var buffer: [1024]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &file_writer.interface;
        if (result.isFullSuccess()) {
            try stdout.print("Deployment completed successfully. Processed {} modules.\n", .{result.deployed_count});
        } else {
            try stdout.print("Warning: Deployment completed with issues. Processed {}/{} modules.\n", .{ result.deployed_count, result.total_count });
        }
    }
};