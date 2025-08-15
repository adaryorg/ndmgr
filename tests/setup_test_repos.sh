#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
# SPDX-License-Identifier: MIT

set -euo pipefail

# Enhanced setup script for both test repositories
# Populates both repositories with generic mock data for comprehensive testing
# Uses generic names to avoid confusion with real applications

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TEST_REPO1_URL="git@github.com:adaryorg/ndmgr_test.git"
TEST_REPO2_URL="git@github.com:adaryorg/ndmgr_test2.git"
TEMP_DIR=$(mktemp -d -t ndmgr_dual_repo_setup_XXXXXX)

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

create_generic_module() {
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

setup_repository_1() {
    local repo_dir="$1"
    log_info "Setting up Repository 1 (Primary) with generic modules..."
    
    cd "$repo_dir"
    
    # Clean up existing content
    find . -maxdepth 1 -type d -name "*_*" -exec rm -rf {} \; 2>/dev/null || true
    find . -maxdepth 1 -name "*.md" -not -name "README.md" -delete 2>/dev/null || true
    
    # === BASIC CONFIGURATION MODULES ===
    
    # Shell configuration module
    create_generic_module "shell_config" \
        "description=\"Generic shell configuration module\"" \
        ".shellrc" "# Generic shell configuration\nexport SHELL_THEME=default\nexport SHELL_EDITOR=generic_editor\nalias ll='ls -la'\nalias grep='grep --color=auto'" \
        ".shell_profile" "# Shell profile\nsource ~/.shellrc\nexport PATH=\"\$PATH:\$HOME/.local/bin\"" \
        ".shell_aliases" "# Custom aliases\nalias ..='cd ..'\nalias ...='cd ../..'\nalias h='history'"
    
    # Editor configuration module
    create_generic_module "editor_config" \
        "description=\"Generic text editor configuration\"" \
        ".editorrc" "\" Generic editor configuration\nset number\nset autoindent\nset tabstop=4\nset expandtab\nset hlsearch" \
        ".editor_themes/dark.theme" "# Dark theme\nbackground=dark\nforeground=light\ncomment_color=gray" \
        ".editor_themes/light.theme" "# Light theme\nbackground=light\nforeground=dark\ncomment_color=blue"
    
    # Terminal configuration module
    create_generic_module "terminal_config" \
        "description=\"Generic terminal emulator configuration\"" \
        ".terminalrc" "# Terminal configuration\ncolor_scheme=solarized_dark\nfont_family=monospace\nfont_size=12\nscrollback=10000" \
        ".terminal_themes/dark.conf" "[colors]\nbackground=#2e3440\nforeground=#d8dee9" \
        ".terminal_themes/light.conf" "[colors]\nbackground=#fdf6e3\nforeground=#657b83"
    
    # === ADVANCED MODULES WITH DEPENDENCIES ===
    
    # Base development module
    create_generic_module "dev_base" \
        "description=\"Base development environment configuration\"" \
        ".dev_profile" "# Development environment\nexport DEV_MODE=true\nexport DEBUG_LEVEL=1" \
        ".dev_tools/linter.conf" "strict_mode=true\nmax_line_length=100" \
        ".dev_tools/formatter.conf" "indent_size=2\nmax_width=80"
    
    # Language-specific module (depends on dev_base)
    create_generic_module "lang_config" \
        "description=\"Language-specific development configuration\"\ndependencies=[\"dev_base\"]" \
        ".lang_config" "# Language configuration\nlanguage_server=enabled\nauto_completion=true" \
        ".lang_tools/debugger.conf" "break_on_exception=true\nshow_variables=true"
    
    # === COMPLEX STRUCTURE MODULES ===
    
    # Application configuration with nested structure
    create_generic_module "app_config" \
        "description=\"Complex application configuration with nested directories\"" \
        ".config/generic_app/main.conf" "[main]\ntheme=dark\nauto_save=true\nbackup_count=5" \
        ".config/generic_app/plugins/plugin1.conf" "[plugin1]\nenabled=true\nconfig_file=~/.config/generic_app/plugins/plugin1.ini" \
        ".config/generic_app/plugins/plugin2.conf" "[plugin2]\nenabled=false" \
        ".config/generic_app/themes/dark.json" "{\"name\": \"dark\", \"background\": \"#2e3440\", \"accent\": \"#5e81ac\"}" \
        ".local/share/generic_app/data.db" "# Database placeholder\ntable_version=1"
    
    # === TESTING MODULES ===
    
    # Module for conflict testing
    create_generic_module "conflict_test" \
        "description=\"Module designed for conflict resolution testing\"" \
        ".conflict_config" "# Configuration that will be modified by different PCs\nconflict_resolution_test=true\nversion=1.0" \
        ".shared_settings" "shared_value=initial\npc_specific_value=pc1"
    
    # Module with ignore patterns
    create_generic_module "ignore_patterns_test" \
        "description=\"Module with ignore patterns for testing\"\nignore_patterns=[\"*.tmp\", \"*.log\", \"cache/\"]" \
        ".important_config" "keep_this=true\nconfig_version=1.0" \
        ".data_file.txt" "important_data=true" \
        "temp.tmp" "this_should_be_ignored=true" \
        "debug.log" "log_entry=should_be_ignored" \
        "cache/cache_file.cache" "cached_data=should_be_ignored" \
        "system_file.tmp" "temp_data=should_be_ignored"
    
    # Module with special characters
    create_generic_module "special_chars_test" \
        "description=\"Module with special characters in filenames\"" \
        ".config-with-dashes" "dashes=true" \
        ".config_with_underscores" "underscores=true" \
        ".config.with.dots" "dots=true" \
        ".CONFIG_UPPERCASE" "uppercase=true" \
        ".config with spaces" "spaces=true" \
        ".配置文件" "unicode=true"
    
    # Commit all to main branch
    git add .
    git commit -m "Add comprehensive generic test modules for ndmgr functional testing"
    git push origin main
    
    # Create development branch with additional modules
    git checkout -b development
    
    create_generic_module "dev_only_module" \
        "description=\"Module only available in development branch\"" \
        ".dev_config" "development_mode=true\nbranch=development\nfeatures=experimental" \
        ".dev_scripts/test.sh" "#!/bin/bash\necho 'Development test script'"
    
    create_generic_module "experimental_features" \
        "description=\"Experimental features module\"" \
        ".experimental_config" "feature_alpha=enabled\nfeature_beta=testing\nfeature_gamma=disabled" \
        ".experimental_data/alpha.json" "{\"feature\": \"alpha\", \"status\": \"enabled\"}"
    
    git add .
    git commit -m "Add development branch specific modules"
    git push origin development
    
    # Create feature branch
    git checkout -b feature/generic-features
    
    create_generic_module "feature_module" \
        "description=\"Feature branch specific module\"" \
        ".feature_config" "feature_name=generic-features\nstatus=in_development" \
        ".feature_data/metadata.yml" "name: generic-features\nauthor: ndmgr-test\nversion: 0.1.0"
    
    git add .
    git commit -m "Add feature branch test module"
    git push origin feature/generic-features
    
    git checkout main
    cd ..
}

setup_repository_2() {
    local repo_dir="$1"
    log_info "Setting up Repository 2 (Secondary) with complementary modules..."
    
    cd "$repo_dir"
    
    # Clean up existing content
    find . -maxdepth 1 -type d -name "*_*" -exec rm -rf {} \; 2>/dev/null || true
    
    # === COMPLEMENTARY MODULES FOR DUAL REPO TESTING ===
    
    # System configuration module
    create_generic_module "system_config" \
        "description=\"System-level configuration module\"" \
        ".system_profile" "# System configuration\nexport SYSTEM_LOCALE=en_US.UTF-8\nexport SYSTEM_TIMEZONE=UTC" \
        ".system_settings" "auto_update=false\ntelemetry=disabled\ncrash_reporting=false"
    
    # Network configuration module
    create_generic_module "network_config" \
        "description=\"Network and connectivity configuration\"" \
        ".network_config" "# Network settings\nproxy_enabled=false\ntimeout=30\nretries=3" \
        ".network_hosts" "# Custom host entries\n127.0.0.1 localhost.test\n::1 localhost.test"
    
    # Security configuration module
    create_generic_module "security_config" \
        "description=\"Security and privacy configuration\"" \
        ".security_settings" "# Security configuration\nencryption=enabled\nkey_length=2048\nauto_lock=true" \
        ".security_keys/public.key" "# Public key placeholder\nssh-rsa AAAAB3... test@ndmgr" \
        ".security_policies/access.policy" "# Access policy\ndefault=deny\nlocal=allow"
    
    # === MULTI-REPOSITORY TESTING MODULES ===
    
    # Shared configuration (for testing conflicts)
    create_generic_module "shared_config" \
        "description=\"Configuration shared between repositories\"" \
        ".shared_settings" "# Settings that might conflict between repos\nrepo=secondary\nversion=1.0\nshared_value=repo2_default" \
        ".common_config" "# Common configuration\ncommon_setting=true\nrepo_specific=repo2"
    
    # Performance monitoring module
    create_generic_module "monitoring_config" \
        "description=\"Performance and monitoring configuration\"" \
        ".monitoring_config" "# Monitoring settings\nmetrics_enabled=true\nlog_level=info\nsample_rate=0.1" \
        ".monitoring_dashboards/system.json" "{\"dashboard\": \"system\", \"widgets\": [\"cpu\", \"memory\", \"disk\"]}" \
        ".monitoring_alerts/critical.yml" "alerts:\n  - name: high_cpu\n    threshold: 90\n    action: alert"
    
    # Backup and sync module
    create_generic_module "backup_config" \
        "description=\"Backup and synchronization configuration\"" \
        ".backup_config" "# Backup settings\nbackup_enabled=true\nbackup_interval=daily\nretention=30" \
        ".backup_scripts/daily.sh" "#!/bin/bash\n# Daily backup script\necho 'Running daily backup...'" \
        ".sync_config" "# Sync configuration\nsync_enabled=true\nconflict_resolution=auto"
    
    # === CONFLICT SIMULATION MODULES ===
    
    # Module that will be modified for conflict testing
    create_generic_module "conflict_simulation" \
        "description=\"Module for simulating git conflicts\"" \
        ".conflict_target" "# This file will be modified by different PCs\npc_id=repo2_initial\ntimestamp=$(date)\nvalue=initial" \
        ".multi_conflict_file1" "section1=repo2\nshared_section=initial" \
        ".multi_conflict_file2" "section2=repo2\nshared_section=initial"
    
    # Binary file testing module
    create_generic_module "binary_test" \
        "description=\"Module with binary files for conflict testing\"" \
        ".text_config" "# Text configuration\nbinary_test_module=true" \
        ".binary_data" "BINARY_DATA_PLACEHOLDER_REPO2"
    
    # Commit all to main branch
    git add .
    git commit -m "Add secondary repository modules for dual-repo testing"
    git push origin main
    
    # Create conflict branch for testing
    git checkout -b conflict-test
    
    # Modify shared files differently
    echo "# Modified in conflict-test branch
pc_id=conflict_branch
timestamp=$(date)
value=conflict_test_branch" > shared_config/.shared_settings
    
    echo "section1=conflict_branch
shared_section=modified_in_branch" > conflict_simulation/.multi_conflict_file1
    
    git add .
    git commit -m "Modify shared files for conflict testing"
    git push origin conflict-test
    
    git checkout main
    cd ..
}

main() {
    log_info "Setting up dual test repositories for comprehensive ndmgr testing"
    log_info "Repository 1: $TEST_REPO1_URL (Primary)"
    log_info "Repository 2: $TEST_REPO2_URL (Secondary)"
    log_info "Using generic names to avoid confusion with real applications"
    log_info "Working directory: $TEMP_DIR"
    
    cd "$TEMP_DIR"
    
    # Setup Repository 1
    log_info "=== Setting up Primary Repository ==="
    if git clone "$TEST_REPO1_URL" repo1; then
        cd repo1
        git config user.name "NDMGR Test Setup Primary"
        git config user.email "test-primary@ndmgr.test"
        cd ..
        setup_repository_1 repo1
        log_success "Primary repository setup completed"
    else
        log_error "Failed to clone primary repository"
        exit 1
    fi
    
    # Setup Repository 2
    log_info "=== Setting up Secondary Repository ==="
    if git clone "$TEST_REPO2_URL" repo2; then
        cd repo2
        git config user.name "NDMGR Test Setup Secondary"
        git config user.email "test-secondary@ndmgr.test"
        cd ..
        setup_repository_2 repo2
        log_success "Secondary repository setup completed"
    else
        log_error "Failed to clone secondary repository"
        exit 1
    fi
    
    log_success "Dual repository setup complete!"
    echo
    log_info "Primary Repository (repo1) contains:"
    log_info "- Basic configuration modules (shell, editor, terminal)"
    log_info "- Complex nested structure modules"
    log_info "- Dependency chain modules"
    log_info "- Special character testing modules"
    log_info "- Development and feature branches"
    echo
    log_info "Secondary Repository (repo2) contains:"
    log_info "- System and network configuration modules"
    log_info "- Security and monitoring modules"
    log_info "- Backup and sync modules"
    log_info "- Conflict simulation modules"
    log_info "- Binary file testing modules"
    echo
    log_info "Both repositories are now ready for comprehensive functional testing"
    log_info "Run the following test suites:"
    log_info "./tests/test_suite.sh                      # Original comprehensive tests"
    log_info "./tests/test_comprehensive_functional.sh   # New comprehensive functional tests"
    log_info "./tests/test_git_conflicts.sh             # Specialized git conflict tests"
    log_info "./tests/test_git_branches.sh              # Extended git branch tests"
}

main "$@"