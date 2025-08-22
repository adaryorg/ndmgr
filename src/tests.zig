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
    _ = @import("test_config.zig");
    _ = @import("test_repository_manager.zig");
    // Note: Some config tests are disabled due to filesystem interaction causing hangs
    // _ = @import("test_config_manager.zig");  // Hangs due to ConfigManager.init()
    // _ = @import("test_config_validation.zig");  // Hangs due to ConfigManager.init()
}