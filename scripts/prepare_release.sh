#!/bin/bash

# FortDocs Release Preparation Script
# This script prepares everything needed for a new release

set -e
set -u

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RELEASE_DIR="$PROJECT_ROOT/release"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
FortDocs Release Preparation Script

Usage: $0 [OPTIONS] VERSION_TYPE

VERSION_TYPES:
    patch       Increment patch version (1.0.0 -> 1.0.1)
    minor       Increment minor version (1.0.0 -> 1.1.0)
    major       Increment major version (1.0.0 -> 2.0.0)

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -n, --dry-run          Show what would be done without executing
    --skip-tests           Skip running tests
    --skip-changelog       Skip changelog generation
    --beta                 Prepare beta release

EXAMPLES:
    $0 patch                Prepare patch release
    $0 minor                Prepare minor release
    $0 --beta patch         Prepare beta patch release

EOF
}

get_current_version() {
    cd "$PROJECT_ROOT"
    agvtool what-marketing-version -terse1 | head -1
}

get_current_build() {
    cd "$PROJECT_ROOT"
    agvtool what-version -terse
}

increment_version() {
    local version_type="$1"
    local current_version
    current_version=$(get_current_version)
    
    log_info "Current version: $current_version"
    
    # Parse version components
    IFS='.' read -ra VERSION_PARTS <<< "$current_version"
    local major="${VERSION_PARTS[0]}"
    local minor="${VERSION_PARTS[1]}"
    local patch="${VERSION_PARTS[2]}"
    
    # Increment based on type
    case "$version_type" in
        patch)
            patch=$((patch + 1))
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        *)
            log_error "Invalid version type: $version_type"
            exit 1
            ;;
    esac
    
    local new_version="$major.$minor.$patch"
    log_info "New version: $new_version"
    
    if [[ "$DRY_RUN" != true ]]; then
        cd "$PROJECT_ROOT"
        agvtool new-marketing-version "$new_version"
    fi
    
    echo "$new_version"
}

generate_changelog() {
    log_info "Generating changelog..."
    
    local last_tag
    last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    
    local changelog_file="$RELEASE_DIR/CHANGELOG.md"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would generate changelog from $last_tag to HEAD"
        return
    fi
    
    mkdir -p "$RELEASE_DIR"
    
    {
        echo "# Changelog"
        echo ""
        echo "## Version $NEW_VERSION"
        echo ""
        echo "### Changes"
        echo ""
        
        if [[ -n "$last_tag" ]]; then
            git log --pretty=format:"- %s" "$last_tag..HEAD" | grep -v "Merge pull request"
        else
            git log --pretty=format:"- %s" | grep -v "Merge pull request"
        fi
        
        echo ""
        echo ""
        echo "### Technical Details"
        echo ""
        echo "- Build: $(get_current_build)"
        echo "- Release Date: $(date '+%Y-%m-%d')"
        echo "- Git Commit: $(git rev-parse --short HEAD)"
        echo ""
    } > "$changelog_file"
    
    log_success "Changelog generated: $changelog_file"
}

run_tests() {
    if [[ "$SKIP_TESTS" == true ]]; then
        log_warning "Skipping tests as requested"
        return
    fi
    
    log_info "Running tests..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would run tests"
        return
    fi
    
    cd "$PROJECT_ROOT"
    fastlane test
    
    log_success "Tests completed successfully"
}

create_release_notes() {
    log_info "Creating release notes..."
    
    local release_notes_file="$RELEASE_DIR/release_notes_$NEW_VERSION.md"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create release notes"
        return
    fi
    
    mkdir -p "$RELEASE_DIR"
    
    {
        echo "# FortDocs v$NEW_VERSION Release Notes"
        echo ""
        echo "## What's New"
        echo ""
        echo "### 🔒 Security Enhancements"
        echo "- Enhanced encryption protocols"
        echo "- Improved biometric authentication"
        echo "- Security vulnerability fixes"
        echo ""
        echo "### 📱 Features & Improvements"
        echo "- Performance optimizations"
        echo "- UI/UX enhancements"
        echo "- Bug fixes and stability improvements"
        echo ""
        echo "### 🔍 Search & Organization"
        echo "- Improved search accuracy"
        echo "- Enhanced document organization"
        echo "- Better OCR recognition"
        echo ""
        echo "## Technical Information"
        echo ""
        echo "- **Version:** $NEW_VERSION"
        echo "- **Build:** $(get_current_build)"
        echo "- **Release Date:** $(date '+%B %d, %Y')"
        echo "- **Minimum iOS:** 17.0"
        echo "- **Compatibility:** iPhone 12 and later"
        echo ""
        echo "## Security & Privacy"
        echo ""
        echo "FortDocs continues to maintain its zero-knowledge architecture with:"
        echo "- AES-256-GCM encryption"
        echo "- Secure Enclave integration"
        echo "- No data collection or tracking"
        echo "- Full GDPR and CCPA compliance"
        echo ""
        echo "## Support"
        echo ""
        echo "For support, please contact: support@fortdocs.app"
        echo "Privacy Policy: https://fortdocs.app/privacy"
        echo "Terms of Service: https://fortdocs.app/terms"
    } > "$release_notes_file"
    
    log_success "Release notes created: $release_notes_file"
}

validate_release() {
    log_info "Validating release..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would validate release"
        return
    fi
    
    # Check git status
    if [[ -n $(git status --porcelain) ]]; then
        log_error "Working directory is not clean. Please commit or stash changes."
        exit 1
    fi
    
    # Check if we're on main branch
    local current_branch
    current_branch=$(git branch --show-current)
    if [[ "$current_branch" != "main" ]]; then
        log_error "Not on main branch. Current branch: $current_branch"
        exit 1
    fi
    
    # Validate version format
    if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid version format: $NEW_VERSION"
        exit 1
    fi
    
    log_success "Release validation passed"
}

create_release_checklist() {
    log_info "Creating release checklist..."
    
    local checklist_file="$RELEASE_DIR/release_checklist_$NEW_VERSION.md"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create release checklist"
        return
    fi
    
    mkdir -p "$RELEASE_DIR"
    
    {
        echo "# FortDocs v$NEW_VERSION Release Checklist"
        echo ""
        echo "## Pre-Release"
        echo ""
        echo "- [ ] All tests passing"
        echo "- [ ] Security scan completed"
        echo "- [ ] Code review completed"
        echo "- [ ] Version number updated"
        echo "- [ ] Changelog generated"
        echo "- [ ] Release notes created"
        echo "- [ ] App Store metadata updated"
        echo "- [ ] Screenshots updated (if needed)"
        echo ""
        echo "## Beta Testing"
        echo ""
        echo "- [ ] Internal beta deployed to TestFlight"
        echo "- [ ] Internal testing completed"
        echo "- [ ] External beta deployed (if needed)"
        echo "- [ ] External testing feedback incorporated"
        echo "- [ ] Performance testing completed"
        echo "- [ ] Security testing completed"
        echo ""
        echo "## App Store Submission"
        echo ""
        echo "- [ ] Final build uploaded to App Store Connect"
        echo "- [ ] App Store metadata finalized"
        echo "- [ ] Screenshots and app preview updated"
        echo "- [ ] App submitted for review"
        echo "- [ ] Review feedback addressed (if any)"
        echo "- [ ] App approved and ready for release"
        echo ""
        echo "## Post-Release"
        echo ""
        echo "- [ ] Release announcement prepared"
        echo "- [ ] Social media posts scheduled"
        echo "- [ ] Support documentation updated"
        echo "- [ ] Monitoring and analytics configured"
        echo "- [ ] User feedback monitoring active"
        echo ""
        echo "## Emergency Procedures"
        echo ""
        echo "- [ ] Rollback plan documented"
        echo "- [ ] Critical issue response plan ready"
        echo "- [ ] Support team briefed"
        echo "- [ ] Escalation procedures confirmed"
        echo ""
        echo "---"
        echo ""
        echo "**Release Manager:** [Name]"
        echo "**Release Date:** $(date '+%Y-%m-%d')"
        echo "**Version:** $NEW_VERSION"
        echo "**Build:** $(get_current_build)"
    } > "$checklist_file"
    
    log_success "Release checklist created: $checklist_file"
}

# Default values
VERSION_TYPE=""
SKIP_TESTS=false
SKIP_CHANGELOG=false
VERBOSE=false
DRY_RUN=false
BETA_RELEASE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --skip-changelog)
            SKIP_CHANGELOG=true
            shift
            ;;
        --beta)
            BETA_RELEASE=true
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            VERSION_TYPE="$1"
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$VERSION_TYPE" ]]; then
    log_error "Version type is required"
    show_usage
    exit 1
fi

# Main execution
main() {
    log_info "FortDocs Release Preparation Starting..."
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Validate release
    validate_release
    
    # Increment version
    NEW_VERSION=$(increment_version "$VERSION_TYPE")
    
    if [[ "$BETA_RELEASE" == true ]]; then
        NEW_VERSION="$NEW_VERSION-beta"
        log_info "Preparing beta release: $NEW_VERSION"
    fi
    
    # Run tests
    run_tests
    
    # Generate changelog
    if [[ "$SKIP_CHANGELOG" != true ]]; then
        generate_changelog
    fi
    
    # Create release notes
    create_release_notes
    
    # Create release checklist
    create_release_checklist
    
    # Summary
    log_success "Release preparation completed!"
    echo ""
    echo "Next steps:"
    echo "1. Review the generated files in $RELEASE_DIR"
    echo "2. Run: ./scripts/deploy.sh beta"
    echo "3. Test the beta build thoroughly"
    echo "4. Run: ./scripts/deploy.sh release"
    echo "5. Follow the release checklist"
}

# Run main function
main "$@"

