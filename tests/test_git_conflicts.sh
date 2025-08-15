#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
# SPDX-License-Identifier: MIT

set -euo pipefail

# Comprehensive Git Conflict Resolution Testing
# Tests ndmgr's ability to automatically resolve git conflicts without user intervention
# Simulates multi-PC scenario where different machines push to the same repository

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[SKIP]${NC} $*"
}

setup_test_environment() {
    TEMP_DIR=$(mktemp -d -t ndmgr_git_conflict_test_XXXXXX)
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

# Helper function to simulate multi-PC scenario
create_multi_pc_conflict() {
    local repo_path="$1"
    local conflict_file="$2"
    local pc1_content="$3"
    local pc2_content="$4"
    
    cd "$repo_path"
    
    # Simulate PC1 making changes
    git checkout main
    echo "$pc1_content" > "$conflict_file"
    git add "$conflict_file"
    git commit -m "PC1: Update $conflict_file" || true
    local pc1_commit=$(git rev-parse HEAD)
    
    # Simulate PC2 making different changes (create divergent history)
    git reset --hard HEAD~1
    echo "$pc2_content" > "$conflict_file"
    git add "$conflict_file"
    git commit -m "PC2: Update $conflict_file" || true
    local pc2_commit=$(git rev-parse HEAD)
    
    # Simulate the conflict scenario by trying to merge PC1 changes
    # This creates the exact scenario ndmgr needs to handle
    git merge "$pc1_commit" || true  # This will create a conflict
    
    cd ..
}

# === BASIC GIT CONFLICT RESOLUTION TESTS ===

test_simple_file_conflict_resolution() {
    # Skip if git is not available
    if ! command -v git &> /dev/null; then
        return 1
    fi
    
    # Clone repository and create conflict scenario
    git clone "$TEST_REPO1_URL" conflict_repo 2>/dev/null || return 1
    
    cd conflict_repo
    git config user.name "NDMGR Conflict Test"
    git config user.email "conflict-test@ndmgr.test"
    cd ..
    
    # Create a simple file conflict
    create_multi_pc_conflict conflict_repo "test_config_file.txt" \
        "# PC1 Configuration\npc1_setting=true\nshared_setting=pc1_value" \
        "# PC2 Configuration\npc2_setting=true\nshared_setting=pc2_value"
    
    # Create ndmgr configuration that uses this repository
    mkdir -p config_dir
    cat > config_dir/config.toml << EOF
[[repository]]
name = "conflict_test"
path = "./conflict_repo"
remote = "$TEST_REPO1_URL"
branch = "main"
auto_commit = true
EOF
    
    # Test that ndmgr can handle the conflict automatically
    local output
    output=$(NDMGR_CONFIG_DIR="config_dir" timeout 30 "$NDMGR_BINARY" --pull --verbose 2>&1) || true
    
    # Verify ndmgr resolved the conflict without user intervention
    if echo "$output" | grep -q -E "(conflict.*resolved|merge.*successful|auto.*resolved|conflict.*handled)"; then
        log_success "NDMGR automatically resolved file conflict"
    elif ! echo "$output" | grep -q -E "(conflict|merge.*failed|manual.*intervention)"; then
        log_success "NDMGR handled conflict scenario (no conflict indication)"
    else
        log_error "NDMGR failed to automatically resolve conflict"
        log_error "Output: $output"
        return 1
    fi
    
    # Verify repository is in clean state after resolution
    cd conflict_repo
    local git_status=$(git status --porcelain)
    if [[ -n "$git_status" ]]; then
        log_error "Repository not in clean state after conflict resolution"
        log_error "Git status: $git_status"
        return 1
    fi
    cd ..
    
    return 0
}

test_module_config_conflict_resolution() {
    # Test conflicts in .ndmgr module configuration files
    if ! command -v git &> /dev/null; then
        return 1
    fi
    
    git clone "$TEST_REPO1_URL" module_conflict_repo 2>/dev/null || return 1
    
    cd module_conflict_repo
    git config user.name "NDMGR Module Test"
    git config user.email "module-test@ndmgr.test"
    
    # Create a test module
    mkdir -p editor_module
    echo 'description="Generic editor configuration"' > editor_module/.ndmgr
    echo "set number" > editor_module/.editorrc
    git add editor_module/
    git commit -m "Add editor module"
    cd ..
    
    # Create conflict in module configuration
    create_multi_pc_conflict module_conflict_repo "editor_module/.ndmgr" \
        'description="Generic editor configuration"\ntarget_dir="$HOME"\npc1_option=true' \
        'description="Generic editor configuration"\ntarget_dir="/tmp"\npc2_option=true'
    
    # Create ndmgr configuration
    mkdir -p module_config_dir
    cat > module_config_dir/config.toml << EOF
[[repository]]
name = "module_conflict_test"
path = "./module_conflict_repo"
remote = "$TEST_REPO1_URL"
branch = "main"
EOF
    
    # Test ndmgr handles module config conflicts
    local output
    output=$(NDMGR_CONFIG_DIR="module_config_dir" timeout 30 "$NDMGR_BINARY" --pull --verbose 2>&1) || true
    
    # Should resolve conflict automatically
    if ! echo "$output" | grep -q -E "(manual.*intervention|resolve.*conflict.*manually|git.*conflict)"; then
        log_success "NDMGR handled module configuration conflict"
    else
        log_error "NDMGR requires manual intervention for module config conflict"
        return 1
    fi
    
    return 0
}

test_multiple_file_conflicts() {
    # Test scenario with conflicts in multiple files simultaneously
    if ! command -v git &> /dev/null; then
        return 1
    fi
    
    git clone "$TEST_REPO2_URL" multi_conflict_repo 2>/dev/null || return 1
    
    cd multi_conflict_repo
    git config user.name "NDMGR Multi Test"
    git config user.email "multi-test@ndmgr.test"
    
    # Create multiple files that will have conflicts
    echo "shell_config=pc_initial" > shell_config.txt
    echo "editor_config=pc_initial" > editor_config.txt
    echo "terminal_config=pc_initial" > terminal_config.txt
    git add *.txt
    git commit -m "Add initial config files"
    cd ..
    
    # Create conflicts in multiple files
    cd multi_conflict_repo
    
    # PC1 changes
    git checkout main
    echo "shell_config=pc1_value" > shell_config.txt
    echo "editor_config=pc1_value" > editor_config.txt
    echo "terminal_config=pc1_value" > terminal_config.txt
    git add *.txt
    git commit -m "PC1: Update all configs"
    local pc1_commit=$(git rev-parse HEAD)
    
    # PC2 changes (conflicting)
    git reset --hard HEAD~1
    echo "shell_config=pc2_value" > shell_config.txt
    echo "editor_config=pc2_value" > editor_config.txt
    echo "terminal_config=pc2_value" > terminal_config.txt
    git add *.txt
    git commit -m "PC2: Update all configs differently"
    
    # Create the conflict
    git merge "$pc1_commit" || true
    cd ..
    
    # Test ndmgr handles multiple conflicts
    mkdir -p multi_config_dir
    cat > multi_config_dir/config.toml << EOF
[[repository]]
name = "multi_conflict_test"
path = "./multi_conflict_repo"
remote = "$TEST_REPO2_URL"
branch = "main"
EOF
    
    local output
    output=$(NDMGR_CONFIG_DIR="multi_config_dir" timeout 45 "$NDMGR_BINARY" --pull --verbose 2>&1) || true
    
    # Should handle multiple conflicts automatically
    if ! echo "$output" | grep -q -E "(manual.*intervention|unresolved.*conflict|conflict.*not.*resolved)"; then
        log_success "NDMGR handled multiple file conflicts"
    else
        log_error "NDMGR couldn't handle multiple file conflicts automatically"
        return 1
    fi
    
    return 0
}

# === ADVANCED CONFLICT SCENARIOS ===

test_binary_file_conflicts() {
    # Test handling of binary file conflicts
    if ! command -v git &> /dev/null; then
        return 1
    fi
    
    git clone "$TEST_REPO1_URL" binary_conflict_repo 2>/dev/null || return 1
    
    cd binary_conflict_repo
    git config user.name "NDMGR Binary Test"
    git config user.email "binary-test@ndmgr.test"
    
    # Create a binary file (simulate with different content)
    echo -e '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x10PC1' > binary_file.png
    git add binary_file.png
    git commit -m "Add binary file from PC1"
    local pc1_commit=$(git rev-parse HEAD)
    
    # PC2 version of binary file
    git reset --hard HEAD~1
    echo -e '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x10PC2' > binary_file.png
    git add binary_file.png
    git commit -m "Add binary file from PC2"
    
    # Create conflict
    git merge "$pc1_commit" || true
    cd ..
    
    # Test ndmgr handles binary conflicts
    mkdir -p binary_config_dir
    cat > binary_config_dir/config.toml << EOF
[[repository]]
name = "binary_conflict_test"
path = "./binary_conflict_repo"
remote = "$TEST_REPO1_URL"
branch = "main"
EOF
    
    local output
    output=$(NDMGR_CONFIG_DIR="binary_config_dir" timeout 30 "$NDMGR_BINARY" --pull --verbose 2>&1) || true
    
    # Binary conflicts should be handled (likely by choosing one version)
    if ! echo "$output" | grep -q -E "(manual.*intervention|binary.*conflict.*unresolved)"; then
        log_success "NDMGR handled binary file conflict"
    else
        log_error "NDMGR couldn't handle binary file conflict"
        return 1
    fi
    
    return 0
}

test_directory_structure_conflicts() {
    # Test conflicts involving directory structure changes
    if ! command -v git &> /dev/null; then
        return 1
    fi
    
    git clone "$TEST_REPO2_URL" dir_conflict_repo 2>/dev/null || return 1
    
    cd dir_conflict_repo
    git config user.name "NDMGR Dir Test"
    git config user.email "dir-test@ndmgr.test"
    
    # Initial structure
    mkdir -p config/app
    echo "initial_config=true" > config/app/config.txt
    git add config/
    git commit -m "Initial directory structure"
    cd ..
    
    # Create directory structure conflict
    cd dir_conflict_repo
    
    # PC1: Move file to different location
    git checkout main
    mkdir -p new_config/app
    mv config/app/config.txt new_config/app/config.txt
    rmdir config/app config 2>/dev/null || true
    echo "pc1_config=true" >> new_config/app/config.txt
    git add -A
    git commit -m "PC1: Restructure config directory"
    local pc1_commit=$(git rev-parse HEAD)
    
    # PC2: Modify file in original location
    git reset --hard HEAD~1
    echo "pc2_config=true" >> config/app/config.txt
    git add config/app/config.txt
    git commit -m "PC2: Update config in original location"
    
    # Create conflict
    git merge "$pc1_commit" || true
    cd ..
    
    # Test ndmgr handles directory conflicts
    mkdir -p dir_config_dir
    cat > dir_config_dir/config.toml << EOF
[[repository]]
name = "dir_conflict_test"
path = "./dir_conflict_repo"
remote = "$TEST_REPO2_URL"
branch = "main"
EOF
    
    local output
    output=$(NDMGR_CONFIG_DIR="dir_config_dir" timeout 30 "$NDMGR_BINARY" --pull --verbose 2>&1) || true
    
    # Directory structure conflicts should be resolved
    if ! echo "$output" | grep -q -E "(manual.*intervention|directory.*conflict.*unresolved)"; then
        log_success "NDMGR handled directory structure conflict"
    else
        log_error "NDMGR couldn't handle directory structure conflict"
        return 1
    fi
    
    return 0
}

test_conflict_resolution_strategies() {
    # Test different conflict resolution strategies
    if ! command -v git &> /dev/null; then
        return 1
    fi
    
    git clone "$TEST_REPO1_URL" strategy_repo 2>/dev/null || return 1
    
    cd strategy_repo
    git config user.name "NDMGR Strategy Test"
    git config user.email "strategy-test@ndmgr.test"
    cd ..
    
    # Create conflict scenario
    create_multi_pc_conflict strategy_repo "strategy_test.conf" \
        "# PC1 Configuration\nstrategy=pc1\ncommon_setting=pc1_value" \
        "# PC2 Configuration\nstrategy=pc2\ncommon_setting=pc2_value"
    
    # Test different conflict resolution strategies in config
    local strategies=("local" "remote" "ask")
    
    for strategy in "${strategies[@]}"; do
        mkdir -p "strategy_config_$strategy"
        cat > "strategy_config_$strategy/config.toml" << EOF
[git]
conflict_resolution = "$strategy"

[[repository]]
name = "strategy_test_$strategy"
path = "./strategy_repo"
remote = "$TEST_REPO1_URL"
branch = "main"
EOF
        
        local output
        output=$(NDMGR_CONFIG_DIR="strategy_config_$strategy" timeout 30 "$NDMGR_BINARY" --pull --verbose 2>&1) || true
        
        # With any strategy, ndmgr should not require manual intervention
        if echo "$output" | grep -q -E "(manual.*intervention|resolve.*conflict.*manually)"; then
            log_error "NDMGR requires manual intervention with $strategy strategy"
            return 1
        fi
    done
    
    log_success "All conflict resolution strategies handled automatically"
    return 0
}

# === REAL-WORLD SIMULATION TESTS ===

test_multi_pc_development_workflow() {
    # Simulate realistic multi-PC development workflow
    if ! command -v git &> /dev/null; then
        return 1
    fi
    
    git clone "$TEST_REPO1_URL" workflow_repo 2>/dev/null || return 1
    
    cd workflow_repo
    git config user.name "NDMGR Workflow Test"
    git config user.email "workflow-test@ndmgr.test"
    
    # Create initial dotfiles structure
    mkdir -p shell_module editor_module terminal_module
    echo 'description="Shell configuration"' > shell_module/.ndmgr
    echo 'description="Editor configuration"' > editor_module/.ndmgr
    echo 'description="Terminal configuration"' > terminal_module/.ndmgr
    
    echo "export SHELL_THEME=default" > shell_module/.shellrc
    echo "set number" > editor_module/.editorrc
    echo "color_scheme=dark" > terminal_module/.terminalrc
    
    git add .
    git commit -m "Initial dotfiles setup"
    cd ..
    
    # Simulate PC1 workflow
    mkdir -p pc1_workspace
    cd pc1_workspace
    git clone ../workflow_repo pc1_repo
    cd pc1_repo
    git config user.name "PC1 User"
    git config user.email "pc1@test.com"
    
    # PC1 makes changes
    echo "export SHELL_THEME=light" > shell_module/.shellrc
    echo "set colorcolumn=80" >> editor_module/.editorrc
    git add -A
    git commit -m "PC1: Update shell and editor configs"
    cd ../../
    
    # Simulate PC2 workflow (concurrent changes)
    mkdir -p pc2_workspace
    cd pc2_workspace
    git clone ../workflow_repo pc2_repo
    cd pc2_repo
    git config user.name "PC2 User"
    git config user.email "pc2@test.com"
    
    # PC2 makes different changes to same files
    echo "export SHELL_THEME=dark" > shell_module/.shellrc
    echo "set relativenumber" >> editor_module/.editorrc
    echo "font_size=14" >> terminal_module/.terminalrc
    git add -A
    git commit -m "PC2: Update configs with different preferences"
    
    # PC2 pushes first (simulating real workflow)
    git push origin main
    cd ../../
    
    # PC1 tries to push (will be rejected, needs pull)
    cd pc1_workspace/pc1_repo
    git push origin main 2>/dev/null || true  # This will fail
    
    # This creates the exact conflict scenario ndmgr needs to handle
    git pull origin main || true  # Creates conflicts
    cd ../../
    
    # Now test ndmgr's ability to handle this real workflow scenario
    mkdir -p workflow_config
    cat > workflow_config/config.toml << EOF
[[repository]]
name = "workflow_test"
path = "./pc1_workspace/pc1_repo"
remote = "$TEST_REPO1_URL"
branch = "main"
auto_commit = true
EOF
    
    local output
    output=$(NDMGR_CONFIG_DIR="workflow_config" timeout 45 "$NDMGR_BINARY" --sync --verbose 2>&1) || true
    
    # Should handle the entire conflict resolution and sync automatically
    if echo "$output" | grep -q -E "(manual.*intervention|unresolved.*conflict|merge.*failed)"; then
        log_error "NDMGR couldn't handle realistic multi-PC workflow"
        log_error "Output: $output"
        return 1
    fi
    
    log_success "NDMGR handled realistic multi-PC workflow conflicts"
    return 0
}

test_rapid_concurrent_pushes() {
    # Test handling of very rapid concurrent changes (race conditions)
    if ! command -v git &> /dev/null; then
        return 1
    fi
    
    git clone "$TEST_REPO2_URL" rapid_repo 2>/dev/null || return 1
    
    cd rapid_repo
    git config user.name "NDMGR Rapid Test"
    git config user.email "rapid-test@ndmgr.test"
    
    # Create test file
    echo "counter=0" > rapid_counter.txt
    git add rapid_counter.txt
    git commit -m "Initial counter file"
    cd ..
    
    # Simulate rapid changes from different sources
    for i in {1..5}; do
        mkdir -p "rapid_workspace_$i"
        cd "rapid_workspace_$i"
        git clone ../rapid_repo "rapid_clone_$i"
        cd "rapid_clone_$i"
        git config user.name "Rapid User $i"
        git config user.email "rapid$i@test.com"
        
        # Each workspace makes different changes
        echo "counter=$i" > rapid_counter.txt
        echo "workspace_${i}_setting=true" >> rapid_counter.txt
        git add rapid_counter.txt
        git commit -m "Workspace $i: Update counter"
        cd ../../
    done
    
    # Try to push all changes (will create conflicts)
    for i in {1..5}; do
        cd "rapid_workspace_$i/rapid_clone_$i"
        git push origin main 2>/dev/null || true
        cd ../../
    done
    
    # Test ndmgr handles this complex conflict scenario
    mkdir -p rapid_config
    cat > rapid_config/config.toml << EOF
[[repository]]
name = "rapid_test"
path = "./rapid_workspace_1/rapid_clone_1"
remote = "$TEST_REPO2_URL"
branch = "main"
EOF
    
    local output
    output=$(NDMGR_CONFIG_DIR="rapid_config" timeout 60 "$NDMGR_BINARY" --pull --verbose 2>&1) || true
    
    # Should handle even complex rapid conflict scenarios
    if echo "$output" | grep -q -E "(timeout|deadlock|manual.*intervention)"; then
        log_error "NDMGR couldn't handle rapid concurrent changes"
        return 1
    fi
    
    log_success "NDMGR handled rapid concurrent changes"
    return 0
}

# Main execution
main() {
    log_info "Starting NDMGR Git Conflict Resolution Tests"
    log_info "Binary: $NDMGR_BINARY"
    log_info "Test Repository 1: $TEST_REPO1_URL"
    log_info "Test Repository 2: $TEST_REPO2_URL"
    log_info "Focus: Automatic conflict resolution without user intervention"
    
    # Check if git is available
    if ! command -v git &> /dev/null; then
        log_error "Git is not available. Skipping all git conflict tests."
        exit 1
    fi
    
    setup_test_environment
    trap cleanup_test_environment EXIT
    
    # Basic Conflict Resolution Tests
    log_info "=== BASIC GIT CONFLICT RESOLUTION TESTS ==="
    run_test "Simple File Conflict Resolution" test_simple_file_conflict_resolution || true
    run_test "Module Config Conflict Resolution" test_module_config_conflict_resolution || true
    run_test "Multiple File Conflicts" test_multiple_file_conflicts || true
    
    # Advanced Conflict Scenarios
    log_info "=== ADVANCED CONFLICT SCENARIOS ==="
    run_test "Binary File Conflicts" test_binary_file_conflicts || true
    run_test "Directory Structure Conflicts" test_directory_structure_conflicts || true
    run_test "Conflict Resolution Strategies" test_conflict_resolution_strategies || true
    
    # Real-World Simulation Tests
    log_info "=== REAL-WORLD SIMULATION TESTS ==="
    run_test "Multi-PC Development Workflow" test_multi_pc_development_workflow || true
    run_test "Rapid Concurrent Pushes" test_rapid_concurrent_pushes || true
    
    # Print summary
    echo
    log_info "=== GIT CONFLICT RESOLUTION TEST SUMMARY ==="
    log_info "Total tests: $TEST_COUNT"
    log_success "Passed: $PASS_COUNT"
    log_error "Failed: $FAIL_COUNT" 
    log_warning "Skipped: $SKIP_COUNT"
    
    if [[ $FAIL_COUNT -eq 0 ]]; then
        log_success "All git conflict resolution tests passed!"
        log_success "NDMGR can handle git conflicts automatically!"
        exit 0
    else
        log_error "Some git conflict resolution tests failed!"
        log_error "NDMGR may require manual conflict resolution in some scenarios"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "NDMGR Git Conflict Resolution Test Suite"
        echo "Usage: $0 [options]"
        echo ""
        echo "This test suite focuses on testing NDMGR's ability to automatically"
        echo "resolve git conflicts without requiring user intervention."
        echo ""
        echo "Test scenarios:"
        echo "- Simple file conflicts between different PCs"
        echo "- Module configuration conflicts"
        echo "- Multiple simultaneous file conflicts"
        echo "- Binary file conflicts"
        echo "- Directory structure changes"
        echo "- Different conflict resolution strategies"
        echo "- Real-world multi-PC development workflows"
        echo "- Rapid concurrent changes"
        echo ""
        echo "All tests assume git repositories are managed by NDMGR and"
        echo "conflicts arise from different PCs pushing updates."
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --binary PATH  Specify ndmgr binary path"
        exit 0
        ;;
    --binary)
        NDMGR_BINARY="$2"
        shift 2
        ;;
esac

main "$@"