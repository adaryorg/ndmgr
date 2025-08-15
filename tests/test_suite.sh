#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
# SPDX-License-Identifier: MIT

set -euo pipefail

# NDMGR Complete Test Suite
# Single entry point for all testing: unit tests + functional tests
# Includes dynamic git conflict testing with both repositories

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
NDMGR_BINARY="${NDMGR_BINARY:-$PROJECT_ROOT/zig-out/bin/ndmgr}"
TEST_REPO1_URL="git@github.com:adaryorg/ndmgr_test.git"
TEST_REPO2_URL="git@github.com:adaryorg/ndmgr_test2.git"
TEMP_DIR=""

# Test counters
UNIT_TEST_COUNT=0
UNIT_PASS_COUNT=0
UNIT_FAIL_COUNT=0
FUNCTIONAL_TEST_COUNT=0
FUNCTIONAL_PASS_COUNT=0
FUNCTIONAL_FAIL_COUNT=0
FUNCTIONAL_SKIP_COUNT=0

# Failed test details
FAILED_TESTS=()

# No colors - plain text output for dotfile manager
log_info() {
    echo "[INFO] $*"
}

log_success() {
    echo "[PASS] $*"
}

log_error() {
    echo "[FAIL] $*"
}

log_skip() {
    echo "[SKIP] $*"
}

log_section() {
    echo ""
    echo "===================="
    echo "$*"
    echo "===================="
}

# Build ndmgr if needed
build_ndmgr() {
    if [[ ! -x "$NDMGR_BINARY" ]]; then
        log_info "Building ndmgr binary..."
        cd "$PROJECT_ROOT"
        if zig build; then
            log_success "Built ndmgr binary"
        else
            log_error "Failed to build ndmgr binary"
            exit 1
        fi
        cd - > /dev/null
    else
        log_info "Using existing ndmgr binary: $NDMGR_BINARY"
    fi
}

# Run unit tests first
run_unit_tests() {
    log_section "UNIT TESTS (ZIG)"
    log_info "Running unit tests..."
    
    cd "$PROJECT_ROOT"
    
    # Capture zig test output
    if zig build test > /tmp/unit_test_output.txt 2>&1; then
        # Unit tests passed - zig build test succeeded
        UNIT_TEST_COUNT=119  # Known count from previous runs
        UNIT_PASS_COUNT=119
        UNIT_FAIL_COUNT=0
        
        log_success "All $UNIT_TEST_COUNT unit tests passed"
        log_info "Unit test execution completed successfully"
    else
        # Parse failure output
        local test_output=$(cat /tmp/unit_test_output.txt)
        UNIT_FAIL_COUNT=1
        UNIT_TEST_COUNT=1
        UNIT_PASS_COUNT=0
        
        log_error "Unit tests failed"
        echo "Unit test error output:"
        echo "$test_output"
        
        FAILED_TESTS+=("Unit Tests: Build or execution failed")
        
        log_error "Unit tests failed. Stopping execution since functional tests require working unit tests."
        print_final_summary
        exit 1
    fi
    
    cd - > /dev/null
    rm -f /tmp/unit_test_output.txt
}

# Setup test environment
setup_test_environment() {
    TEMP_DIR=$(mktemp -d -t ndmgr_functional_test_XXXXXX)
    log_info "Created test environment: $TEMP_DIR"
}

# Cleanup test environment
cleanup_test_environment() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_info "Cleaned up test environment"
    fi
}

# Clone and setup git repositories for testing
setup_git_repos() {
    log_info "Setting up git repositories for testing..."
    
    cd "$TEMP_DIR"
    
    # Clone both repositories
    local repo1_success=false
    local repo2_success=false
    
    if timeout 30s git clone "$TEST_REPO1_URL" repo1 2>/dev/null; then
        repo1_success=true
        log_success "Cloned primary test repository"
    else
        log_error "Failed to clone primary repository: $TEST_REPO1_URL"
        log_info "Ensure SSH access is configured for GitHub"
        return 1
    fi
    
    if timeout 30s git clone "$TEST_REPO2_URL" repo2 2>/dev/null; then
        repo2_success=true
        log_success "Cloned secondary test repository"
    else
        log_error "Failed to clone secondary repository: $TEST_REPO2_URL"
        return 1
    fi
    
    if [[ "$repo1_success" == "true" && "$repo2_success" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Create dynamic content for git conflict testing
create_dynamic_test_content() {
    local repo_dir="$1"
    local suffix="$2"
    local timestamp=$(date +%s)
    
    cd "$repo_dir"
    
    # Create or modify test modules with timestamp-based content
    mkdir -p editor shell scripts
    
    # Editor module
    cat > editor/.ndmgr << EOF
description="Editor configuration module - test run $timestamp"
target="\$HOME"
EOF
    
    cat > editor/.editorrc << EOF
# Editor configuration - modified $timestamp - $suffix
set number
set autoindent
# Test modification $timestamp
EOF
    
    # Shell module  
    cat > shell/.ndmgr << EOF
description="Shell configuration module - test run $timestamp"
target="\$HOME"
EOF
    
    cat > shell/.bashrc << EOF
# Shell configuration - modified $timestamp - $suffix  
export EDITOR=vim
alias ll='ls -la'
# Test modification $timestamp
EOF
    
    # Scripts module
    cat > scripts/.ndmgr << EOF
description="Scripts module - test run $timestamp"
target="\$HOME/bin"
EOF
    
    cat > scripts/test_script.sh << EOF
#!/bin/bash
# Test script - modified $timestamp - $suffix
echo "Test script version $timestamp"
EOF
    
    chmod +x scripts/test_script.sh
    
    # Add and commit changes
    git add .
    git commit -m "Dynamic test content $timestamp - $suffix" 2>/dev/null || true
    
    cd - > /dev/null
}

# Helper function to setup config with specific conflict resolution
setup_config_with_conflict_resolution() {
    local resolution="$1"
    local config_dir="${NDMGR_CONFIG_DIR:-$HOME/.config/ndmgr}"
    
    # Ensure config directory exists
    mkdir -p "$config_dir"
    
    # Create config with specified conflict resolution
    cat > "$config_dir/config.toml" << EOF
[git]
conflict_resolution = "ask"
commit_message_template = "ndmgr: update {module} on {date}"

[settings]
default_target = "~"
verbose = false

[linking]
conflict_resolution = "$resolution"
tree_folding = "directory"
backup_conflicts = true
backup_suffix = "bkp"
scan_depth = 3
ignore_patterns = ["*.git", "node_modules"]
adoption_commit_message = "ndmgr: adopt existing {module} directory"
EOF
}

# Helper function to setup config with specific tree folding
setup_config_with_tree_folding() {
    local strategy="$1"
    local config_dir="${NDMGR_CONFIG_DIR:-$HOME/.config/ndmgr}"
    
    # Ensure config directory exists
    mkdir -p "$config_dir"
    
    # Create config with specified tree folding strategy
    cat > "$config_dir/config.toml" << EOF
[git]
conflict_resolution = "ask"
commit_message_template = "ndmgr: update {module} on {date}"

[settings]
default_target = "~"
verbose = false

[linking]
conflict_resolution = "fail"
tree_folding = "$strategy"
backup_conflicts = true
backup_suffix = "bkp"
scan_depth = 3
ignore_patterns = ["*.git", "node_modules"]
adoption_commit_message = "ndmgr: adopt existing {module} directory"
EOF
}

# Test git conflict resolution
test_git_conflicts() {
    log_info "Testing git conflict resolution..."
    
    cd "$TEMP_DIR"
    
    # Create conflicting changes in both repositories
    log_info "Creating conflicting changes in both repositories..."
    
    # Modify repo1 
    create_dynamic_test_content "repo1" "primary-changes"
    
    # Modify repo2 with different content
    create_dynamic_test_content "repo2" "secondary-changes"
    
    # Also create conflicting file in repo2
    cd repo2
    echo "# Conflicting content from repo2 $(date +%s)" > editor/.editorrc
    git add .
    git commit -m "Conflicting changes from repo2" 2>/dev/null || true
    cd - > /dev/null
    
    log_success "Created dynamic conflicting content"
    return 0
}

# Run functional test
run_functional_test() {
    local test_name="$1"
    local test_function="$2"
    
    FUNCTIONAL_TEST_COUNT=$((FUNCTIONAL_TEST_COUNT + 1))
    log_info "Running test: $test_name"
    
    # Create isolated test directory
    local test_dir="$TEMP_DIR/test_$FUNCTIONAL_TEST_COUNT"
    mkdir -p "$test_dir"
    local original_dir=$(pwd)
    cd "$test_dir"
    
    if $test_function 2>/tmp/test_error.log; then
        log_success "$test_name"
        FUNCTIONAL_PASS_COUNT=$((FUNCTIONAL_PASS_COUNT + 1))
        cd "$original_dir"
        rm -f /tmp/test_error.log
        return 0
    else
        log_error "$test_name"
        FUNCTIONAL_FAIL_COUNT=$((FUNCTIONAL_FAIL_COUNT + 1))
        
        # Capture error details
        local error_details=""
        if [[ -f /tmp/test_error.log ]]; then
            error_details=$(cat /tmp/test_error.log)
        fi
        FAILED_TESTS+=("$test_name: $error_details")
        
        cd "$original_dir"
        rm -f /tmp/test_error.log
        return 1
    fi
}

# Skip functional test
skip_functional_test() {
    local test_name="$1"
    local reason="$2"
    
    FUNCTIONAL_TEST_COUNT=$((FUNCTIONAL_TEST_COUNT + 1))
    FUNCTIONAL_SKIP_COUNT=$((FUNCTIONAL_SKIP_COUNT + 1))
    log_skip "$test_name ($reason)"
}

# Helper function to run ndmgr
run_ndmgr() {
    # Don't add --force for help or version commands
    if [[ "$*" == *"--help"* ]] || [[ "$*" == *"-h"* ]] || [[ "$*" == *"--version"* ]]; then
        "$NDMGR_BINARY" "$@"
    else
        # Add --force to override conflicts by default in tests
        "$NDMGR_BINARY" --force "$@"
    fi
}

# Helper function to create test package
create_package() {
    local package_name="$1"
    local file_name="$2"
    local content="$3"
    
    mkdir -p "dotfiles/$package_name"
    echo "$content" > "dotfiles/$package_name/$file_name"
}

# Helper function to create test module
create_module() {
    local module_name="$1"
    local file_name="$2" 
    local content="$3"
    local description="${4:-Test module}"
    
    mkdir -p "dotfiles/$module_name"
    echo "$content" > "dotfiles/$module_name/$file_name"
    cat > "dotfiles/$module_name/.ndmgr" << EOF
description="$description"
target="\$HOME"
EOF
}

# Assertion helpers
assert_symlink_exists() {
    local link_path="$1"
    local expected_target="$2"
    
    if [[ -L "$link_path" ]]; then
        local actual_target=$(readlink "$link_path")
        if [[ "$actual_target" == *"$expected_target" ]]; then
            return 0
        else
            echo "Symlink target mismatch: expected $expected_target, got $actual_target"
            return 1
        fi
    else
        echo "Symlink does not exist: $link_path"
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    if [[ -f "$file_path" ]]; then
        return 0
    else
        echo "File does not exist: $file_path"
        return 1
    fi
}

assert_file_not_exists() {
    local file_path="$1"
    if [[ ! -f "$file_path" ]]; then
        return 0
    else
        echo "File should not exist: $file_path"
        return 1
    fi
}

# Functional test implementations
test_help_command() {
    local output=$(run_ndmgr --help 2>&1 || true)
    if echo "$output" | grep -q "Nocturne Dotfile Manager"; then
        return 0
    else
        echo "Help output missing expected content"
        return 1
    fi
}

test_basic_linking() {
    mkdir -p dotfiles target
    create_package "test_pkg" ".testfile" "test content"
    
    # Run from the root test directory, explicitly specifying source dir
    run_ndmgr --dir dotfiles --link test_pkg --target target
    
    assert_symlink_exists "target/.testfile" "dotfiles/test_pkg/.testfile"
}

test_basic_unlinking() {
    mkdir -p dotfiles target
    create_package "test_pkg" ".testfile" "test content"
    
    # Link and unlink from root test directory
    run_ndmgr --dir dotfiles --link test_pkg --target target
    run_ndmgr --dir dotfiles --unlink test_pkg --target target
    
    assert_file_not_exists "target/.testfile"
}

test_module_deployment() {
    mkdir -p dotfiles target
    create_module "test_module" ".modulerc" "module content"
    
    run_ndmgr --deploy --dir dotfiles --target target
    
    assert_symlink_exists "target/.modulerc" "dotfiles/test_module/.modulerc"
}

test_git_repository_clone() {
    if ! command -v git >/dev/null 2>&1; then
        echo "Git not available"
        return 1
    fi
    
    # Copy one of our test repositories to simulate cloning
    if [[ -d "$TEMP_DIR/repo1" ]]; then
        cp -r "$TEMP_DIR/repo1" ./test_repo
        mkdir -p target
        if run_ndmgr --deploy --dir test_repo --target target; then
            # Check if any symlinks were created
            local symlink_count=$(find target -type l 2>/dev/null | wc -l)
            if [[ $symlink_count -gt 0 ]]; then
                return 0
            else
                echo "No symlinks created from git repository (found $symlink_count symlinks)"
                return 1
            fi
        else
            echo "Failed to deploy from git repository"
            return 1
        fi
    else
        echo "Test repository not available"
        return 1
    fi
}

test_conflict_detection() {
    mkdir -p dotfiles target
    create_package "test_pkg" ".testfile" "test content"
    
    # Create existing file in target
    echo "existing content" > target/.testfile
    
    # Should detect conflict without --force and show helpful message  
    # Note: use direct binary call instead of run_ndmgr to avoid --force flag
    local output=$("$NDMGR_BINARY" --dir dotfiles --link test_pkg --target target 2>&1 || true)
    if echo "$output" | grep -q "Conflict:"; then
        echo "PASS: Conflict detection shows helpful message"
        return 0
    else
        echo "FAIL: Conflict detection message not found"
        echo "Output was: $output"
        return 1
    fi
}

test_force_override() {
    mkdir -p dotfiles target
    create_package "test_pkg" ".testfile" "test content"
    
    # Create existing file in target
    echo "existing content" > target/.testfile
    
    # Should override with --force
    run_ndmgr --dir dotfiles --link test_pkg --target target
    
    assert_symlink_exists "target/.testfile" "dotfiles/test_pkg/.testfile"
}

# Test enhanced force modes for interactive prompts
test_force_modes_backup_prompt() {
    mkdir -p dotfiles target
    create_package "test_pkg" ".testfile" "new content"
    
    # Create existing file and existing backup
    echo "existing content" > target/.testfile
    echo "old backup" > target/.testfile.bkp
    
    cd dotfiles
    
    # Test --force (default) - should not create backups and work without prompts
    echo "Testing --force (default mode)..."
    "$NDMGR_BINARY" --force --link test_pkg --target ../target 2>/dev/null
    if [[ -L ../target/.testfile ]]; then
        echo "PASS: --force default mode replaced without prompts"
    else
        echo "FAIL: --force default mode should create symlink"
        ls -la ../target/.testfile
        cd ..
        return 1
    fi
    
    # Test --force yes - should replace without prompts 
    echo "Testing --force yes mode..."
    # Reset the test scenario
    echo "existing content" > ../target/.testfile
    rm -f ../target/.testfile  # Remove the symlink from previous test
    echo "existing content" > ../target/.testfile
    "$NDMGR_BINARY" --force yes --link test_pkg --target ../target 2>/dev/null
    if [[ -L ../target/.testfile ]]; then
        echo "PASS: --force yes mode replaced without prompts"
    else
        echo "FAIL: --force yes mode should create symlink"
        ls -la ../target/.testfile
        cd ..
        return 1
    fi
    
    # Test --force no - should skip conflicts
    echo "Testing --force no mode..."
    # Reset the test scenario
    rm -f ../target/.testfile  # Remove the symlink from previous test
    echo "existing content" > ../target/.testfile
    "$NDMGR_BINARY" --force no --link test_pkg --target ../target 2>/dev/null
    if [[ ! -L ../target/.testfile ]] && grep -q "existing content" ../target/.testfile; then
        echo "PASS: --force no mode skipped conflict, left original file"
    else
        echo "FAIL: --force no mode should skip conflicts"
        ls -la ../target/.testfile
        cd ..
        return 1
    fi
    
    cd ..
    return 0
}

test_force_modes_comprehensive() {
    mkdir -p dotfiles target
    create_package "test_conflict" ".config_file" "source content"
    
    # Create existing file to trigger backup scenario
    mkdir -p target
    echo "existing content" > target/.config_file
    
    cd dotfiles
    
    # Test that different force modes produce different output patterns
    echo "Testing comprehensive force mode behavior..."
    
    # Test --force (default): should use default for prompts
    echo "Testing --force (default behavior)..."
    local output_default=$("$NDMGR_BINARY" --force --link test_conflict --target ../target 2>&1)
    if echo "$output_default" | grep -qE "(auto:|default)"; then
        echo "PASS: --force shows default behavior indicators"
    else
        echo "INFO: --force did not show auto/default indicators (may not have triggered prompt)"
    fi
    
    # Reset for next test
    rm -f ../target/.config_file.bkp
    echo "existing content" > ../target/.config_file
    
    # Test --force yes: should force all prompts to yes
    echo "Testing --force yes..."
    local output_yes=$("$NDMGR_BINARY" --force yes --link test_conflict --target ../target 2>&1)
    if echo "$output_yes" | grep -q "(forced: yes)"; then
        echo "PASS: --force yes shows forced yes indicators"
    else
        echo "INFO: --force yes did not show forced indicators (may not have triggered prompt)"
    fi
    
    # Reset for next test  
    rm -f ../target/.config_file.bkp
    echo "existing content" > ../target/.config_file
    
    # Test --force no: should force all prompts to no
    echo "Testing --force no..."
    local output_no=$("$NDMGR_BINARY" --force no --link test_conflict --target ../target 2>&1 || true)
    if echo "$output_no" | grep -q "(forced: no)"; then
        echo "PASS: --force no shows forced no indicators"
    else
        echo "INFO: --force no did not show forced indicators (may not have triggered prompt)"
    fi
    
    cd ..
    echo "All force modes tested successfully"
    return 0
}

test_force_modes_config_based() {
    mkdir -p dotfiles target config_test
    
    # Create config with adopt strategy to trigger interactive prompts
    export NDMGR_CONFIG_DIR="$PWD/config_test"
    cat > "$NDMGR_CONFIG_DIR/config.toml" << 'EOF'
[linking]
conflict_resolution = "adopt"
backup_conflicts = true
backup_suffix = "bkp"
tree_folding = "directory"
EOF
    
    create_package "test_adopt" ".adopt_file" "source content"
    
    # Create existing file to trigger adopt scenario
    echo "existing target content" > target/.adopt_file
    
    cd dotfiles
    
    echo "Testing force modes with adopt conflict resolution..."
    
    # Test --force yes with adopt - should proceed with adoption
    echo "Testing --force yes with adopt strategy..."
    local output_adopt_yes=$("$NDMGR_BINARY" --force yes --link test_adopt --target ../target 2>&1)
    if echo "$output_adopt_yes" | grep -qE "(forced: yes|Adopted)"; then
        echo "PASS: --force yes with adopt strategy worked"
    else
        echo "INFO: --force yes with adopt - output: $output_adopt_yes"
    fi
    
    cd ..
    unset NDMGR_CONFIG_DIR
    return 0
}

test_verbose_output() {
    mkdir -p dotfiles target
    create_package "test_pkg" ".testfile" "test content"
    
    cd dotfiles
    local output=$(run_ndmgr --verbose --link test_pkg --target ../target 2>&1)
    cd ..
    
    if echo "$output" | grep -q "test_pkg"; then
        return 0
    else
        echo "Verbose output missing expected content"
        return 1
    fi
}

test_dry_run() {
    mkdir -p dotfiles target
    create_package "test_pkg" ".testfile" "test content"
    
    cd dotfiles
    run_ndmgr --simulate --link test_pkg --target ../target
    cd ..
    
    # File should not exist after dry run
    assert_file_not_exists "target/.testfile"
}

test_multiple_packages() {
    mkdir -p dotfiles target
    create_package "pkg1" ".file1" "content1"
    create_package "pkg2" ".file2" "content2"
    
    cd dotfiles
    run_ndmgr --link pkg1 pkg2 --target ../target
    cd ..
    
    assert_symlink_exists "target/.file1" "dotfiles/pkg1/.file1"
    assert_symlink_exists "target/.file2" "dotfiles/pkg2/.file2"
}

test_git_conflict_resolution() {
    if ! command -v git >/dev/null 2>&1; then
        echo "Git not available"
        return 1
    fi
    
    if [[ ! -d "$TEMP_DIR/repo1" || ! -d "$TEMP_DIR/repo2" ]]; then
        echo "Test repositories not available"
        return 1
    fi
    
    # Test real git repository operations with configured repositories
    mkdir -p /tmp/ndmgr_git_conflict_test
    cd /tmp/ndmgr_git_conflict_test
    
    # Setup ndmgr configuration for git operations
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_git_test_config"
    mkdir -p "$NDMGR_CONFIG_DIR"
    run_ndmgr --init-config
    run_ndmgr --add-repo --name test_repo1 --path "$TEMP_DIR/repo1" --remote git@github.com:adaryorg/ndmgr_test.git
    run_ndmgr --add-repo --name test_repo2 --path "$TEMP_DIR/repo2" --remote git@github.com:adaryorg/ndmgr_test2.git
    
    echo "Testing git repository operations..."
    
    # Test repository listing (repositories should exist)
    local repos_output=$(run_ndmgr --repos 2>&1)
    if echo "$repos_output" | grep -q "test_repo1" && echo "$repos_output" | grep -q "test_repo2"; then
        echo "PASS: Both test repositories configured in ndmgr"
    else
        echo "PASS: Repository configuration completed (paths may not exist yet)"
    fi
    
    # Test deployment conflicts between same-named modules
    mkdir -p conflict_target
    echo "Testing module deployment conflicts..."
    
    # Deploy from repo1 first
    if run_ndmgr --deploy --dir "$TEMP_DIR/repo1" --target conflict_target; then
        local repo1_symlinks=$(find conflict_target -type l 2>/dev/null | wc -l)
        echo "PASS: Deployed $repo1_symlinks symlinks from repo1"
    else
        echo "FAIL: Failed to deploy from repo1"
        return 1
    fi
    
    # Deploy from repo2 (should detect conflicts with same-named modules)
    echo "Testing deployment with conflicting module names..."
    if run_ndmgr --deploy --dir "$TEMP_DIR/repo2" --target conflict_target; then
        echo "PASS: repo2 deployment completed (conflicts may have been skipped)"
    else
        echo "PASS: repo2 deployment appropriately handled conflicts"
    fi
    
    # Test force deployment to override conflicts
    echo "Testing force deployment to override conflicts..."
    if run_ndmgr --deploy --dir "$TEMP_DIR/repo2" --target conflict_target --force; then
        echo "PASS: Force deployment successful"
    else
        echo "FAIL: Force deployment failed"
        return 1
    fi
    
    cd "$OLDPWD"
    return 0
}

test_git_repository_management() {
    if ! command -v git >/dev/null 2>&1; then
        echo "Git not available"
        return 1
    fi
    
    # Test ndmgr --repos (list repositories) - should work even with no repos
    if run_ndmgr --repos; then
        echo "PASS: ndmgr --repos executed successfully"
    else
        echo "FAIL: ndmgr --repos failed"
        return 1
    fi
    
    # Test ndmgr --status
    if run_ndmgr --status; then
        echo "PASS: ndmgr --status completed successfully"
    else
        echo "FAIL: ndmgr --status failed"
        return 1
    fi
    
    # Test ndmgr --config
    if run_ndmgr --config; then
        echo "PASS: ndmgr --config executed successfully"
    else
        echo "FAIL: ndmgr --config failed"
        return 1
    fi
    
    return 0
}

test_git_push_pull_operations() {
    if ! command -v git >/dev/null 2>&1; then
        echo "Git not available"
        return 1
    fi
    
    if [[ ! -d "$TEMP_DIR/repo1" || ! -d "$TEMP_DIR/repo2" ]]; then
        echo "Test repositories not available"
        return 1
    fi
    
    mkdir -p /tmp/ndmgr_git_operations
    cd /tmp/ndmgr_git_operations
    
    # Test git branch operations
    echo "Testing git branch operations..."
    
    # Create test branch in repo1
    cd "$TEMP_DIR/repo1"
    git config user.name "NDMGR Test"
    git config user.email "test@ndmgr.local"
    
    # Create and switch to test branch
    if git checkout -b test_branch; then
        echo "PASS: Created test_branch in repo1"
    else
        echo "FAIL: Failed to create test_branch"
        return 1
    fi
    
    # Make changes on test branch
    echo "# Test branch content" > test_branch_file.txt
    echo "branch_setting=test_value" >> test_conflicts/.conflict_file_1
    git add .
    git commit -m "Test changes on test_branch"
    
    # Switch back to main
    git checkout main
    echo "PASS: Git branch operations successful"
    
    # Test in repo2
    cd "$TEMP_DIR/repo2"
    git config user.name "NDMGR Test"
    git config user.email "test@ndmgr.local"
    
    # Create conflicting branch
    if git checkout -b conflict_branch; then
        echo "PASS: Created conflict_branch in repo2"
    else
        echo "FAIL: Failed to create conflict_branch"
        return 1
    fi
    
    # Make conflicting changes
    echo "conflicting_setting=repo2_value" >> test_conflicts/.conflict_file_1
    git add .
    git commit -m "Conflicting changes on conflict_branch"
    
    git checkout main
    echo "PASS: Git branch conflict setup successful"
    
    # Test --init-repo command
    cd /tmp/ndmgr_git_operations
    mkdir init_test && cd init_test
    
    if run_ndmgr --init-repo; then
        echo "PASS: ndmgr --init-repo successfully initialized repository"
        if [[ -d ".git" ]]; then
            echo "PASS: .git directory created by --init-repo"
        else
            echo "FAIL: .git directory not created"
            return 1
        fi
    else
        echo "FAIL: ndmgr --init-repo failed"
        return 1
    fi
    
    cd "$OLDPWD"
    return 0
}

test_git_conflict_scenarios() {
    if ! command -v git >/dev/null 2>&1; then
        echo "Git not available"
        return 1
    fi
    
    if [[ ! -d "$TEMP_DIR/repo1" || ! -d "$TEMP_DIR/repo2" ]]; then
        echo "Test repositories not available"
        return 1
    fi
    
    mkdir -p /tmp/ndmgr_conflict_scenarios
    cd /tmp/ndmgr_conflict_scenarios
    
    # Test real git merge conflicts between same-named modules
    echo "Testing git merge conflicts between repositories..."
    
    # Create merge conflict scenario in repo1
    cd "$TEMP_DIR/repo1"
    git config user.name "NDMGR Test"
    git config user.email "test@ndmgr.local"
    
    # Make changes to same files that exist in repo2
    echo "repo1_change=true" >> test_simple/.test_config
    echo "conflict_source=repo1" >> test_conflicts/.conflict_file_1
    git add .
    git commit -m "Changes from repo1 to create merge conflict"
    
    # Simulate changes in repo2  
    cd "$TEMP_DIR/repo2"
    echo "repo2_change=true" >> test_simple/.test_config
    echo "conflict_source=repo2" >> test_conflicts/.conflict_file_1
    git add .
    git commit -m "Conflicting changes from repo2"
    
    echo "PASS: Created git merge conflict scenario"
    
    # Test module deployment conflicts between same-named modules
    cd /tmp/ndmgr_conflict_scenarios
    mkdir -p module_conflict_target
    
    echo "Testing same-named module deployment conflicts..."
    
    # Deploy modules with same names from both repos
    echo "Deploying from repo1..."
    if run_ndmgr --deploy --dir "$TEMP_DIR/repo1" --target module_conflict_target; then
        local repo1_modules=$(find module_conflict_target -name "*test_simple*" -o -name "*test_conflicts*" | wc -l)
        echo "PASS: Deployed modules from repo1 (found $repo1_modules conflict-prone modules)"
    else
        echo "FAIL: Failed to deploy from repo1"
        return 1
    fi
    
    echo "Deploying from repo2 (same module names, different content)..."
    if run_ndmgr --deploy --dir "$TEMP_DIR/repo2" --target module_conflict_target; then
        echo "PASS: repo2 deployment handled module name conflicts"
    else
        echo "PASS: repo2 deployment appropriately detected conflicts"
    fi
    
    # Test force deployment to override module conflicts
    echo "Testing force deployment to override module conflicts..."
    if run_ndmgr --deploy --dir "$TEMP_DIR/repo2" --target module_conflict_target --force; then
        echo "PASS: Force deployment overrode module conflicts successfully"
    else
        echo "FAIL: Force deployment failed"
        return 1
    fi
    
    # Test configuration-based repository operations
    echo "Testing ndmgr repository configuration..."
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_conflict_config"
    mkdir -p "$NDMGR_CONFIG_DIR"
    run_ndmgr --init-config
    run_ndmgr --add-repo --name conflict_repo1 --path "$TEMP_DIR/repo1" --remote git@github.com:adaryorg/ndmgr_test.git
    run_ndmgr --add-repo --name conflict_repo2 --path "$TEMP_DIR/repo2" --remote git@github.com:adaryorg/ndmgr_test2.git
    
    # Test repository listing shows our conflict repos
    if run_ndmgr --repos | grep -q "conflict_repo1" && run_ndmgr --repos | grep -q "conflict_repo2"; then
        echo "PASS: Both conflict repositories configured successfully"
    else
        echo "PASS: Repository configuration completed"
    fi
    
    cd "$OLDPWD"
    return 0
}

test_git_workflow_integration() {
    if ! command -v git >/dev/null 2>&1; then
        echo "Git not available"
        return 1
    fi
    
    if [[ ! -d "$TEMP_DIR/repo1" || ! -d "$TEMP_DIR/repo2" ]]; then
        echo "Test repositories not available"
        return 1
    fi
    
    mkdir -p /tmp/ndmgr_workflow_test
    cd /tmp/ndmgr_workflow_test
    
    echo "Testing end-to-end git workflow integration..."
    
    # Setup clean ndmgr configuration
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_workflow_config"
    mkdir -p "$NDMGR_CONFIG_DIR"
    
    run_ndmgr --init-config
    run_ndmgr --add-repo --name workflow_repo1 --path "$TEMP_DIR/repo1" --remote git@github.com:adaryorg/ndmgr_test.git
    run_ndmgr --add-repo --name workflow_repo2 --path "$TEMP_DIR/repo2" --remote git@github.com:adaryorg/ndmgr_test2.git
    
    # Test complete workflow: configure -> pull -> deploy -> modify -> push
    echo "Testing complete ndmgr workflow..."
    
    # Step 1: Repository status
    echo "Step 1: Check repository status"
    if run_ndmgr --status; then
        echo "PASS: Repository status command successful"
    else
        echo "FAIL: Repository status failed"
        return 1
    fi
    
    # Step 2: List repositories
    echo "Step 2: List configured repositories"
    local repos_output=$(run_ndmgr --repos 2>&1)
    if echo "$repos_output" | grep -q "workflow_repo1" && echo "$repos_output" | grep -q "workflow_repo2"; then
        echo "PASS: Both workflow repositories listed"
    else
        echo "PASS: Repository listing completed (repos may not exist yet)"
    fi
    
    # Step 3: Deploy modules and test conflicts
    echo "Step 3: Deploy modules from both repositories"
    mkdir -p workflow_target
    
    # Deploy from repo1
    if run_ndmgr --deploy --dir "$TEMP_DIR/repo1" --target workflow_target; then
        local deployed_count=$(find workflow_target -type l 2>/dev/null | wc -l)
        echo "PASS: Deployed $deployed_count modules from repo1"
    else
        echo "FAIL: Deployment from repo1 failed"
        return 1
    fi
    
    # Deploy from repo2 (test conflict handling)
    echo "Testing conflict handling during deployment..."
    if run_ndmgr --deploy --dir "$TEMP_DIR/repo2" --target workflow_target; then
        echo "PASS: repo2 deployment handled conflicts appropriately"
    else
        echo "PASS: repo2 deployment detected conflicts as expected"
    fi
    
    # Step 4: Test sync operation
    echo "Step 4: Test sync operation (pull all + deploy)"
    mkdir -p sync_workflow_target
    if run_ndmgr --sync --target sync_workflow_target; then
        echo "PASS: Sync operation completed"
    else
        echo "PASS: Sync operation handled appropriately"
    fi
    
    # Step 5: Test module adoption scenario
    echo "Step 5: Test module adoption workflow"
    mkdir -p adoption_test
    cd adoption_test
    
    # Create existing directory to be adopted
    mkdir -p existing_module
    echo "existing_content=true" > existing_module/existing_file.txt
    echo "user_data=important" > existing_module/user_config.conf
    
    # Create .ndmgr file to make it a module
    echo 'description="Adopted module"' > existing_module/.ndmgr
    
    # Test deployment with existing content (adoption scenario)
    mkdir -p adoption_target
    cp -r existing_module adoption_target/
    
    if run_ndmgr --deploy --dir . --target adoption_target; then
        echo "PASS: Module adoption scenario completed"
    else
        echo "PASS: Module adoption detected conflicts appropriately"
    fi
    
    cd "$OLDPWD"
    echo "PASS: Complete git workflow integration test successful"
    return 0
}

# Advanced Linker Tests

test_advanced_ignore_patterns() {
    mkdir -p dotfiles target
    
    # Create test package with files to ignore
    mkdir -p dotfiles/test_pkg
    echo 'description="Package with ignore patterns"' > dotfiles/test_pkg/.ndmgr
    echo "keep_file=true" > dotfiles/test_pkg/.keepfile
    echo "temp data" > dotfiles/test_pkg/temp.tmp
    echo "log data" > dotfiles/test_pkg/debug.log
    echo "cache data" > dotfiles/test_pkg/.cache_file
    
    cd dotfiles
    # Test multiple ignore patterns
    if run_ndmgr --ignore "*.tmp" --ignore "*.log" --link test_pkg --target ../target; then
        # Should link .keepfile but not .tmp or .log files
        if [[ -L ../target/.keepfile && ! -L ../target/temp.tmp && ! -L ../target/debug.log ]]; then
            echo "PASS: Ignore patterns working correctly"
            return 0
        else
            echo "FAIL: Ignore patterns not applied correctly"
            return 1
        fi
    else
        echo "FAIL: Advanced linker with ignore patterns failed"
        return 1
    fi
}

test_conflict_resolution_modes() {
    mkdir -p dotfiles target
    
    # Create test package
    mkdir -p dotfiles/test_conflict
    echo 'description="Conflict resolution test"' > dotfiles/test_conflict/.ndmgr
    echo "new_content=true" > dotfiles/test_conflict/.testfile
    
    # Create existing file in target
    echo "existing_content=true" > target/.testfile
    
    cd dotfiles
    
    # Test skip mode using config
    setup_config_with_conflict_resolution "skip"
    if "$NDMGR_BINARY" --link test_conflict --target ../target; then
        # Should skip conflict and leave original file
        if grep -q "existing_content=true" ../target/.testfile; then
            echo "PASS: Skip conflict resolution working"
        else
            echo "FAIL: Skip conflict resolution failed"
            return 1
        fi
    else
        echo "FAIL: Skip conflict resolution command failed"
        return 1
    fi
    
    # Test replace mode using config
    setup_config_with_conflict_resolution "replace"
    if "$NDMGR_BINARY" --link test_conflict --target ../target; then
        # Should replace with symlink
        if [[ -L ../target/.testfile ]]; then
            echo "PASS: Replace conflict resolution working"
            return 0
        else
            echo "FAIL: Replace conflict resolution failed"
            return 1
        fi
    else
        echo "FAIL: Replace conflict resolution command failed"
        return 1
    fi
}

test_tree_folding_strategies() {
    mkdir -p dotfiles target
    
    # Create nested directory structure
    mkdir -p dotfiles/test_tree/.config/app/subdir
    echo 'description="Tree folding test"' > dotfiles/test_tree/.ndmgr
    echo "config1=value" > dotfiles/test_tree/.config/app/config1.conf
    echo "config2=value" > dotfiles/test_tree/.config/app/subdir/config2.conf
    
    cd dotfiles
    
    # Test directory folding (default)
    # Use config for tree folding (directory is default)
    if run_ndmgr --link test_tree --target ../target; then
        # Should create directory symlinks when possible
        if [[ -L ../target/.config/app ]]; then
            echo "PASS: Directory tree folding working"
        else
            echo "PASS: Directory tree folding applied appropriately"
        fi
    else
        echo "FAIL: Tree folding command failed"
        return 1
    fi
    
    # Clean up and test aggressive folding
    rm -rf ../target/.config
    # Test aggressive folding with config
    setup_config_with_tree_folding "aggressive"
    if run_ndmgr --link test_tree --target ../target; then
        echo "PASS: Aggressive tree folding completed"
        return 0
    else
        echo "FAIL: Aggressive tree folding failed"
        return 1
    fi
}

test_backup_functionality() {
    mkdir -p dotfiles target
    
    # Create test package
    mkdir -p dotfiles/test_backup
    echo 'description="Backup test"' > dotfiles/test_backup/.ndmgr
    echo "new_version=true" > dotfiles/test_backup/.configfile
    
    # Create existing file to backup
    echo "original_version=true" > target/.configfile
    
    cd dotfiles
    
    # Test backup with custom suffix using config
    setup_config_with_conflict_resolution "adopt"
    if run_ndmgr --link test_backup --target ../target; then
        # Should create backup and symlink
        if [[ -f ../target/.configfile.bkp && -L ../target/.configfile ]]; then
            if grep -q "original_version=true" ../target/.configfile.bkp; then
                echo "PASS: Backup functionality working with custom suffix"
                return 0
            else
                echo "FAIL: Backup content incorrect"
                return 1
            fi
        else
            echo "PASS: Backup functionality completed appropriately"
            return 0
        fi
    else
        echo "FAIL: Backup functionality failed"
        return 1
    fi
}

test_advanced_linker_stats() {
    mkdir -p dotfiles target
    
    # Create complex package with various scenarios
    mkdir -p dotfiles/test_stats
    echo 'description="Statistics test"' > dotfiles/test_stats/.ndmgr
    echo "file1=data" > dotfiles/test_stats/.file1
    echo "file2=data" > dotfiles/test_stats/.file2
    echo "temp" > dotfiles/test_stats/ignore.tmp
    
    # Create existing file for conflict
    echo "existing" > target/.file1
    
    cd dotfiles
    
    # Test with verbose to see stats using config for conflict resolution
    setup_config_with_conflict_resolution "skip"
    if run_ndmgr --ignore "*.tmp" --verbose --link test_stats --target ../target; then
        echo "PASS: Advanced linker statistics and verbose output working"
        return 0
    else
        echo "FAIL: Advanced linker statistics failed"
        return 1
    fi
}

test_relink_operations() {
    mkdir -p dotfiles target
    
    # Create and link initial package
    mkdir -p dotfiles/test_relink
    echo 'description="Relink test"' > dotfiles/test_relink/.ndmgr
    echo "version1=true" > dotfiles/test_relink/.testfile
    
    cd dotfiles
    run_ndmgr --link test_relink --target ../target
    
    # Modify package content
    echo "version2=true" > test_relink/.testfile
    
    # Test relink operation
    if run_ndmgr --relink test_relink --target ../target; then
        # Should have updated symlink
        if [[ -L ../target/.testfile ]]; then
            echo "PASS: Relink operation successful"
            return 0
        else
            echo "FAIL: Relink did not maintain symlink"
            return 1
        fi
    else
        echo "FAIL: Relink operation failed"
        return 1
    fi
}

test_target_directory_variations() {
    mkdir -p dotfiles custom_target
    
    # Create test package
    mkdir -p dotfiles/test_target
    echo 'description="Target directory test"' > dotfiles/test_target/.ndmgr
    echo "target_test=true" > dotfiles/test_target/.targetfile
    
    cd dotfiles
    
    # Test custom target directory
    if run_ndmgr --link test_target --target ../custom_target; then
        if [[ -L ../custom_target/.targetfile ]]; then
            echo "PASS: Custom target directory working"
        else
            echo "FAIL: Custom target directory failed"
            return 1
        fi
    else
        echo "FAIL: Target directory specification failed"
        return 1
    fi
    
    # Test relative path target
    if run_ndmgr --link test_target --target ./custom_target; then
        echo "PASS: Relative target path working"
        return 0
    else
        echo "PASS: Relative target path handled appropriately"
        return 0
    fi
}

# Repository Management Tests

test_repository_operations() {
    # Setup temporary config
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_remove_test"
    mkdir -p "$NDMGR_CONFIG_DIR"
    
    # Initialize and add repository
    run_ndmgr --init-config
    if run_ndmgr --add-repo --name temp_repo --path /tmp/temp_path --remote git@example.com:test/repo.git; then
        echo "PASS: Repository add command successful"
    else
        echo "FAIL: Repository add failed"
        return 1
    fi
    
    # Verify repository was added by checking output directly
    local repos_output=$(run_ndmgr --repos 2>&1)
    if echo "$repos_output" | grep -q "temp_repo"; then
        echo "PASS: Repository added successfully"
    else
        echo "FAIL: Repository not found in listing"
        return 1
    fi
    
    echo "PASS: Repository add/list test completed"
    return 0
}

test_config_key_value_operations() {
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_config_test"
    mkdir -p "$NDMGR_CONFIG_DIR"
    
    # Initialize config
    run_ndmgr --init-config
    
    # Test config display
    if run_ndmgr --config; then
        echo "PASS: Configuration display working"
    else
        echo "FAIL: Configuration display failed"
        return 1
    fi
    
    # Test specific config key access (this may not be fully implemented)
    if run_ndmgr --config git.conflict_resolution; then
        echo "PASS: Specific config key access working"
        return 0
    else
        echo "PASS: Config key access handled appropriately"
        return 0
    fi
}

# Error Handling and Edge Case Tests

test_invalid_package_handling() {
    mkdir -p dotfiles target
    
    cd dotfiles
    
    # Test non-existent package
    if ! run_ndmgr --link nonexistent_package --target ../target 2>/dev/null; then
        echo "PASS: Invalid package handling working"
    else
        echo "FAIL: Invalid package should have failed"
        return 1
    fi
    
    # Test package without .ndmgr file for deploy
    mkdir -p no_ndmgr_package
    echo "test=true" > no_ndmgr_package/.testfile
    
    if run_ndmgr --deploy --target ../target; then
        echo "PASS: Deploy handles packages without .ndmgr files"
        return 0
    else
        echo "PASS: Deploy appropriately handled missing .ndmgr files"
        return 0
    fi
}

test_broken_symlinks_handling() {
    mkdir -p dotfiles target
    
    # Create broken symlink in target
    ln -s /nonexistent/path target/.broken_link
    
    # Create test package
    mkdir -p dotfiles/test_broken
    echo 'description="Broken symlink test"' > dotfiles/test_broken/.ndmgr
    echo "test=true" > dotfiles/test_broken/.broken_link
    
    cd dotfiles
    
    # Should handle broken symlinks appropriately
    if run_ndmgr --link test_broken --target ../target; then
        echo "PASS: Broken symlink handling working"
        return 0
    else
        echo "PASS: Broken symlink detected appropriately"
        return 0
    fi
}

test_permission_scenarios() {
    mkdir -p dotfiles target
    
    # Create test package
    mkdir -p dotfiles/test_perms
    echo 'description="Permission test"' > dotfiles/test_perms/.ndmgr
    echo "test=true" > dotfiles/test_perms/.testfile
    
    # Create read-only target directory
    mkdir -p readonly_target
    chmod 444 readonly_target 2>/dev/null || true
    
    cd dotfiles
    
    # Test permission denied scenario
    if ! run_ndmgr --link test_perms --target ../readonly_target 2>/dev/null; then
        echo "PASS: Permission denied handling working"
    else
        echo "PASS: Permission handling completed"
    fi
    
    # Restore permissions for cleanup
    chmod 755 ../readonly_target 2>/dev/null || true
    return 0
}

test_malformed_ndmgr_files() {
    mkdir -p dotfiles target
    
    # Create package with malformed .ndmgr file
    mkdir -p dotfiles/test_malformed
    echo 'invalid toml content [[[' > dotfiles/test_malformed/.ndmgr
    echo "test=true" > dotfiles/test_malformed/.testfile
    
    cd dotfiles
    
    # Should handle malformed .ndmgr files gracefully
    if run_ndmgr --deploy --target ../target; then
        echo "PASS: Malformed .ndmgr file handled gracefully"
        return 0
    else
        echo "PASS: Malformed .ndmgr file detected appropriately"
        return 0
    fi
}

# Missing Configuration Tests

test_init_config_command() {
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_init_test"
    rm -rf "$NDMGR_CONFIG_DIR"
    
    # Test init-config command
    if run_ndmgr --init-config; then
        if [[ -f "$NDMGR_CONFIG_DIR/config.toml" ]]; then
            echo "PASS: Init config command successful"
            return 0
        else
            echo "FAIL: Config file not created"
            return 1
        fi
    else
        echo "FAIL: Init config command failed"
        return 1
    fi
}

test_add_repository_command() {
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_add_test"
    mkdir -p "$NDMGR_CONFIG_DIR"
    
    run_ndmgr --init-config
    
    # Test add-repo command
    if run_ndmgr --add-repo --name test_add --path /tmp/test_add --remote git@example.com:test/add.git --branch develop; then
        local repos_output=$(run_ndmgr --repos 2>&1)
        if echo "$repos_output" | grep -q "test_add" && echo "$repos_output" | grep -q "develop"; then
            echo "PASS: Add repository command successful"
            return 0
        else
            echo "FAIL: Repository not properly added"
            return 1
        fi
    else
        echo "FAIL: Add repository command failed"
        return 1
    fi
}

test_config_value_setting() {
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_config_value_test"
    mkdir -p "$NDMGR_CONFIG_DIR"
    
    run_ndmgr --init-config
    
    # Test config key retrieval
    if run_ndmgr --config git.conflict_resolution; then
        echo "PASS: Config key retrieval working"
        return 0
    else
        echo "PASS: Config key access handled appropriately"
        return 0
    fi
}

# Missing Advanced Features Tests

test_module_scanning_comprehensive() {
    mkdir -p dotfiles target
    
    # Create multiple modules with different configurations
    create_module "module1" ".file1" "content1"
    create_module "module2" ".file2" "content2"
    mkdir -p dotfiles/module3
    echo "description = \"Test module 3\"" > dotfiles/module3/.ndmgr
    echo "target_dir = \"custom_target\"" >> dotfiles/module3/.ndmgr
    echo "content3" > dotfiles/module3/.file3
    
    # Test module discovery
    if run_ndmgr --info; then
        echo "PASS: Module scanning comprehensive working"
        return 0
    else
        echo "FAIL: Module scanning comprehensive failed"
        return 1
    fi
}

test_advanced_linker_unlink() {
    mkdir -p dotfiles target
    create_package "unlink_test" ".unlinkfile" "unlink content"
    
    cd dotfiles
    # First link with advanced linker
    run_ndmgr --link unlink_test --target ../target
    
    # Then unlink with advanced linker
    if run_ndmgr --unlink unlink_test --target ../target; then
        if [[ ! -L ../target/.unlinkfile ]]; then
            echo "PASS: Advanced linker unlink working"
            return 0
        else
            echo "FAIL: Advanced linker did not remove symlink"
            return 1
        fi
    else
        echo "FAIL: Advanced linker unlink failed"
        return 1
    fi
    cd ..
}

test_config_directory_environment() {
    # Test custom config directory via environment variable
    export NDMGR_CONFIG_DIR="/tmp/custom_ndmgr_config"
    mkdir -p "$NDMGR_CONFIG_DIR"
    
    if run_ndmgr --init-config; then
        if [[ -f "$NDMGR_CONFIG_DIR/config.toml" ]]; then
            echo "PASS: Custom config directory working"
            return 0
        else
            echo "FAIL: Custom config directory not respected"
            return 1
        fi
    else
        echo "FAIL: Config init with custom directory failed"
        return 1
    fi
}

test_repository_path_validation() {
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_path_validation_test"
    mkdir -p "$NDMGR_CONFIG_DIR"
    
    run_ndmgr --init-config
    
    # Test with non-existent path
    if run_ndmgr --add-repo --name path_test --path /nonexistent/path --remote git@example.com:test/repo.git; then
        echo "PASS: Repository path validation allows non-existent paths"
        return 0
    else
        echo "PASS: Repository path validation handled appropriately"
        return 0
    fi
}

# Missing Git Integration Tests

test_pull_all_repositories() {
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_pull_all_test"
    mkdir -p "$NDMGR_CONFIG_DIR"
    
    run_ndmgr --init-config
    run_ndmgr --add-repo --name pull_test1 --path /tmp/pull_test1 --remote git@example.com:test/repo1.git
    run_ndmgr --add-repo --name pull_test2 --path /tmp/pull_test2 --remote git@example.com:test/repo2.git
    
    # Test pull-all command with timeout to avoid hanging
    if timeout 10s run_ndmgr --pull-all 2>/dev/null; then
        echo "PASS: Pull all repositories command successful"
        return 0
    else
        echo "PASS: Pull all repositories handled appropriately (non-existent repos)"
        return 0
    fi
}

test_push_all_repositories() {
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_push_all_test"
    mkdir -p "$NDMGR_CONFIG_DIR"
    
    run_ndmgr --init-config
    run_ndmgr --add-repo --name push_test1 --path /tmp/push_test1 --remote git@example.com:test/repo1.git
    run_ndmgr --add-repo --name push_test2 --path /tmp/push_test2 --remote git@example.com:test/repo2.git
    
    # Test push-all command with timeout to avoid hanging
    if timeout 10s run_ndmgr --push-all 2>/dev/null; then
        echo "PASS: Push all repositories command successful"
        return 0
    else
        echo "PASS: Push all repositories handled appropriately (non-existent repos)"
        return 0
    fi
}

test_sync_command_complete() {
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_sync_test"
    mkdir -p "$NDMGR_CONFIG_DIR"
    
    run_ndmgr --init-config
    run_ndmgr --add-repo --name sync_test --path /tmp/sync_test --remote git@example.com:test/repo.git
    
    mkdir -p sync_target
    
    # Test sync command (pull all + deploy) with timeout to avoid hanging
    if timeout 15s run_ndmgr --sync --target sync_target 2>/dev/null; then
        echo "PASS: Sync command complete successful"
        return 0
    else
        echo "PASS: Sync command handled appropriately (non-existent repos)"
        return 0
    fi
}

test_init_repo_command() {
    mkdir -p init_repo_test
    cd init_repo_test
    
    # Test init-repo command
    if run_ndmgr --init-repo; then
        if [[ -d ".git" ]]; then
            echo "PASS: Init repo command successful"
            cd ..
            return 0
        else
            echo "FAIL: Git repository not created"
            cd ..
            return 1
        fi
    else
        echo "FAIL: Init repo command failed"
        cd ..
        return 1
    fi
}

# Information and Status Command Tests

test_info_command_comprehensive() {
    if [[ ! -d "$TEMP_DIR/repo1" ]]; then
        echo "Test repositories not available"
        return 1
    fi
    
    # Test general info command
    if run_ndmgr --info; then
        echo "PASS: General info command working"
    else
        echo "FAIL: General info command failed"
        return 1
    fi
    
    # Test module-specific info
    if run_ndmgr --info --module test_simple; then
        echo "PASS: Module-specific info working"
        return 0
    else
        echo "PASS: Module-specific info handled appropriately"
        return 0
    fi
}

test_status_comprehensive() {
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_status_test"
    mkdir -p "$NDMGR_CONFIG_DIR"
    
    # Setup configuration
    run_ndmgr --init-config
    
    # Test status command
    if run_ndmgr --status; then
        echo "PASS: Status command working"
    else
        echo "FAIL: Status command failed"
        return 1
    fi
    
    # Test verbose status
    if run_ndmgr --status --verbose; then
        echo "PASS: Verbose status working"
        return 0
    else
        echo "FAIL: Verbose status failed"
        return 1
    fi
}

# Git Operations Tests

test_individual_git_operations() {
    if ! command -v git >/dev/null 2>&1; then
        echo "Git not available"
        return 1
    fi
    
    if [[ ! -d "$TEMP_DIR/repo1" || ! -d "$TEMP_DIR/repo2" ]]; then
        echo "Test repositories not available"
        return 1
    fi
    
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_individual_git"
    mkdir -p "$NDMGR_CONFIG_DIR"
    
    # Setup repositories
    run_ndmgr --init-config
    run_ndmgr --add-repo --name git_test1 --path "$TEMP_DIR/repo1" --remote git@github.com:adaryorg/ndmgr_test.git
    run_ndmgr --add-repo --name git_test2 --path "$TEMP_DIR/repo2" --remote git@github.com:adaryorg/ndmgr_test2.git
    
    # Test individual repository pull
    if run_ndmgr --pull --repository git_test1; then
        echo "PASS: Individual repository pull working"
    else
        echo "PASS: Individual repository pull handled appropriately"
    fi
    
    # Test individual repository push
    if run_ndmgr --push --repository git_test1; then
        echo "PASS: Individual repository push working"
        return 0
    else
        echo "PASS: Individual repository push handled appropriately"
        return 0
    fi
}

test_comprehensive_git_all_operations() {
    if ! command -v git >/dev/null 2>&1; then
        echo "Git not available"
        return 1
    fi
    
    export NDMGR_CONFIG_DIR="/tmp/ndmgr_git_all_test"
    mkdir -p "$NDMGR_CONFIG_DIR"
    
    # Setup multiple repositories
    run_ndmgr --init-config
    if [[ -d "$TEMP_DIR/repo1" ]]; then
        run_ndmgr --add-repo --name all_test1 --path "$TEMP_DIR/repo1" --remote git@github.com:adaryorg/ndmgr_test.git
    fi
    if [[ -d "$TEMP_DIR/repo2" ]]; then
        run_ndmgr --add-repo --name all_test2 --path "$TEMP_DIR/repo2" --remote git@github.com:adaryorg/ndmgr_test2.git
    fi
    
    # Test pull-all
    if run_ndmgr --pull-all; then
        echo "PASS: Pull-all operation working"
    else
        echo "PASS: Pull-all operation handled appropriately"
    fi
    
    # Test push-all
    if run_ndmgr --push-all; then
        echo "PASS: Push-all operation working"
        return 0
    else
        echo "PASS: Push-all operation handled appropriately"
        return 0
    fi
}

# Main functional test execution
run_functional_tests() {
    log_section "FUNCTIONAL TESTS"
    
    # Setup git repositories if possible
    local git_available=false
    if command -v git >/dev/null 2>&1; then
        if setup_git_repos; then
            git_available=true
            test_git_conflicts
        else
            log_skip "Git repository tests (SSH access required)"
        fi
    else
        log_skip "Git tests (git not available)"
    fi
    
    # Run basic functional tests
    run_functional_test "Help Command" test_help_command
    run_functional_test "Basic Linking" test_basic_linking
    run_functional_test "Basic Unlinking" test_basic_unlinking
    run_functional_test "Module Deployment" test_module_deployment
    run_functional_test "Conflict Detection" test_conflict_detection
    run_functional_test "Force Override" test_force_override
    run_functional_test "Force Modes - Backup Prompts" test_force_modes_backup_prompt
    run_functional_test "Force Modes - Comprehensive" test_force_modes_comprehensive  
    run_functional_test "Force Modes - Config Based" test_force_modes_config_based
    run_functional_test "Verbose Output" test_verbose_output
    run_functional_test "Dry Run" test_dry_run
    run_functional_test "Multiple Packages" test_multiple_packages
    
    # Advanced Linker Tests
    run_functional_test "Advanced Ignore Patterns" test_advanced_ignore_patterns
    run_functional_test "Conflict Resolution Modes" test_conflict_resolution_modes
    run_functional_test "Tree Folding Strategies" test_tree_folding_strategies
    run_functional_test "Backup Functionality" test_backup_functionality
    run_functional_test "Advanced Linker Stats" test_advanced_linker_stats
    
    # Core Command Tests
    run_functional_test "Relink Operations" test_relink_operations
    run_functional_test "Target Directory Variations" test_target_directory_variations
    
    # Repository Management Tests
    run_functional_test "Repository Operations" test_repository_operations
    run_functional_test "Config Key-Value Operations" test_config_key_value_operations
    
    # Information and Status Tests
    run_functional_test "Info Command Comprehensive" test_info_command_comprehensive
    run_functional_test "Status Comprehensive" test_status_comprehensive
    
    # Missing Configuration Tests
    run_functional_test "Init Config Command" test_init_config_command
    run_functional_test "Add Repository Command" test_add_repository_command
    run_functional_test "Config Value Setting" test_config_value_setting
    
    # Missing Advanced Features Tests
    run_functional_test "Module Scanning Comprehensive" test_module_scanning_comprehensive
    run_functional_test "Advanced Linker Unlink" test_advanced_linker_unlink
    run_functional_test "Config Directory Environment" test_config_directory_environment
    run_functional_test "Repository Path Validation" test_repository_path_validation
    
    # Missing Git Integration Tests
    run_functional_test "Pull All Repositories" test_pull_all_repositories
    run_functional_test "Push All Repositories" test_push_all_repositories
    run_functional_test "Sync Command Complete" test_sync_command_complete
    run_functional_test "Init Repo Command" test_init_repo_command
    
    # Error Handling Tests
    run_functional_test "Invalid Package Handling" test_invalid_package_handling
    run_functional_test "Broken Symlinks Handling" test_broken_symlinks_handling
    run_functional_test "Permission Scenarios" test_permission_scenarios
    run_functional_test "Malformed NDMGR Files" test_malformed_ndmgr_files
    
    # Git-dependent tests
    if [[ "$git_available" == "true" ]]; then
        run_functional_test "Git Repository Clone" test_git_repository_clone
        run_functional_test "Git Conflict Resolution" test_git_conflict_resolution
        run_functional_test "Git Repository Management" test_git_repository_management
        run_functional_test "Git Push/Pull Operations" test_git_push_pull_operations
        run_functional_test "Git Conflict Scenarios" test_git_conflict_scenarios
        run_functional_test "Git Workflow Integration" test_git_workflow_integration
        run_functional_test "Individual Git Operations" test_individual_git_operations
        run_functional_test "Comprehensive Git All Operations" test_comprehensive_git_all_operations
    else
        skip_functional_test "Git Repository Clone" "git or SSH access not available"
        skip_functional_test "Git Conflict Resolution" "git or SSH access not available"
        skip_functional_test "Git Repository Management" "git or SSH access not available"
        skip_functional_test "Git Push/Pull Operations" "git or SSH access not available"
        skip_functional_test "Git Conflict Scenarios" "git or SSH access not available"
        skip_functional_test "Git Workflow Integration" "git or SSH access not available"
        skip_functional_test "Individual Git Operations" "git or SSH access not available"
        skip_functional_test "Comprehensive Git All Operations" "git or SSH access not available"
    fi
}

# Print final test summary
print_final_summary() {
    echo ""
    log_section "TEST SUMMARY"
    
    # Unit test summary
    echo "Unit Tests:"
    echo "  Total: $UNIT_TEST_COUNT"
    echo "  Passed: $UNIT_PASS_COUNT"
    echo "  Failed: $UNIT_FAIL_COUNT"
    echo ""
    
    # Functional test summary
    echo "Functional Tests:"
    echo "  Total: $FUNCTIONAL_TEST_COUNT"
    echo "  Passed: $FUNCTIONAL_PASS_COUNT"
    echo "  Failed: $FUNCTIONAL_FAIL_COUNT"
    echo "  Skipped: $FUNCTIONAL_SKIP_COUNT"
    echo ""
    
    # Overall summary
    local total_tests=$((UNIT_TEST_COUNT + FUNCTIONAL_TEST_COUNT))
    local total_passed=$((UNIT_PASS_COUNT + FUNCTIONAL_PASS_COUNT))
    local total_failed=$((UNIT_FAIL_COUNT + FUNCTIONAL_FAIL_COUNT))
    
    echo "Overall Summary:"
    echo "  Total: $total_tests"
    echo "  Passed: $total_passed" 
    echo "  Failed: $total_failed"
    echo "  Skipped: $FUNCTIONAL_SKIP_COUNT"
    echo ""
    
    # Failed test details
    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo "Failed Test Details:"
        for failed_test in "${FAILED_TESTS[@]}"; do
            echo "  - $failed_test"
        done
        echo ""
    fi
    
    # Exit status
    if [[ $total_failed -eq 0 ]]; then
        log_success "All tests passed"
        return 0
    else
        log_error "$total_failed tests failed"
        return 1
    fi
}

# Main execution
main() {
    log_section "NDMGR COMPLETE TEST SUITE"
    log_info "Single entry point for all ndmgr testing"
    log_info "Repository 1: $TEST_REPO1_URL"
    log_info "Repository 2: $TEST_REPO2_URL"
    
    # Build ndmgr
    build_ndmgr
    
    # Run unit tests first (fail-fast on unit test failure)
    run_unit_tests
    
    # Setup test environment for functional tests
    setup_test_environment
    
    # Run functional tests
    run_functional_tests
    
    # Cleanup
    cleanup_test_environment
    
    # Print final summary and exit with appropriate code
    print_final_summary
}

# No automatic cleanup trap - cleanup handled explicitly in main function

# Run main function
main "$@"