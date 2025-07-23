#!/bin/bash

# FortDocs Deployment Script
# This script handles deployment to different environments

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FASTLANE_DIR="$PROJECT_ROOT/fastlane"
BUILD_DIR="$PROJECT_ROOT/build"
LOGS_DIR="$PROJECT_ROOT/logs"

# Default values
ENVIRONMENT="beta"
SKIP_TESTS=false
SKIP_SECURITY_SCAN=false
VERBOSE=false
DRY_RUN=false

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
FortDocs Deployment Script

Usage: $0 [OPTIONS] ENVIRONMENT

ENVIRONMENTS:
    dev         Build for development
    beta        Deploy to TestFlight (internal)
    beta-ext    Deploy to TestFlight (external)
    release     Deploy to App Store
    validate    Validate build without deployment

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -n, --dry-run          Show what would be done without executing
    -s, --skip-tests       Skip running tests
    --skip-security-scan   Skip security scanning
    --clean                Clean build artifacts before deployment
    --setup-certs          Setup certificates and provisioning profiles

EXAMPLES:
    $0 beta                 Deploy to TestFlight (internal)
    $0 beta-ext             Deploy to TestFlight (external)
    $0 release              Deploy to App Store
    $0 --clean beta         Clean and deploy to TestFlight
    $0 --dry-run release    Show release deployment steps

ENVIRONMENT VARIABLES:
    APPLE_ID                Apple Developer Account ID
    TEAM_ID                 Apple Developer Team ID
    ITC_TEAM_ID            iTunes Connect Team ID
    APP_STORE_CONNECT_API_KEY_PATH  Path to App Store Connect API key
    KEYCHAIN_PASSWORD       Password for temporary keychain
    SLACK_URL              Slack webhook URL for notifications
    GITHUB_TOKEN           GitHub token for release creation

EOF
}

check_requirements() {
    log_info "Checking requirements..."
    
    # Check if we're in the right directory
    if [[ ! -f "$PROJECT_ROOT/FortDocs.xcodeproj/project.pbxproj" ]]; then
        log_error "FortDocs.xcodeproj not found. Please run this script from the project root."
        exit 1
    fi
    
    # Check if Fastlane is installed
    if ! command -v fastlane &> /dev/null; then
        log_error "Fastlane is not installed. Please install it first:"
        echo "  gem install fastlane"
        exit 1
    fi
    
    # Check if Xcode is installed
    if ! command -v xcodebuild &> /dev/null; then
        log_error "Xcode command line tools are not installed."
        exit 1
    fi
    
    # Check required environment variables
    local required_vars=("APPLE_ID" "TEAM_ID" "APP_STORE_CONNECT_API_KEY_PATH" "KEYCHAIN_PASSWORD")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        printf '  %s\n' "${missing_vars[@]}"
        echo ""
        echo "Please set these variables in your environment or .env file."
        exit 1
    fi
    
    log_success "Requirements check passed"
}

setup_environment() {
    log_info "Setting up environment..."
    
    # Create necessary directories
    mkdir -p "$BUILD_DIR"
    mkdir -p "$LOGS_DIR"
    
    # Load environment variables from .env file if it exists
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        log_info "Loading environment variables from .env file"
        set -a  # Automatically export all variables
        source "$PROJECT_ROOT/.env"
        set +a
    fi
    
    # Set up logging
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    export FASTLANE_LOG_FILE="$LOGS_DIR/fastlane_${ENVIRONMENT}_${timestamp}.log"
    
    if [[ "$VERBOSE" == true ]]; then
        export FASTLANE_VERBOSE=1
    fi
    
    log_success "Environment setup completed"
}

clean_build_artifacts() {
    log_info "Cleaning build artifacts..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would clean build artifacts"
        return
    fi
    
    cd "$PROJECT_ROOT"
    fastlane clean
    
    log_success "Build artifacts cleaned"
}

setup_certificates() {
    log_info "Setting up certificates and provisioning profiles..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would setup certificates"
        return
    fi
    
    cd "$PROJECT_ROOT"
    fastlane setup_certificates
    
    log_success "Certificates setup completed"
}

run_deployment() {
    log_info "Starting deployment for environment: $ENVIRONMENT"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would run: fastlane $ENVIRONMENT"
        return
    fi
    
    cd "$PROJECT_ROOT"
    
    # Build fastlane command
    local fastlane_cmd="fastlane $ENVIRONMENT"
    
    # Add options based on flags
    if [[ "$SKIP_TESTS" == true ]]; then
        fastlane_cmd+=" skip_tests:true"
    fi
    
    if [[ "$SKIP_SECURITY_SCAN" == true ]]; then
        fastlane_cmd+=" skip_security_scan:true"
    fi
    
    log_info "Running: $fastlane_cmd"
    
    # Execute fastlane command
    if eval "$fastlane_cmd"; then
        log_success "Deployment completed successfully!"
    else
        log_error "Deployment failed!"
        exit 1
    fi
}

validate_environment() {
    case "$ENVIRONMENT" in
        dev|beta|beta-ext|release|validate)
            log_info "Environment '$ENVIRONMENT' is valid"
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT"
            log_error "Valid environments: dev, beta, beta-ext, release, validate"
            exit 1
            ;;
    esac
}

show_deployment_summary() {
    log_info "Deployment Summary:"
    echo "  Environment: $ENVIRONMENT"
    echo "  Skip Tests: $SKIP_TESTS"
    echo "  Skip Security Scan: $SKIP_SECURITY_SCAN"
    echo "  Verbose: $VERBOSE"
    echo "  Dry Run: $DRY_RUN"
    echo "  Project Root: $PROJECT_ROOT"
    echo "  Build Directory: $BUILD_DIR"
    echo "  Logs Directory: $LOGS_DIR"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warning "This is a dry run - no actual deployment will occur"
    fi
}

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
        -s|--skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --skip-security-scan)
            SKIP_SECURITY_SCAN=true
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --setup-certs)
            SETUP_CERTS=true
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            ENVIRONMENT="$1"
            shift
            ;;
    esac
done

# Main execution
main() {
    log_info "FortDocs Deployment Script Starting..."
    
    # Validate environment
    validate_environment
    
    # Check requirements
    check_requirements
    
    # Setup environment
    setup_environment
    
    # Show deployment summary
    show_deployment_summary
    
    # Ask for confirmation if not dry run
    if [[ "$DRY_RUN" != true ]]; then
        echo ""
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Clean build artifacts if requested
    if [[ "${CLEAN_BUILD:-false}" == true ]]; then
        clean_build_artifacts
    fi
    
    # Setup certificates if requested
    if [[ "${SETUP_CERTS:-false}" == true ]]; then
        setup_certificates
    fi
    
    # Run deployment
    run_deployment
    
    log_success "Deployment script completed successfully!"
}

# Run main function
main "$@"

