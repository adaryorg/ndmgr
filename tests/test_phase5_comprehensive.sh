#!/bin/bash

# Test Phase 5: Comprehensive Testing of Aggressive Tree Folding Implementation

set -euo pipefail

NDMGR_BINARY="${NDMGR_BINARY:-$(pwd)/zig-out/bin/ndmgr}"
TEST_DIR="/tmp/ndmgr_phase5_comprehensive"

cleanup() {
    rm -rf "$TEST_DIR"
}

setup() {
    cleanup
    mkdir -p "$TEST_DIR"/{source,target,config}
    cd "$TEST_DIR"
}

test_basic_aggressive_vs_directory() {
    echo "=== Phase 5: Basic Aggressive vs Directory Strategy ==="
    
    # Create test module
    mkdir -p source/comprehensive/.config/{app1,app2}
    echo "app1_config=true" > source/comprehensive/.config/app1/config.conf
    echo "app2_config=true" > source/comprehensive/.config/app2/config.conf
    echo "target_dir=$TEST_DIR/target" > source/comprehensive/.ndmgr
    
    echo "--- Testing Directory Strategy with Empty Target ---"
    cat > config/config.toml <<EOF
[linking]
conflict_resolution = "fail"
tree_folding = "directory"
backup_conflicts = true
backup_suffix = "bkp"
EOF
    
    NDMGR_CONFIG_DIR="$TEST_DIR/config" $NDMGR_BINARY --ignore "*.dummy" --link comprehensive --dir source --target target
    
    if [[ -L target/.config ]]; then
        echo "✓ Directory strategy: Created directory symlink for empty target"
        local dir_empty_result="folded"
    else
        echo "? Directory strategy: No directory symlink for empty target"
        local dir_empty_result="no_fold"
    fi
    
    # Reset and test with existing empty directory
    rm -rf target source
    mkdir -p source target
    mkdir -p source/comprehensive/.config/{app1,app2}
    echo "app1_config=true" > source/comprehensive/.config/app1/config.conf
    echo "app2_config=true" > source/comprehensive/.config/app2/config.conf
    echo "target_dir=$TEST_DIR/target" > source/comprehensive/.ndmgr
    mkdir -p target/.config  # Empty directory exists
    
    echo "--- Testing Directory Strategy with Existing Empty Directory ---"
    NDMGR_CONFIG_DIR="$TEST_DIR/config" $NDMGR_BINARY --ignore "*.dummy" --link comprehensive --dir source --target target
    
    if [[ -L target/.config ]]; then
        echo "? Directory strategy: Folded existing empty directory (unexpected)"
        local dir_existing_result="folded"
    elif [[ -d target/.config ]] && [[ -L target/.config/app1 ]]; then
        echo "✓ Directory strategy: Conservative - did not fold existing directory"
        local dir_existing_result="no_fold"
    else
        echo "? Directory strategy: Unexpected result"
        local dir_existing_result="unknown"
    fi
    
    # Reset for aggressive test
    rm -rf target source
    mkdir -p source target
    mkdir -p source/comprehensive/.config/{app1,app2}
    echo "app1_config=true" > source/comprehensive/.config/app1/config.conf
    echo "app2_config=true" > source/comprehensive/.config/app2/config.conf
    echo "target_dir=$TEST_DIR/target" > source/comprehensive/.ndmgr
    mkdir -p target/.config  # Empty directory exists
    
    echo "--- Testing Aggressive Strategy with Existing Empty Directory ---"
    cat > config/config.toml <<EOF
[linking]
conflict_resolution = "fail"
tree_folding = "aggressive"
backup_conflicts = true
backup_suffix = "bkp"
EOF
    
    NDMGR_CONFIG_DIR="$TEST_DIR/config" $NDMGR_BINARY --ignore "*.dummy" --link comprehensive --dir source --target target
    
    if [[ -L target/.config ]]; then
        echo "✓ Aggressive strategy: Folded existing empty directory"
        local agg_existing_result="folded"
    elif [[ -d target/.config ]] && [[ -L target/.config/app1 ]]; then
        echo "? Aggressive strategy: Did not fold existing empty directory"  
        local agg_existing_result="no_fold"
    else
        echo "? Aggressive strategy: Unexpected result"
        local agg_existing_result="unknown"
    fi
    
    # Verify the core difference
    if [[ "$dir_existing_result" == "no_fold" ]] && [[ "$agg_existing_result" == "folded" ]]; then
        echo "✅ SUCCESS: Aggressive strategy is more aggressive than directory strategy"
        return 0
    else
        echo "✗ FAIL: No clear difference between strategies"
        echo "  Directory result: $dir_existing_result"
        echo "  Aggressive result: $agg_existing_result"
        return 1
    fi
}

test_aggressive_strategy_safety() {
    echo
    echo "=== Phase 5: Aggressive Strategy Safety Tests ==="
    
    # Clean up
    rm -rf target source
    mkdir -p source target
    
    # Create test module
    mkdir -p source/safety_test/.config/important_app
    echo "important_config=true" > source/safety_test/.config/important_app/critical.conf
    echo "target_dir=$TEST_DIR/target" > source/safety_test/.ndmgr
    
    # Create target with non-empty directory (should NOT be folded)
    mkdir -p target/.config/important_app
    echo "existing_user_data=important" > target/.config/existing_user_file.conf
    
    cat > config/config.toml <<EOF
[linking]
conflict_resolution = "fail"
tree_folding = "aggressive"
backup_conflicts = true
backup_suffix = "bkp"
EOF
    
    echo "--- Testing Aggressive Strategy with Non-Empty Directory ---"
    NDMGR_CONFIG_DIR="$TEST_DIR/config" $NDMGR_BINARY --ignore "*.dummy" --link safety_test --dir source --target target
    
    if [[ -f target/.config/existing_user_file.conf ]] && [[ -L target/.config/important_app ]]; then
        echo "✓ Aggressive strategy: Safely preserved user data and created selective symlinks"
        echo "  ✓ User file preserved: target/.config/existing_user_file.conf"
        echo "  ✓ App symlinked: target/.config/important_app -> source"
        
        # Verify the .config directory itself was NOT folded (which would lose user data)
        if [[ ! -L target/.config ]]; then
            echo "✓ Safety: .config directory correctly NOT folded (preserves user data)"
        else
            echo "✗ Safety violation: .config was folded, user data could be lost"
            return 1
        fi
    else
        echo "✗ Aggressive strategy: Did not preserve user data correctly"
        echo "  User file exists: $(test -f target/.config/existing_user_file.conf && echo 'yes' || echo 'no')"
        echo "  App symlinked: $(test -L target/.config/important_app && echo 'yes' || echo 'no')"
        return 1
    fi
}

test_strategies_with_different_configs() {
    echo
    echo "=== Phase 5: Strategy Configuration Validation ==="
    
    # Clean up
    rm -rf target source
    mkdir -p source target
    
    # Create test module
    mkdir -p source/config_test/.dotfiles
    echo "config_data=true" > source/config_test/.dotfiles/bashrc
    echo "target_dir=$TEST_DIR/target" > source/config_test/.ndmgr
    
    echo "--- Testing 'none' Strategy Rejection ---"
    cat > config/config.toml <<EOF
[linking]
conflict_resolution = "fail"
tree_folding = "none"
backup_conflicts = true
backup_suffix = "bkp"
EOF
    
    if NDMGR_CONFIG_DIR="$TEST_DIR/config" $NDMGR_BINARY --ignore "*.dummy" --link config_test --dir source --target target 2>&1 | grep -q "InvalidValueType\|error parsing"; then
        echo "✓ 'none' strategy correctly rejected by config parser"
    else
        echo "✗ 'none' strategy was not rejected - this is unexpected"
        return 1
    fi
    
    echo "--- Testing 'directory' Strategy Acceptance ---"
    cat > config/config.toml <<EOF
[linking]
conflict_resolution = "fail"
tree_folding = "directory"
backup_conflicts = true
backup_suffix = "bkp"
EOF
    
    if NDMGR_CONFIG_DIR="$TEST_DIR/config" $NDMGR_BINARY --ignore "*.dummy" --link config_test --dir source --target target; then
        echo "✓ 'directory' strategy accepted and functioning"
    else
        echo "✗ 'directory' strategy was rejected - this is unexpected"
        return 1
    fi
    
    # Clean for aggressive test
    rm -rf target
    mkdir -p target
    
    echo "--- Testing 'aggressive' Strategy Acceptance ---"
    cat > config/config.toml <<EOF
[linking]
conflict_resolution = "fail"
tree_folding = "aggressive"
backup_conflicts = true
backup_suffix = "bkp"
EOF
    
    if NDMGR_CONFIG_DIR="$TEST_DIR/config" $NDMGR_BINARY --ignore "*.dummy" --link config_test --dir source --target target; then
        echo "✓ 'aggressive' strategy accepted and functioning"
    else
        echo "✗ 'aggressive' strategy was rejected - this is unexpected"
        return 1
    fi
}

main() {
    echo "Phase 5 Test: Comprehensive Testing of Aggressive Tree Folding"
    echo "NDMGR Binary: $NDMGR_BINARY"
    echo
    
    setup
    test_basic_aggressive_vs_directory
    test_aggressive_strategy_safety
    test_strategies_with_different_configs
    cleanup
    
    echo
    echo "✅ Phase 5 Complete: Comprehensive testing passed"
    echo "   ✅ Aggressive strategy works differently from directory strategy"
    echo "   ✅ Safety measures prevent unsafe operations"
    echo "   ✅ Configuration validation working correctly"
}

trap cleanup EXIT
main "$@"