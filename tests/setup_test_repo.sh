#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
# SPDX-License-Identifier: MIT

set -euo pipefail

# This script sets up an extensive test library in the git repository
# It should be run once to populate the test repository with various test modules

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TEST_REPO_URL="git@github.com:adaryorg/ndmgr_test.git"
TEMP_DIR=$(mktemp -d -t ndmgr_test_repo_setup_XXXXXX)
NDMGR_BINARY="${NDMGR_BINARY:-./zig-out/bin/ndmgr}"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_info "Cleaned up temporary directory"
    fi
}

trap cleanup EXIT

create_module() {
    local module_name="$1"
    local ndmgr_config="$2"
    shift 2
    
    log_info "Creating module: $module_name"
    
    mkdir -p "$module_name"
    echo "$ndmgr_config" > "$module_name/.ndmgr"
    
    while [[ $# -gt 0 ]]; do
        local file_path="$1"
        local file_content="$2"
        shift 2
        
        local full_path="$module_name/$file_path"
        mkdir -p "$(dirname "$full_path")"
        echo -e "$file_content" > "$full_path"
    done
}

main() {
    log_info "Setting up extensive test repository"
    log_info "Repository: $TEST_REPO_URL"
    log_info "Working directory: $TEMP_DIR"
    
    cd "$TEMP_DIR"
    
    # Clone the repository
    log_info "Cloning test repository..."
    if ! git clone "$TEST_REPO_URL" repo; then
        log_error "Failed to clone repository"
        exit 1
    fi
    
    cd repo
    
    # Configure git
    git config user.name "NDMGR Test Setup"
    git config user.email "test-setup@ndmgr.test"
    
    # Clean up any existing test modules (keep only README if it exists)
    log_info "Cleaning up existing test modules..."
    find . -maxdepth 1 -type d -name "test_*" -exec rm -rf {} \; 2>/dev/null || true
    
    # Create comprehensive test modules
    
    # 1. Simple module with basic config files
    create_module "test_simple" \
        "description=\"Simple test module with basic config files\"" \
        ".test_config" "# Simple test configuration\ntest_mode=enabled\nversion=1.0" \
        ".test_settings.json" '{"settings": {"test": true, "level": 1}}'
    
    # 2. Complex module with nested directories (removed target_subdirectory to avoid conflicts)
    create_module "test_complex" \
        "description=\"Complex module with nested directory structure\"" \
        ".config/complex_app/config.yml" "app:\n  name: complex_app\n  version: 2.0\n  enabled: true" \
        ".config/complex_app/themes/dark.theme" "background=#000000\nforeground=#FFFFFF" \
        ".config/complex_app/themes/light.theme" "background=#FFFFFF\nforeground=#000000" \
        ".config/complex_app/data/settings.dat" "binary_data_placeholder" \
        ".local/share/complex_app/cache.db" "cache_database_placeholder"
    
    # 3. Module with dependencies
    create_module "test_base_module" \
        "description=\"Base module that others depend on\"" \
        ".test_base_profile" "export TEST_BASE_VAR=initialized\nexport TEST_PATH=/usr/local/test" \
        ".test_base_config" "base_setting=true\nbase_version=1.0"
    
    create_module "test_dependent_module" \
        "description=\"Module that depends on test_base_module\"
dependencies=[\"test_base_module\"]" \
        ".test_dependent_rc" "source ~/.test_base_profile\necho \"Dependent module loaded\"" \
        ".test_dependent_config" "dependent_setting=true\nrequires_base=yes"
    
    # 4. Module with tree folding test
    create_module "test_tree_fold" \
        "description=\"Module to test tree folding behavior\"" \
        ".config/tree_test/level1/file1.conf" "level1_setting=1" \
        ".config/tree_test/level1/file2.conf" "level1_setting=2" \
        ".config/tree_test/level2/subdir/file3.conf" "level2_setting=3" \
        ".config/tree_test/level2/subdir/file4.conf" "level2_setting=4"
    
    # 5. Module with ignore patterns
    create_module "test_ignore_patterns" \
        "description=\"Module with ignore patterns\"
ignore_patterns=[\"*.tmp\", \"*.log\", \"cache/\"]" \
        ".test_ignore_config" "ignore_test=true" \
        ".test_data.txt" "important_data" \
        "temp.tmp" "should_be_ignored" \
        "debug.log" "should_be_ignored" \
        "cache/file.cache" "should_be_ignored"
    
    # 6. Module for testing
    create_module "test_adoption" \
        "target_dir=/tmp/test_adoption" \
        ".test_adoption_dir/config.txt" "adoption_config=true" \
        ".test_adoption_dir/data/file.dat" "adoption_data"
    
    # 7. Module with special characters in names
    create_module "test_special_chars" \
        "ignore=false" \
        ".test-config_2024" "test_dash_underscore=true" \
        ".test.config.backup" "test_dots=true" \
        ".TEST_UPPER_CASE" "test_uppercase=true"
    
    # 8. Module chain with multiple dependencies
    create_module "test_chain_a" \
        "description=\"First in dependency chain\"" \
        ".chain_a_config" "chain_a=initialized"
    
    create_module "test_chain_b" \
        "description=\"Second in dependency chain\"
dependencies=[\"test_chain_a\"]" \
        ".chain_b_config" "chain_b=initialized\nrequires_a=true"
    
    create_module "test_chain_c" \
        "description=\"Third in dependency chain\"
dependencies=[\"test_chain_a\", \"test_chain_b\"]" \
        ".chain_c_config" "chain_c=initialized\nrequires_a_and_b=true"
    
    # 9. Module with mixed content types
    create_module "test_mixed_content" \
        "description=\"Module with various file types\"" \
        ".test_script.sh" "#!/bin/bash\necho 'Test script'" \
        ".test_python.py" "#!/usr/bin/env python3\nprint('Test Python')" \
        ".test_data.csv" "id,name,value\n1,test1,100\n2,test2,200" \
        ".test_markdown.md" "# Test Documentation\n\nThis is a test."
    
    # 10. Module for conflict testing
    create_module "test_conflicts" \
        "description=\"Module designed to test conflict scenarios\"" \
        ".conflict_file_1" "conflict_content_1" \
        ".conflict_file_2" "conflict_content_2" \
        ".conflict_dir/file.txt" "conflict_dir_content"
    
    # Commit all modules to main branch
    log_info "Committing modules to main branch..."
    git add .
    git commit -m "Add comprehensive test modules for ndmgr testing" || true
    git push origin main
    
    # Create a development branch with additional modules
    log_info "Creating development branch with additional modules..."
    git checkout -b development
    
    # Add development-specific modules
    create_module "test_dev_only" \
        "description=\"Module only in development branch\"" \
        ".dev_config" "development=true\nbranch=development" \
        ".dev_tools/lint.conf" "strict_mode=true" \
        ".dev_tools/debug.conf" "debug_level=verbose"
    
    create_module "test_experimental" \
        "description=\"Experimental features module\"" \
        ".experimental_features" "feature_x=enabled\nfeature_y=testing" \
        ".experimental/data.json" '{"experimental": true, "status": "testing"}'
    
    # Modify an existing module in dev branch
    echo "dev_branch_addition=true" >> test_simple/.test_config
    
    git add .
    git commit -m "Add development branch specific modules"
    git push origin development
    
    # Create a feature branch
    log_info "Creating feature branch..."
    git checkout -b feature/test-branch
    
    create_module "test_feature" \
        "description=\"Feature branch specific module\"" \
        ".feature_config" "feature_branch=true\nfeature_name=test-branch" \
        ".feature_data/info.txt" "Feature branch data"
    
    git add .
    git commit -m "Add feature branch test module"
    git push origin feature/test-branch
    
    # Switch back to main
    git checkout main
    
    log_success "Test repository setup complete!"
    log_info "Created branches: main, development, feature/test-branch"
    log_info "Total modules created: 15+"
    
    # List all modules
    echo
    log_info "Modules in main branch:"
    find . -maxdepth 1 -type d -name "test_*" -exec basename {} \; | sort
    
    echo
    log_info "Repository structure created successfully"
}

main "$@"