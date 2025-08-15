// SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
// SPDX-License-Identifier: MIT

const std = @import("std");

// Import test files - Only legitimate unit tests  
test {
    _ = @import("test_cli.zig");
    _ = @import("test_path_analyzer.zig");
    _ = @import("test_linker.zig");
    _ = @import("test_module_scanner.zig");
    _ = @import("pattern_utils.zig");
    _ = @import("test_utils.zig");
    // Note: Config-related tests (test_config.zig, test_repository_manager.zig, 
    // test_config_manager.zig, test_config_validation.zig) are temporarily disabled 
    // due to zig build test hanging issues with toml dependency.
    // These tests pass when run individually with proper dependencies.
}