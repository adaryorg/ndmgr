#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
# SPDX-License-Identifier: MIT

set -euo pipefail

# Master functional test runner
# Coordinates all functional test suites for comprehensive ndmgr testing

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
NDMGR_BINARY="${NDMGR_BINARY:-$PROJECT_ROOT/zig-out/bin/ndmgr}"
SETUP_REPOS=false
RUN_UNIT_TESTS=true
RUN_ORIGINAL_TESTS=true
RUN_COMPREHENSIVE_TESTS=true
RUN_GIT_CONFLICT_TESTS=true
RUN_GIT_BRANCH_TESTS=false
FAIL_FAST=false

# Test suite results
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
SKIPPED_SUITES=0

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

log_header() {
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN} $*${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

run_test_suite() {
    local suite_name="$1"
    local suite_script="$2"
    local suite_description="$3"
    
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    
    log_header "$suite_name"
    log_info "$suite_description"
    echo
    
    local start_time=$(date +%s)
    
    if [[ -x "$SCRIPT_DIR/$suite_script" ]]; then
        if "$SCRIPT_DIR/$suite_script"; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log_success "$suite_name completed successfully in ${duration}s"
            PASSED_SUITES=$((PASSED_SUITES + 1))
            echo
            return 0
        else
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log_error "$suite_name failed after ${duration}s"
            FAILED_SUITES=$((FAILED_SUITES + 1))
            
            if [[ "$FAIL_FAST" == "true" ]]; then
                log_error "Fail-fast enabled. Stopping test execution."
                exit 1
            fi
            echo
            return 1
        fi
    else
        log_warning "$suite_name - script not found or not executable: $suite_script"
        SKIPPED_SUITES=$((SKIPPED_SUITES + 1))
        echo
        return 1
    fi
}

run_unit_tests() {
    if [[ "$RUN_UNIT_TESTS" != "true" ]]; then
        return 0
    fi
    
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    
    log_header "UNIT TESTS"
    log_info "Running Zig unit tests for all ndmgr modules"
    echo
    
    local start_time=$(date +%s)
    
    cd "$PROJECT_ROOT"
    if zig build test; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "Unit tests completed successfully in ${duration}s"
        PASSED_SUITES=$((PASSED_SUITES + 1))
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_error "Unit tests failed after ${duration}s"
        FAILED_SUITES=$((FAILED_SUITES + 1))
        
        if [[ "$FAIL_FAST" == "true" ]]; then
            log_error "Fail-fast enabled. Stopping test execution."
            exit 1
        fi
    fi
    echo
}

setup_test_repositories() {
    if [[ "$SETUP_REPOS" != "true" ]]; then
        return 0
    fi
    
    log_header "TEST REPOSITORY SETUP"
    log_info "Setting up both test repositories with mock data"
    echo
    
    if [[ -x "$SCRIPT_DIR/setup_test_repos.sh" ]]; then
        if "$SCRIPT_DIR/setup_test_repos.sh"; then
            log_success "Test repositories setup completed"
        else
            log_error "Test repositories setup failed"
            log_error "Some functional tests may not work correctly"
        fi
    else
        log_warning "Repository setup script not found"
    fi
    echo
}

print_summary() {
    log_header "FUNCTIONAL TEST EXECUTION SUMMARY"
    
    echo -e "${BLUE}Test Environment:${NC}"
    echo -e "  Binary: $NDMGR_BINARY"
    echo -e "  Project Root: $PROJECT_ROOT"
    echo -e "  Git Available: $(command -v git >/dev/null && echo "Yes" || echo "No")"
    echo
    
    echo -e "${BLUE}Test Suite Results:${NC}"
    echo -e "  Total Suites: $TOTAL_SUITES"
    echo -e "  ${GREEN}Passed: $PASSED_SUITES${NC}"
    echo -e "  ${RED}Failed: $FAILED_SUITES${NC}"
    echo -e "  ${YELLOW}Skipped: $SKIPPED_SUITES${NC}"
    echo
    
    if [[ $FAILED_SUITES -eq 0 ]]; then
        log_success "ALL FUNCTIONAL TESTS PASSED!"
        echo -e "${GREEN}NDMGR is ready for production use.${NC}"
        return 0
    else
        log_error "SOME FUNCTIONAL TESTS FAILED!"
        echo -e "${RED}Please review failed test suites before deploying NDMGR.${NC}"
        return 1
    fi
}

show_help() {
    cat << EOF
NDMGR Master Functional Test Runner

Usage: $0 [options]

This script runs all functional test suites for comprehensive ndmgr testing.
It coordinates unit tests, shell-based functional tests, and specialized tests.

Test Suites Available:
  1. Unit Tests                 - Zig unit tests for all modules
  2. Original Test Suite        - Comprehensive shell-based functional tests
  3. Comprehensive Tests        - Advanced CLI and git operations testing
  4. Git Conflict Tests         - Specialized git conflict resolution testing
  5. Git Branch Tests           - Extended git branch functionality testing

Options:
  --help, -h                    Show this help message
  --binary PATH                 Specify ndmgr binary path (default: ./zig-out/bin/ndmgr)
  --setup-repos                 Setup test repositories before running tests
  --skip-unit                   Skip unit tests
  --skip-original               Skip original test suite
  --skip-comprehensive          Skip comprehensive functional tests
  --skip-git-conflicts          Skip git conflict resolution tests
  --run-git-branches            Include git branch tests (slower)
  --fail-fast                   Stop on first test suite failure
  --only-unit                   Run only unit tests
  --only-functional             Run only functional tests (skip unit tests)
  --only-git                    Run only git-related tests

Examples:
  $0                            # Run all test suites (default)
  $0 --setup-repos              # Setup repositories and run all tests
  $0 --only-functional          # Run only functional tests
  $0 --only-git --setup-repos   # Setup repos and run only git tests
  $0 --fail-fast                # Stop on first failure

Environment Variables:
  NDMGR_BINARY                  Path to ndmgr binary

Notes:
  - Git tests require SSH access to GitHub test repositories
  - Some tests may be skipped if dependencies are not available
  - Test repositories use generic names to avoid real app confusion
  - Git conflict tests focus on automatic resolution without user intervention
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --binary)
                NDMGR_BINARY="$2"
                shift 2
                ;;
            --setup-repos)
                SETUP_REPOS=true
                shift
                ;;
            --skip-unit)
                RUN_UNIT_TESTS=false
                shift
                ;;
            --skip-original)
                RUN_ORIGINAL_TESTS=false
                shift
                ;;
            --skip-comprehensive)
                RUN_COMPREHENSIVE_TESTS=false
                shift
                ;;
            --skip-git-conflicts)
                RUN_GIT_CONFLICT_TESTS=false
                shift
                ;;
            --run-git-branches)
                RUN_GIT_BRANCH_TESTS=true
                shift
                ;;
            --fail-fast)
                FAIL_FAST=true
                shift
                ;;
            --only-unit)
                RUN_UNIT_TESTS=true
                RUN_ORIGINAL_TESTS=false
                RUN_COMPREHENSIVE_TESTS=false
                RUN_GIT_CONFLICT_TESTS=false
                RUN_GIT_BRANCH_TESTS=false
                shift
                ;;
            --only-functional)
                RUN_UNIT_TESTS=false
                RUN_ORIGINAL_TESTS=true
                RUN_COMPREHENSIVE_TESTS=true
                RUN_GIT_CONFLICT_TESTS=true
                shift
                ;;
            --only-git)
                RUN_UNIT_TESTS=false
                RUN_ORIGINAL_TESTS=false
                RUN_COMPREHENSIVE_TESTS=false
                RUN_GIT_CONFLICT_TESTS=true
                RUN_GIT_BRANCH_TESTS=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

main() {
    parse_arguments "$@"
    
    log_header "NDMGR MASTER FUNCTIONAL TEST RUNNER"
    log_info "Comprehensive testing of ndmgr functionality"
    log_info "Binary: $NDMGR_BINARY"
    
    # Check if binary exists
    if [[ ! -x "$NDMGR_BINARY" ]]; then
        log_info "NDMGR binary not found, attempting to build..."
        cd "$PROJECT_ROOT"
        if zig build; then
            log_success "NDMGR binary built successfully"
        else
            log_error "Failed to build NDMGR binary"
            exit 1
        fi
        cd "$SCRIPT_DIR"
    fi
    
    echo
    
    # Setup test repositories if requested
    setup_test_repositories
    
    # Run test suites in order
    if [[ "$RUN_UNIT_TESTS" == "true" ]]; then
        run_unit_tests
    fi
    
    if [[ "$RUN_ORIGINAL_TESTS" == "true" ]]; then
        run_test_suite "ORIGINAL COMPREHENSIVE TEST SUITE" \
            "test_suite.sh" \
            "Original comprehensive functional tests covering all basic ndmgr functionality"
    fi
    
    if [[ "$RUN_COMPREHENSIVE_TESTS" == "true" ]]; then
        run_test_suite "ADVANCED COMPREHENSIVE TESTS" \
            "test_comprehensive_functional.sh" \
            "Advanced CLI combinations, dual repository testing, and edge case scenarios"
    fi
    
    if [[ "$RUN_GIT_CONFLICT_TESTS" == "true" ]]; then
        run_test_suite "GIT CONFLICT RESOLUTION TESTS" \
            "test_git_conflicts.sh" \
            "Specialized testing of automatic git conflict resolution without user intervention"
    fi
    
    if [[ "$RUN_GIT_BRANCH_TESTS" == "true" ]]; then
        run_test_suite "GIT BRANCH FUNCTIONALITY TESTS" \
            "test_git_branches.sh" \
            "Extended git branch functionality and multi-branch deployment testing"
    fi
    
    # Print final summary
    echo
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

main "$@"