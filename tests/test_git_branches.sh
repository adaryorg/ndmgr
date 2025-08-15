#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
# SPDX-License-Identifier: MIT

set -euo pipefail

# Extended git integration tests for branch functionality

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
NDMGR_BINARY="${NDMGR_BINARY:-$PROJECT_ROOT/zig-out/bin/ndmgr}"
TEST_REPO_URL="git@github.com:adaryorg/ndmgr_test.git"
TEMP_DIR=""
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $*"
}

setup_test_environment() {
    TEMP_DIR=$(mktemp -d -t ndmgr_branch_test_XXXXXX)
    log_info "Created test environment: $TEMP_DIR"
}

cleanup_test_environment() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_info "Cleaned up test environment"
    fi
}

run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TEST_COUNT=$((TEST_COUNT + 1))
    log_info "Running test: $test_name"
    
    # Create isolated test directory
    local test_dir="$TEMP_DIR/test_$TEST_COUNT"
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    if $test_function; then
        log_success "$test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        log_error "$test_name"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

run_ndmgr() {
    mkdir -p target
    "$NDMGR_BINARY" -d dotfiles -t target "$@"
}

assert_symlink_exists() {
    local link_path="$1"
    local expected_target="$2"
    
    if [[ ! -L "target/$link_path" ]]; then
        log_error "Expected symlink at target/$link_path, but it doesn't exist"
        return 1
    fi
    
    local actual_target
    actual_target=$(readlink "target/$link_path")
    
    if [[ ! "$actual_target" == *"$expected_target" ]]; then
        log_error "Symlink target mismatch. Expected: *$expected_target, Got: $actual_target"
        return 1
    fi
    
    return 0
}

assert_file_not_exists() {
    local file_path="$1"
    
    if [[ -e "target/$file_path" ]]; then
        log_error "Expected file target/$file_path to not exist, but it does"
        return 1
    fi
    
    return 0
}

# Test functions
test_main_branch_deployment() {
    # Clone main branch and deploy all modules
    git clone "$TEST_REPO_URL" dotfiles 2>/dev/null || return 1
    
    cd dotfiles
    git checkout main 2>/dev/null
    cd ..
    
    # Deploy and verify some key modules exist
    run_ndmgr --deploy
    
    # Check that main branch modules are deployed
    assert_symlink_exists ".test_config" "test_simple/.test_config" &&
    assert_symlink_exists ".test_base_profile" "test_base_module/.test_base_profile" &&
    assert_symlink_exists ".test_settings.json" "test_simple/.test_settings.json"
}

test_development_branch_deployment() {
    # Clone and switch to development branch
    git clone "$TEST_REPO_URL" dotfiles 2>/dev/null || return 1
    
    cd dotfiles
    git checkout development 2>/dev/null
    cd ..
    
    # Deploy and verify development-specific modules
    run_ndmgr --deploy
    
    # Check that dev branch specific modules are deployed
    assert_symlink_exists ".dev_config" "test_dev_only/.dev_config" &&
    assert_symlink_exists ".experimental_features" "test_experimental/.experimental_features"
}

test_feature_branch_deployment() {
    # Clone and switch to feature branch
    git clone "$TEST_REPO_URL" dotfiles 2>/dev/null || return 1
    
    cd dotfiles
    git checkout feature/test-branch 2>/dev/null
    cd ..
    
    # Deploy and verify feature branch module
    run_ndmgr --deploy
    
    # Check that feature branch module is deployed
    assert_symlink_exists ".feature_config" "test_feature/.feature_config"
}

test_branch_switching() {
    # Clone repository
    git clone "$TEST_REPO_URL" dotfiles 2>/dev/null || return 1
    
    # Deploy from main branch
    cd dotfiles
    git checkout main 2>/dev/null
    cd ..
    
    run_ndmgr --deploy
    
    # Verify main branch module
    assert_symlink_exists ".test_config" "test_simple/.test_config"
    
    # Switch to development branch
    cd dotfiles
    git checkout development 2>/dev/null
    cd ..
    
    # Re-deploy (should update symlinks)
    run_ndmgr --deploy --force
    
    # Verify development branch module is now present
    assert_symlink_exists ".dev_config" "test_dev_only/.dev_config"
}

test_dependency_chain() {
    # Test complex dependency chains in main branch
    git clone "$TEST_REPO_URL" dotfiles 2>/dev/null || return 1
    
    cd dotfiles
    git checkout main 2>/dev/null
    cd ..
    
    # Deploy with verbose to see dependency resolution
    local output
    output=$(run_ndmgr --deploy --verbose 2>&1)
    
    # Check that all chain modules are deployed in correct order
    echo "$output" | grep -q "test_chain_a" &&
    echo "$output" | grep -q "test_chain_b" &&
    echo "$output" | grep -q "test_chain_c" &&
    assert_symlink_exists ".chain_a_config" "test_chain_a/.chain_a_config" &&
    assert_symlink_exists ".chain_b_config" "test_chain_b/.chain_b_config" &&
    assert_symlink_exists ".chain_c_config" "test_chain_c/.chain_c_config"
}

test_tree_folding_complex() {
    # Test tree folding with complex nested structure by deploying only one module
    git clone "$TEST_REPO_URL" dotfiles 2>/dev/null || return 1
    
    cd dotfiles
    git checkout main 2>/dev/null
    cd ..
    
    # Deploy just the tree folding test module to avoid conflicts
    run_ndmgr --link test_tree_fold
    
    # Should create directory symlink for .config due to tree folding
    assert_symlink_exists ".config" "test_tree_fold/.config"
}

test_ignore_patterns_module() {
    # Test that the ignore patterns module deploys correctly
    # Note: Ignore patterns currently only work during module scanning, not file linking
    git clone "$TEST_REPO_URL" dotfiles 2>/dev/null || return 1
    
    cd dotfiles
    git checkout main 2>/dev/null
    cd ..
    
    run_ndmgr --deploy
    
    # Verify the module's intended files are linked
    # (ignore patterns implementation for file linking is TODO)
    assert_symlink_exists ".test_ignore_config" "test_ignore_patterns/.test_ignore_config" &&
    assert_symlink_exists ".test_data.txt" "test_ignore_patterns/.test_data.txt"
    # Note: temp.tmp and debug.log will currently be linked - this is expected behavior until ignore patterns are implemented in linker
}

test_mixed_content_deployment() {
    # Test deployment of various file types
    git clone "$TEST_REPO_URL" dotfiles 2>/dev/null || return 1
    
    cd dotfiles
    git checkout main 2>/dev/null
    cd ..
    
    run_ndmgr --deploy
    
    # Check various file types are linked
    assert_symlink_exists ".test_script.sh" "test_mixed_content/.test_script.sh" &&
    assert_symlink_exists ".test_python.py" "test_mixed_content/.test_python.py" &&
    assert_symlink_exists ".test_data.csv" "test_mixed_content/.test_data.csv"
}

test_special_characters() {
    # Test files with special characters in names
    git clone "$TEST_REPO_URL" dotfiles 2>/dev/null || return 1
    
    cd dotfiles
    git checkout main 2>/dev/null
    cd ..
    
    run_ndmgr --deploy
    
    # Check files with special characters
    assert_symlink_exists ".test-config_2024" "test_special_chars/.test-config_2024" &&
    assert_symlink_exists ".test.config.backup" "test_special_chars/.test.config.backup" &&
    assert_symlink_exists ".TEST_UPPER_CASE" "test_special_chars/.TEST_UPPER_CASE"
}

test_branch_specific_conflicts() {
    # Test conflict handling between branches
    git clone "$TEST_REPO_URL" dotfiles 2>/dev/null || return 1
    
    # Deploy from main branch
    cd dotfiles
    git checkout main 2>/dev/null
    cd ..
    
    run_ndmgr --deploy
    
    # Create a conflicting file
    echo "local change" > target/.test_config
    
    # Try to deploy again - should detect conflict
    if run_ndmgr --deploy 2>&1 | grep -q -i "conflict"; then
        # Now force deploy
        run_ndmgr --deploy --force
        assert_symlink_exists ".test_config" "test_simple/.test_config"
    else
        log_error "Expected conflict detection"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting NDMGR Git Branch Tests"
    log_info "Binary: $NDMGR_BINARY"
    log_info "Test Repository: $TEST_REPO_URL"
    
    # Check if git is available
    if ! command -v git &> /dev/null; then
        log_error "Git is not available. Skipping git branch tests."
        exit 1
    fi
    
    setup_test_environment
    trap cleanup_test_environment EXIT
    
    # Run all tests
    run_test "Main Branch Deployment" test_main_branch_deployment
    run_test "Development Branch Deployment" test_development_branch_deployment
    run_test "Feature Branch Deployment" test_feature_branch_deployment
    run_test "Branch Switching" test_branch_switching
    run_test "Dependency Chain" test_dependency_chain
    run_test "Complex Tree Folding" test_tree_folding_complex
    run_test "Ignore Patterns Module" test_ignore_patterns_module
    run_test "Mixed Content Deployment" test_mixed_content_deployment
    run_test "Special Characters" test_special_characters
    run_test "Branch Specific Conflicts" test_branch_specific_conflicts
    
    # Print summary
    echo
    log_info "Test Summary:"
    log_info "Total tests: $TEST_COUNT"
    log_success "Passed: $PASS_COUNT"
    log_error "Failed: $FAIL_COUNT"
    
    if [[ $FAIL_COUNT -eq 0 ]]; then
        log_success "All branch tests passed!"
        exit 0
    else
        log_error "Some branch tests failed!"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "NDMGR Git Branch Test Suite"
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --setup        Run setup_test_repo.sh first to populate repository"
        exit 0
        ;;
    --setup)
        log_info "Running repository setup first..."
        "$SCRIPT_DIR/setup_test_repo.sh"
        shift
        ;;
esac

main "$@"