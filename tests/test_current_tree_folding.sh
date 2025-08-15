#!/bin/bash

# Test current tree folding functionality to establish baseline

set -euo pipefail

NDMGR_BINARY="${NDMGR_BINARY:-$(pwd)/zig-out/bin/ndmgr}"
TEST_DIR="/tmp/ndmgr_tree_fold_baseline"

cleanup() {
    rm -rf "$TEST_DIR"
}

setup() {
    cleanup
    mkdir -p "$TEST_DIR"/{source,target,config}
    cd "$TEST_DIR"
    
    # Create config with current default (directory strategy)
    cat > config/config.toml <<EOF
[linking]
conflict_resolution = "fail"
tree_folding = "directory"
backup_conflicts = true
backup_suffix = "bkp"
EOF
    
    # Create test module with nested structure
    mkdir -p source/baseline_test/.config/{app1,app2/subdir}
    echo "app1_main=true" > source/baseline_test/.config/app1/main.conf
    echo "app1_extra=true" > source/baseline_test/.config/app1/extra.conf
    echo "app2_config=true" > source/baseline_test/.config/app2/config.conf
    echo "app2_sub=true" > source/baseline_test/.config/app2/subdir/sub.conf
    echo "target_dir=$TEST_DIR/target" > source/baseline_test/.ndmgr
}

test_directory_folding() {
    echo "=== Testing Current Directory Tree Folding ==="
    
    # Use ignore flag to trigger advanced linker that respects config
    NDMGR_CONFIG_DIR="$TEST_DIR/config" $NDMGR_BINARY --verbose --ignore "*.dummy" --link baseline_test --dir source --target target
    
    echo
    echo "=== Result Analysis ==="
    
    # Check what type of linking occurred
    if [[ -L target/.config ]]; then
        echo "✓ DIRECTORY STRATEGY: Top-level directory folded (.config -> $(readlink target/.config))"
        echo "  Files accessible through directory symlink:"
        find target/.config -type f 2>/dev/null | head -5 || echo "    Error accessing files"
    elif [[ -d target/.config ]]; then
        echo "✓ PARTIAL FOLDING: .config exists as directory, checking subdirectories..."
        find target/.config -type l -exec echo "  Symlinked: {} -> $(readlink {})" \;
        find target/.config -type d -exec echo "  Directory: {}" \;
    else
        echo "? NO FOLDING: Checking individual files..."
        find target -type l -exec echo "  File symlink: {} -> $(readlink {})" \;
    fi
    
    echo
    echo "=== Accessibility Test ==="
    # Test that all files are accessible regardless of folding strategy
    local expected_files=(
        "target/.config/app1/main.conf"
        "target/.config/app1/extra.conf"
        "target/.config/app2/config.conf"
        "target/.config/app2/subdir/sub.conf"
    )
    
    local all_accessible=true
    for file in "${expected_files[@]}"; do
        if [[ -f "$file" ]]; then
            echo "  ✓ $file accessible"
        else
            echo "  ✗ $file NOT accessible"
            all_accessible=false
        fi
    done
    
    if $all_accessible; then
        echo "✓ All files accessible through current folding strategy"
    else
        echo "✗ Some files not accessible - folding issue detected"
        return 1
    fi
}

test_none_strategy() {
    echo
    echo "=== Testing None Strategy (if it exists) ==="
    
    # Clean target and test with 'none' strategy
    rm -rf target/*
    
    # Update config to use 'none' strategy
    cat > config/config.toml <<EOF
[linking]
conflict_resolution = "fail"
tree_folding = "none"
backup_conflicts = true
backup_suffix = "bkp"
EOF
    
    NDMGR_CONFIG_DIR="$TEST_DIR/config" $NDMGR_BINARY --verbose --ignore "*.dummy" --link baseline_test --dir source --target target
    
    echo
    echo "=== None Strategy Result Analysis ==="
    
    if [[ -L target/.config ]] || [[ -L target/.config/app1 ]] || [[ -L target/.config/app2 ]]; then
        echo "✗ NONE STRATEGY FAILED: Found directory symlinks when none should exist"
        find target -type l -name "*config*" -exec echo "  Unexpected directory symlink: {} -> $(readlink {})" \;
    else
        echo "✓ NONE STRATEGY: No directory symlinks found"
        local file_links=$(find target -type l -name "*.conf" | wc -l)
        echo "  Found $file_links individual file symlinks"
        if [[ $file_links -gt 0 ]]; then
            echo "✓ Individual file symlinking working"
        else
            echo "? No file symlinks found - unexpected"
        fi
    fi
}

main() {
    echo "Establishing Tree Folding Baseline..."
    echo "NDMGR Binary: $NDMGR_BINARY"
    echo
    
    setup
    test_directory_folding
    test_none_strategy
    cleanup
    
    echo
    echo "✓ Baseline tree folding test completed!"
}

trap cleanup EXIT
main "$@"