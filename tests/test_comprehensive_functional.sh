#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
# SPDX-License-Identifier: MIT

set -euo pipefail

# Comprehensive functional testing using both test repositories
# Tests all CLI options, git operations, and real scenarios with mock data

# No colors - simple text output for dotfile manager

# Test configuration  
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
NDMGR_BINARY="${NDMGR_BINARY:-$PROJECT_ROOT/zig-out/bin/ndmgr}"
TEST_REPO1_URL="git@github.com:adaryorg/ndmgr_test.git"
TEST_REPO2_URL="git@github.com:adaryorg/ndmgr_test2.git"
TEMP_DIR=""
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Utility functions
log_info() {
    echo "[INFO] $*"
}

log_success() {
    echo "[PASS] $*"
}

log_error() {
    echo "[FAIL] $*"
}

log_warning() {
    echo "[SKIP] $*"
}

setup_test_environment() {
    TEMP_DIR=$(mktemp -d -t ndmgr_comprehensive_test_XXXXXX)
    log_info "Created test environment: $TEMP_DIR"
    
    # Build ndmgr if binary doesn't exist
    if [[ ! -x "$NDMGR_BINARY" ]]; then
        log_info "Building ndmgr binary..."
        cd "$PROJECT_ROOT"
        zig build
        cd -
    fi
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

skip_test() {
    local test_name="$1"
    local reason="$2"
    
    TEST_COUNT=$((TEST_COUNT + 1))
    SKIP_COUNT=$((SKIP_COUNT + 1))
    log_warning "$test_name - $reason"
}

# Helper functions
run_ndmgr() {
    mkdir -p target
    "$NDMGR_BINARY" -d dotfiles -t target "$@"
}

create_generic_module() {
    local module_name="$1"
    local config_content="$2"
    shift 2
    
    mkdir -p "dotfiles/$module_name"
    echo -e "$config_content" > "dotfiles/$module_name/.ndmgr"
    
    while [[ $# -gt 0 ]]; do
        local file_path="$1"
        local file_content="$2"
        shift 2
        
        local full_path="dotfiles/$module_name/$file_path"
        mkdir -p "$(dirname "$full_path")"
        echo -e "$file_content" > "$full_path"
    done
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

# === CLI COMMAND COMPREHENSIVE TESTS ===

test_all_cli_help_options() {
    # Test all help variations
    local help_variants=("--help" "-h")
    
    for variant in "${help_variants[@]}"; do
        local output
        output=$(run_ndmgr "$variant" 2>&1) || return 1
        
        if ! echo "$output" | grep -q "ndmgr"; then
            log_error "Help output for $variant doesn't contain 'ndmgr'"
            return 1
        fi
    done
    
    return 0
}

test_all_linking_command_combinations() {
    # Create test modules with generic names
    create_generic_module "shell_config" \
        "description=\"Generic shell configuration\"" \
        ".shellrc" "export SHELL_CONFIG=loaded" \
        ".shell_profile" "source ~/.shellrc"
    
    create_generic_module "editor_config" \
        "description=\"Generic editor configuration\"" \
        ".editorrc" "set number\nset autoindent" \
        ".editor_themes/dark.theme" "background=dark"
    
    create_generic_module "terminal_config" \
        "description=\"Generic terminal configuration\"" \
        ".terminalrc" "color_scheme=solarized" \
        ".terminal/fonts.conf" "font_size=12"
    
    # Test various linking command combinations
    local link_commands=(
        "--link shell_config"
        "--link --verbose shell_config"
        "--link --simulate shell_config"
        "--link --force shell_config"
        "--link --verbose --simulate shell_config"
        "--link shell_config editor_config"
        "--link --verbose shell_config editor_config terminal_config"
    )
    
    for cmd in "${link_commands[@]}"; do
        run_ndmgr $cmd || return 1
        run_ndmgr --delete shell_config editor_config terminal_config 2>/dev/null || true
    done
    
    return 0
}

test_advanced_linking_combinations() {
    create_generic_module "advanced_test" \
        "description=\"Advanced linking test module\"" \
        ".config/app/config.yml" "app: advanced" \
        ".data/cache.db" "cache_data" \
        "temp.log" "ignore_me" \
        "backup.bak" "ignore_me_too"
    
    # Test all advanced linking combinations
    local advanced_commands=(
        "--advanced --link advanced_test"
        "--advanced --conflict-resolution skip --link advanced_test"
        "--advanced --conflict-resolution adopt --link advanced_test"
        "--advanced --conflict-resolution replace --link advanced_test"
        "--advanced --tree-folding none --link advanced_test"
        "--advanced --tree-folding directory --link advanced_test"  
        "--advanced --tree-folding aggressive --link advanced_test"
        "--advanced --backup --link advanced_test"
        "--advanced --backup --backup-suffix .test.bak --link advanced_test"
        "--advanced --ignore '*.log' --ignore '*.bak' --link advanced_test"
        "--advanced --verbose --simulate --conflict-resolution skip --tree-folding aggressive --backup --ignore '*.log' --link advanced_test"
    )
    
    for cmd in "${advanced_commands[@]}"; do
        # Create conflicting file for some tests
        mkdir -p target/.config/app
        echo "existing" > target/.config/app/config.yml
        
        run_ndmgr $cmd || return 1
        
        # Cleanup
        rm -rf target/*
    done
    
    return 0
}

test_deployment_command_combinations() {
    create_generic_module "deploy_module1" \
        "description=\"First deployment test module\"" \
        ".deploy_config1" "module1=active"
    
    create_generic_module "deploy_module2" \
        "description=\"Second deployment test module\"\ndependencies=[\"deploy_module1\"]" \
        ".deploy_config2" "module2=active"
    
    # Test deployment commands
    local deploy_commands=(
        "--deploy"
        "--deploy --verbose"
        "--deploy --simulate"
        "--deploy --force"
        "--deploy --verbose --simulate"
        "--deploy --advanced"
        "--deploy --advanced --verbose --conflict-resolution adopt"
    )
    
    for cmd in "${deploy_commands[@]}"; do
        run_ndmgr $cmd || return 1
        rm -rf target/* 2>/dev/null || true
    done
    
    return 0
}

# === GIT OPERATIONS COMPREHENSIVE TESTS ===

test_dual_repository_setup() {
    # Skip if git is not available
    if ! command -v git &> /dev/null; then
        return 1
    fi
    
    # Clone both test repositories
    local repo1_success=false
    local repo2_success=false
    
    if git clone "$TEST_REPO1_URL" repo1 2>/dev/null; then
        repo1_success=true
        cd repo1
        git config user.name "NDMGR Test"
        git config user.email "test@ndmgr.test"
        cd ..
    fi
    
    if git clone "$TEST_REPO2_URL" repo2 2>/dev/null; then
        repo2_success=true
        cd repo2
        git config user.name "NDMGR Test"
        git config user.email "test@ndmgr.test"
        cd ..
    fi
    
    if [[ "$repo1_success" == "true" && "$repo2_success" == "true" ]]; then
        return 0
    else
        log_error "Failed to clone one or both test repositories"
        return 1
    fi
}

test_multi_repository_configuration() {
    # Skip if git is not available
    if ! command -v git &> /dev/null; then
        return 1
    fi
    
    # Set up dual repository test
    test_dual_repository_setup || return 1
    
    # Create configuration using both repositories
    mkdir -p test_config_dir
    cat > test_config_dir/config.toml << 'EOF'
[[repository]]
name = "primary_dotfiles"
path = "./repo1"
remote = "git@github.com:adaryorg/ndmgr_test.git"
branch = "main"
auto_commit = false

[[repository]]
name = "secondary_dotfiles" 
path = "./repo2"
remote = "git@github.com:adaryorg/ndmgr_test2.git"
branch = "main"
auto_commit = true
EOF
    
    # Test configuration commands with both repos
    local config_commands=(
        "--config"
        "--status"
        "--repos"
        "--info"
    )
    
    for cmd in "${config_commands[@]}"; do
        local output
        output=$(NDMGR_CONFIG_DIR="test_config_dir" "$NDMGR_BINARY" $cmd 2>&1) || true
        
        # Verify output mentions both repositories
        if ! echo "$output" | grep -q -E "(primary_dotfiles|secondary_dotfiles|repo1|repo2)"; then
            log_error "Config command $cmd doesn't show repository information"
            return 1
        fi
    done
    
    return 0
}

test_git_operations_comprehensive() {
    # Skip if git is not available
    if ! command -v git &> /dev/null; then
        return 1
    fi
    
    test_dual_repository_setup || return 1
    
    # Create configuration for git operations testing
    mkdir -p git_ops_config
    cat > git_ops_config/config.toml << 'EOF'
[[repository]]
name = "test_repo1"
path = "./repo1"
remote = "git@github.com:adaryorg/ndmgr_test.git"
branch = "main"

[[repository]]
name = "test_repo2"
path = "./repo2"
remote = "git@github.com:adaryorg/ndmgr_test2.git"
branch = "main"
EOF
    
    # Test all git operation commands
    local git_commands=(
        "--pull"
        "--pull --verbose"
        "--push"
        "--push --verbose"
        "--sync"
        "--sync --verbose"
        "--pull-all"
        "--push-all"
    )
    
    for cmd in "${git_commands[@]}"; do
        local output
        output=$(NDMGR_CONFIG_DIR="git_ops_config" "$NDMGR_BINARY" $cmd 2>&1) || true
        
        # Should not show "not yet implemented" anymore
        if echo "$output" | grep -q "not yet implemented"; then
            log_error "Git command $cmd still shows 'not yet implemented'"
            return 1
        fi
        
        # Should show some git operation activity or proper error handling
        if ! echo "$output" | grep -q -E "(Repository|Sync|Clone|Pull|Push|Failed|Success|Statistics)"; then
            log_error "Git command $cmd doesn't show expected git operation output"
            return 1
        fi
    done
    
    return 0
}

test_repository_management_commands() {
    # Test repository management with both test repositories
    rm -rf "$HOME/.config/ndmgr" 2>/dev/null || true
    run_ndmgr --init-config
    
    # Test adding repositories  
    local add_commands=(
        "--add-repo --name primary --path ./repo1 --remote $TEST_REPO1_URL --branch main"
        "--add-repo --name secondary --path ./repo2 --remote $TEST_REPO2_URL --branch development"
    )
    
    for cmd in "${add_commands[@]}"; do
        local output
        output=$(run_ndmgr $cmd 2>&1) || true
        
        if ! echo "$output" | grep -q "successfully"; then
            log_error "Add repository command failed: $cmd"
            return 1
        fi
    done
    
    # Verify repositories were added
    local output
    output=$(run_ndmgr --repos 2>&1) || true
    
    if ! echo "$output" | grep -q "primary" || ! echo "$output" | grep -q "secondary"; then
        log_error "Added repositories not shown in --repos output"
        return 1
    fi
    
    return 0
}

# === ERROR SCENARIO AND EDGE CASE TESTS ===

test_network_permission_error_scenarios() {
    # Test various network and permission error scenarios
    
    # Test with invalid git repository URLs
    mkdir -p error_config1
    cat > error_config1/config.toml << 'EOF'
[[repository]]
name = "invalid_repo"
path = "/tmp/invalid_test_repo"
remote = "git@invalid.domain.that.does.not.exist.com:fake/repo.git"
branch = "main"
EOF
    
    local output
    output=$(NDMGR_CONFIG_DIR="error_config1" "$NDMGR_BINARY" --pull 2>&1) || true
    
    # Should handle network errors gracefully
    if ! echo "$output" | grep -q -E "(Failed|Error|Unable|Could not|Connection|Network)"; then
        log_error "Network error not handled gracefully"
        return 1
    fi
    
    # Test with permission denied scenarios
    mkdir -p error_config2
    cat > error_config2/config.toml << 'EOF'
[[repository]]
name = "permission_denied"
path = "/root/definitely/no/permission/here"
remote = "git@github.com:adaryorg/ndmgr_test.git"
branch = "main"
EOF
    
    output=$(NDMGR_CONFIG_DIR="error_config2" "$NDMGR_BINARY" --pull 2>&1) || true
    
    # Should handle permission errors gracefully
    if ! echo "$output" | grep -q -E "(Permission|Access|denied|Failed|Error|Could not create)"; then
        log_error "Permission error not handled gracefully"
        return 1
    fi
    
    return 0
}

test_malformed_configuration_handling() {
    # Test handling of malformed TOML configurations
    mkdir -p malformed_config
    
    # Create invalid TOML
    cat > malformed_config/config.toml << 'EOF'
[invalid toml syntax
name = "broken
remote = git@example.com:test.git
missing_quotes = value without quotes
[section with spaces in name]
EOF
    
    local output
    output=$(NDMGR_CONFIG_DIR="malformed_config" "$NDMGR_BINARY" --status 2>&1) || true
    
    # Should handle malformed config gracefully
    if ! echo "$output" | grep -q -E "(Error|Invalid|Failed|Parse|Configuration)"; then
        log_error "Malformed configuration not handled gracefully"
        return 1
    fi
    
    return 0
}

test_missing_dependencies_handling() {
    # Test module dependency resolution with missing dependencies
    create_generic_module "dependent_module" \
        "description=\"Module with missing dependency\"\ndependencies=[\"nonexistent_module\"]" \
        ".dependent_config" "depends_on_missing=true"
    
    local output
    output=$(run_ndmgr --deploy --verbose 2>&1) || true
    
    # Should handle missing dependencies gracefully
    if ! echo "$output" | grep -q -E "(dependency|missing|not found|skip|error)" && \
       ! echo "$output" | grep -q "dependent_module"; then
        log_error "Missing dependencies not handled appropriately"
        return 1
    fi
    
    return 0
}

test_filesystem_edge_cases() {
    # Test various filesystem edge cases
    
    # Test with very long filenames
    create_generic_module "long_filename_test" \
        "description=\"Test module with very long filenames\"" \
        ".very_long_filename_that_might_cause_issues_with_filesystem_operations_and_path_handling_in_various_systems.conf" "long_filename=true"
    
    run_ndmgr --deploy || return 1
    
    # Test with special characters in paths
    create_generic_module "special_chars_test" \
        "description=\"Test module with special characters\"" \
        ".config with spaces/app-name_2024/config@test.conf" "special_chars=true" \
        ".测试中文" "unicode=true"
    
    run_ndmgr --deploy || return 1
    
    # Test with symlink loops prevention
    mkdir -p dotfiles/symlink_test
    echo 'description="Symlink test module"' > dotfiles/symlink_test/.ndmgr
    ln -s ../symlink_test dotfiles/symlink_test/recursive_link
    
    local output
    output=$(run_ndmgr --deploy --verbose 2>&1) || true
    
    # Should handle recursive symlinks appropriately
    if ! echo "$output" | grep -q -E "(symlink|recursive|loop|skip|error)"; then
        log_error "Recursive symlinks not handled appropriately"
        return 1
    fi
    
    return 0
}

# === PERFORMANCE AND STRESS TESTS ===

test_large_repository_handling() {
    # Create a module with many files to test performance
    create_generic_module "large_module" \
        "description=\"Large module with many files\""
    
    # Create many test files
    for i in {1..50}; do
        echo "file_$i=true" > "dotfiles/large_module/.config_file_$i"
    done
    
    # Create nested directory structure
    for dir in {1..10}; do
        mkdir -p "dotfiles/large_module/.config/app$dir/subdir$dir"
        for file in {1..5}; do
            echo "nested_$dir_$file=true" > "dotfiles/large_module/.config/app$dir/subdir$dir/file$file.conf"
        done
    done
    
    # Test deployment performance
    local start_time=$(date +%s)
    run_ndmgr --deploy --verbose
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Should complete within reasonable time (30 seconds)
    if [[ $duration -gt 30 ]]; then
        log_error "Large repository deployment took too long: ${duration}s"
        return 1
    fi
    
    # Verify files were linked
    if [[ ! -L "target/.config_file_1" ]] || [[ ! -L "target/.config_file_50" ]]; then
        log_error "Large module files not properly linked"
        return 1
    fi
    
    return 0
}

test_concurrent_operations_safety() {
    # Test that multiple operations don't interfere with each other
    create_generic_module "concurrent_test1" \
        "description=\"First concurrent test module\"" \
        ".concurrent1" "test1=true"
    
    create_generic_module "concurrent_test2" \
        "description=\"Second concurrent test module\"" \
        ".concurrent2" "test2=true"
    
    # Run multiple operations rapidly
    run_ndmgr --link concurrent_test1 &
    run_ndmgr --link concurrent_test2 &
    run_ndmgr --deploy &
    
    # Wait for all operations to complete
    wait
    
    # Verify results are consistent
    if [[ -L "target/.concurrent1" ]] && [[ -L "target/.concurrent2" ]]; then
        return 0
    else
        log_error "Concurrent operations produced inconsistent results"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting NDMGR Comprehensive Functional Tests"
    log_info "Binary: $NDMGR_BINARY"
    log_info "Test Repository 1: $TEST_REPO1_URL"
    log_info "Test Repository 2: $TEST_REPO2_URL"
    log_info "Testing with generic module names (no real app names)"
    
    setup_test_environment
    trap cleanup_test_environment EXIT
    
    # CLI Command Tests
    log_info "=== CLI COMMAND COMPREHENSIVE TESTS ==="
    run_test "All CLI Help Options" test_all_cli_help_options
    run_test "All Linking Command Combinations" test_all_linking_command_combinations
    run_test "Advanced Linking Combinations" test_advanced_linking_combinations
    run_test "Deployment Command Combinations" test_deployment_command_combinations
    
    # Git Operations Tests
    if command -v git &> /dev/null; then
        log_info "=== GIT OPERATIONS COMPREHENSIVE TESTS ==="
        run_test "Dual Repository Setup" test_dual_repository_setup || true
        run_test "Multi Repository Configuration" test_multi_repository_configuration || true
        run_test "Git Operations Comprehensive" test_git_operations_comprehensive || true
        run_test "Repository Management Commands" test_repository_management_commands || true
    else
        skip_test "Git Operations Tests" "git command not available"
    fi
    
    # Error Scenario Tests
    log_info "=== ERROR SCENARIO AND EDGE CASE TESTS ==="
    run_test "Network/Permission Error Scenarios" test_network_permission_error_scenarios
    run_test "Malformed Configuration Handling" test_malformed_configuration_handling
    run_test "Missing Dependencies Handling" test_missing_dependencies_handling
    run_test "Filesystem Edge Cases" test_filesystem_edge_cases
    
    # Performance Tests
    log_info "=== PERFORMANCE AND STRESS TESTS ==="
    run_test "Large Repository Handling" test_large_repository_handling
    run_test "Concurrent Operations Safety" test_concurrent_operations_safety
    
    # Print summary
    echo
    log_info "=== COMPREHENSIVE TEST SUMMARY ==="
    log_info "Total tests: $TEST_COUNT"
    log_success "Passed: $PASS_COUNT"
    log_error "Failed: $FAIL_COUNT" 
    log_warning "Skipped: $SKIP_COUNT"
    
    if [[ $FAIL_COUNT -eq 0 ]]; then
        log_success "All comprehensive functional tests passed!"
        exit 0
    else
        log_error "Some comprehensive tests failed!"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "NDMGR Comprehensive Functional Test Suite"
        echo "Usage: $0 [options]"
        echo ""
        echo "This test suite provides comprehensive functional testing of ndmgr including:"
        echo "- All CLI command combinations"
        echo "- Dual git repository testing"
        echo "- Error scenario handling"
        echo "- Performance and stress testing"
        echo "- Edge case handling"
        echo ""
        echo "Uses generic module names to avoid confusion with real applications."
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --binary PATH  Specify ndmgr binary path (default: ./zig-out/bin/ndmgr)"
        exit 0
        ;;
    --binary)
        NDMGR_BINARY="$2"
        shift 2
        ;;
esac

main "$@"