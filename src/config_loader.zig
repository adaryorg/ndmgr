// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");
const config = @import("config.zig");
const config_manager = @import("config_manager.zig");

pub const ConfigLoader = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ConfigLoader {
        return .{ .allocator = allocator };
    }
    
    pub fn loadConfig(self: *ConfigLoader) !config.ConfigWithRepositories {
        const cfg_mgr = try config.ConfigManager.init(self.allocator);
        defer cfg_mgr.deinit();
        
        return cfg_mgr.loadConfig();
    }
    
    pub fn loadConfigWithManager(self: *ConfigLoader) !struct { config: config.ConfigWithRepositories, manager: config_manager.ConfigurationManager } {
        var cfg_manager = try config_manager.ConfigurationManager.init(self.allocator);
        errdefer cfg_manager.deinit();
        
        var app_config = cfg_manager.config_mgr.loadConfig() catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("Error: Configuration file not found. Use --init-config to create one.\n", .{});
                return err;
            },
            else => return err,
        };
        errdefer app_config.deinit();
        
        return .{ .config = app_config, .manager = cfg_manager };
    }
    
    pub fn loadConfigWithErrorHandling(self: *ConfigLoader) !config.ConfigWithRepositories {
        const cfg_mgr = try config.ConfigManager.init(self.allocator);
        defer cfg_mgr.deinit();
        
        return cfg_mgr.loadConfig() catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("Error: Configuration file not found. Use --init-config to create one.\n", .{});
                return err;
            },
            else => {
                std.debug.print("Error loading configuration: {}\n", .{err});
                return err;
            },
        };
    }
    
    pub fn validateConfigHasRepositories(config_with_repos: *const config.ConfigWithRepositories) !void {
        if (config_with_repos.repositories.count() == 0) {
            std.debug.print("Warning: No repositories configured. Use --add-repo to add repositories.\n", .{});
            return error.NoRepositories;
        }
    }
};