#!/bin/bash

# Test Phase 1: Verify 'none' strategy removal and directory strategy still works

set -euo pipefail

NDMGR_BINARY="${NDMGR_BINARY:-$(pwd)/zig-out/bin/ndmgr}"
TEST_DIR="/tmp/ndmgr_phase1_test"

cleanup() {
    rm -rf "$TEST_DIR"
}

setup() {
    cleanup
    mkdir -p "$TEST_DIR"/{source,target,config}
    cd "$TEST_DIR"
}

test_directory_strategy_works() {
    echo "=== Phase 1: Testing Directory Strategy Still Works ==="
    
    # Create config with directory strategy (default)
    cat > config/config.toml <<EOF
[linking]
conflict_resolution = "fail"
tree_folding = "directory"
backup_conflicts = true
backup_suffix = "bkp"
EOF
    
    # Create test module
    mkdir -p source/phase1_test/.config/testapp
    echo "config_data=true" > source/phase1_test/.config/testapp/config.conf
    echo "other_data=true" > source/phase1_test/.config/testapp/other.conf
    echo "target_dir=$TEST_DIR/target" > source/phase1_test/.ndmgr
    
    # Test linking
    NDMGR_CONFIG_DIR="$TEST_DIR/config" $NDMGR_BINARY --verbose --ignore "*.dummy" --link phase1_test --dir source --target target
    
    # Verify directory folding occurred
    if [[ -L target/.config ]]; then
        echo "✓ Directory strategy working: .config is symlinked"
        echo "  Points to: $(readlink target/.config)"
        
        # Verify files are accessible
        if [[ -f target/.config/testapp/config.conf ]] && [[ -f target/.config/testapp/other.conf ]]; then
            echo "✓ All files accessible through directory symlink"
        else
            echo "✗ Files not accessible through directory symlink"
            return 1
        fi
    else
        echo "✗ Directory strategy not working - no directory symlink created"
        return 1
    fi
}

test_none_strategy_rejected() {
    echo
    echo "=== Phase 1: Testing 'none' Strategy Rejected ==="
    
    # Clean up previous test
    rm -rf target source  
    mkdir -p source target
    
    # Create config with 'none' strategy (should be rejected)
    cat > config/config.toml <<EOF
[linking]
conflict_resolution = "fail"  
tree_folding = "none"
backup_conflicts = true
backup_suffix = "bkp"
EOF
    
    # Create test module
    mkdir -p source/none_test
    echo "test_data=true" > source/none_test/test.conf
    echo "target_dir=$TEST_DIR/target" > source/none_test/.ndmgr
    
    # Attempt to link - should fail with config parsing error
    if NDMGR_CONFIG_DIR="$TEST_DIR/config" $NDMGR_BINARY --ignore "*.dummy" --link none_test --dir source --target target 2>&1 | grep -q "InvalidValueType\|error parsing"; then
        echo "✓ 'none' strategy correctly rejected by config parser"
    else
        echo "✗ 'none' strategy was not rejected - this is unexpected"
        return 1
    fi
}

test_aggressive_strategy_exists() {
    echo
    echo "=== Phase 1: Testing 'aggressive' Strategy Accepted ==="
    
    # Clean up previous test  
    rm -rf target source
    mkdir -p source target
    
    # Create config with aggressive strategy
    cat > config/config.toml <<EOF
[linking]
conflict_resolution = "fail"
tree_folding = "aggressive"
backup_conflicts = true
backup_suffix = "bkp"  
EOF
    
    # Create test module
    mkdir -p source/aggressive_test/.config/app
    echo "app_config=true" > source/aggressive_test/.config/app/config.conf
    echo "target_dir=$TEST_DIR/target" > source/aggressive_test/.ndmgr
    
    # Test that aggressive strategy is accepted (even if not yet implemented)
    if NDMGR_CONFIG_DIR="$TEST_DIR/config" $NDMGR_BINARY --verbose --ignore "*.dummy" --link aggressive_test --dir source --target target; then
        echo "✓ 'aggressive' strategy accepted by config parser"
        
        # For now, aggressive should behave like directory
        if [[ -L target/.config ]]; then
            echo "✓ Aggressive strategy functioning (currently same as directory)"
        else
            echo "? Aggressive strategy parsed but no folding occurred"
        fi
    else
        echo "✗ 'aggressive' strategy was rejected - this is unexpected"
        return 1
    fi
}

main() {
    echo "Phase 1 Test: Verifying 'none' Strategy Removal"
    echo "NDMGR Binary: $NDMGR_BINARY"
    echo
    
    setup
    test_directory_strategy_works
    test_none_strategy_rejected
    test_aggressive_strategy_exists
    cleanup
    
    echo
    echo "✅ Phase 1 Complete: 'none' strategy removed successfully"
    echo "   - Directory strategy: ✅ Working"
    echo "   - None strategy: ✅ Properly rejected" 
    echo "   - Aggressive strategy: ✅ Accepted (ready for implementation)"
}

trap cleanup EXIT
main "$@"