# NDMGR Test Suite

This directory contains comprehensive tests for ndmgr functionality including unit tests and functional tests.

## Overview

The test suite combines Zig unit tests with shell-based functional tests that provide end-to-end testing of the ndmgr binary. It tests all major functionality and uses two dedicated GitHub repositories for git integration testing.

## Test Structure

### Unit Tests (Zig)
- Located in `src/test_*.zig` files
- Run via `zig build test`
- Test individual modules and functions
- No external dependencies required

### Functional Tests (Shell Scripts)
- `run_all_functional_tests.sh` - Master test runner coordinating all test suites
- `test_suite.sh` - Original comprehensive functional test suite
- `test_comprehensive_functional.sh` - Extended functional tests with dual repository scenarios
- `test_git_conflicts.sh` - Specialized git conflict resolution testing
- `test_git_branches.sh` - Git branch functionality testing
- `setup_test_repos.sh` - Repository setup and population script

### Test Repositories
- **Primary**: `git@github.com:adaryorg/ndmgr_test.git` (SSH only, not public)
- **Secondary**: `git@github.com:adaryorg/ndmgr_test2.git` (SSH only, not public)
- Both contain generic test modules with `.ndmgr` configuration files
- Use preconfigured git name/email - do not modify during tests

## Running Tests

### Prerequisites

1. **Build ndmgr**: `zig build`
2. **Git access**: For git integration tests, ensure SSH access to the test repositories
3. **SSH keys**: GitHub SSH keys configured for `git@github.com:adaryorg/ndmgr_test.git` and `git@github.com:adaryorg/ndmgr_test2.git`

### Running All Tests

```bash
# Recommended: Run complete test suite (unit + functional)
./tests/run_all_functional_tests.sh

# Unit tests only (fast, no external dependencies)
zig build test

# Functional tests only (requires git access)
./tests/run_all_functional_tests.sh --only-functional
```

### Running Individual Test Suites

```bash
# Original comprehensive test suite
./tests/test_suite.sh

# Extended dual-repository tests  
./tests/test_comprehensive_functional.sh

# Git conflict resolution tests
./tests/test_git_conflicts.sh

# Git branch functionality tests
./tests/test_git_branches.sh

# Setup test repositories (if needed)
./tests/setup_test_repos.sh
```

### Test Configuration

#### Environment Variables
- `NDMGR_BINARY` - Path to ndmgr binary (default: `./zig-out/bin/ndmgr`)

#### Git Requirements
- **SSH Access**: Tests require SSH access to both repositories
- **Authentication**: Use SSH keys, not HTTPS (repositories are private)
- **Network**: Internet connection required for git operations
- **Permissions**: Read/write access to test repositories

## Test Coverage

### Unit Tests (Zig)
- **Module Systems**: Configuration, scanner, linker, advanced linker
- **Git Operations**: Repository detection, error handling, command execution
- **CLI Parsing**: Argument parsing, validation, help text
- **Repository Manager**: Multi-repo operations, sync operations
- **Configuration Manager**: Config loading, validation, repository management

### Functional Tests (Shell)

#### Basic Operations
- Package linking, unlinking, relinking
- Module discovery and deployment  
- Conflict detection and resolution
- Advanced linking features (ignore patterns, tree folding)
- Configuration management commands

#### Git Integration
- Repository cloning and synchronization
- Multi-repository management
- Conflict resolution without user intervention
- Branch switching and management  
- Push/pull operations across repositories

#### Advanced Scenarios
- Dual repository workflows
- Cross-repository conflict handling
- Multi-PC development simulation
- Error recovery and edge cases

## Test Repositories

### Repository Details
- **Primary**: `git@github.com:adaryorg/ndmgr_test.git`
  - Contains comprehensive test modules with `.ndmgr` configuration files
  - Multiple branches: main, development, feature branches
  - Used for basic git integration testing

- **Secondary**: `git@github.com:adaryorg/ndmgr_test2.git`  
  - Used for dual-repository scenarios
  - Cross-repository conflict testing
  - Multi-repo synchronization testing

### Repository Usage Rules
1. **SSH Only**: Use SSH URLs, not HTTPS (repositories are private)
2. **No Git Config Changes**: Use preconfigured git name/email, do not modify during tests
3. **Generic Names**: All modules use generic names (editor_config, shell_config, etc.)
4. **NDMGR-Only Modifications**: Repositories should only be modified by ndmgr or test setup scripts

## Test Execution Details

### Test Environment
Each test runs in an isolated temporary directory with:
- `dotfiles/` - Source directory with packages/modules  
- `target/` - Target directory where symlinks are created
- Automatic cleanup after each test
- No interference between test runs

### Expected Results
- **Unit Tests**: All tests should pass (149 tests as of current version)
- **Functional Tests**: Tests may be skipped if SSH access unavailable
- **Git Tests**: Require network access and SSH authentication
- **Output**: Plain text only, no colors, no progress bars, no timing information

### Test Output Format
```
[INFO] Running test: Test Name
[PASS] Test Name
[FAIL] Test Name  
[SKIP] Test Name (reason)

Summary: X passed, Y failed, Z skipped
```

## Test Files Description

### Core Test Files

#### `run_all_functional_tests.sh` - Master Test Runner
Coordinates all test suites:
- Runs unit tests (`zig build test`)
- Executes all functional test suites
- Provides summary of results across all test types
- Entry point for complete testing

#### `test_suite.sh` - Original Functional Tests
Comprehensive shell-based tests:
- Basic operations (link, unlink, relink)
- Module discovery and deployment
- Configuration management
- Git integration basics

#### `test_comprehensive_functional.sh` - Extended Tests  
Advanced functional testing:
- Dual repository scenarios using both test repos
- All CLI command combinations
- Error handling and edge cases
- Uses generic module names only

#### `test_git_conflicts.sh` - Git Conflict Resolution
Specialized git conflict testing:
- Automatic conflict resolution without user intervention
- Multi-PC development workflow simulation
- Cross-repository conflict scenarios
- Focus on no-user-intervention requirement

#### `test_git_branches.sh` - Git Branch Operations
Git branch functionality testing:
- Multi-branch deployment scenarios
- Branch switching and management
- Branch-specific conflict resolution

#### `setup_test_repos.sh` - Repository Setup
Populates test repositories with:
- Generic test modules (editor_config, shell_config, etc.)
- Multiple branches for testing
- Conflict simulation data

## Important Notes

### No Visual Elements
- **No Colors**: Plain text output only
- **No Progress Bars**: No visual progress indicators
- **No Timing**: No operation timing display
- **No Emojis/Icons**: Simple text-based status messages

### Repository Requirements
- **SSH Access Required**: Tests use `git@github.com:` URLs exclusively
- **Preconfigured Git**: Use existing git name/email configuration
- **Generic Naming**: All test modules use generic names to avoid confusion with real applications
- **Private Repositories**: Both test repositories are private and require SSH authentication