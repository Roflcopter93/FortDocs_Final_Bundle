# FortDocs Developer Guide

## Table of Contents

1. [Project Overview](#project-overview)
2. [Quick Start](#quick-start)
3. [Development Setup](#development-setup)
4. [Architecture Overview](#architecture-overview)
5. [Security Implementation](#security-implementation)
6. [Deployment Guide](#deployment-guide)
7. [Testing Strategy](#testing-strategy)
8. [App Store Submission](#app-store-submission)
9. [Maintenance & Updates](#maintenance--updates)
10. [Troubleshooting](#troubleshooting)

## Project Overview

FortDocs is a privacy-first document vault application for iOS that provides military-grade security for personal and business documents. The application is built with SwiftUI and follows a zero-knowledge architecture, ensuring that user data remains completely private and secure.

### Key Features

- **Military-Grade Encryption**: AES-256-GCM encryption with Secure Enclave integration
- **Advanced Document Scanning**: VisionKit integration with OCR text extraction
- **Intelligent Organization**: Hierarchical folder system with smart categorization
- **Powerful Search**: Full-text search with Core Spotlight integration
- **Seamless Sync**: End-to-end encrypted iCloud synchronization
- **Biometric Security**: Face ID, Touch ID, and Optic ID support
- **Privacy-First Design**: Zero-knowledge architecture with no data collection

### Technical Stack

- **Platform**: iOS 17.0+
- **Language**: Swift 5.9
- **UI Framework**: SwiftUI
- **Data Persistence**: Core Data with CloudKit
- **Security**: CryptoKit, LocalAuthentication, Secure Enclave
- **Document Processing**: VisionKit, Vision Framework
- **Search**: Core Spotlight, NSPredicate
- **Testing**: XCTest, UI Testing
- **CI/CD**: GitHub Actions, Fastlane
- **Deployment**: App Store Connect, TestFlight

## Quick Start

### Prerequisites

- macOS 14.0 or later
- Xcode 15.2 or later
- iOS 17.0+ device or simulator
- Apple Developer Account
- Git

### Initial Setup

1. **Clone the Repository**
   ```bash
   git clone https://github.com/your-org/fortdocs-ios.git
   cd fortdocs-ios
   ```

2. **Install Dependencies**
   ```bash
   # Install Fastlane
   gem install fastlane
   
   # Install SwiftLint (optional but recommended)
   brew install swiftlint
   ```

3. **Configure Environment**
   ```bash
   # Copy environment template
   cp .env.template .env
   
   # Edit .env with your configuration
   nano .env
   ```

4. **Open in Xcode**
   ```bash
   open FortDocs.xcodeproj
   ```

5. **Build and Run**
   - Select your target device or simulator
   - Press Cmd+R to build and run

## Development Setup

### Environment Configuration

The project uses environment variables for configuration. Copy `.env.template` to `.env` and configure the following essential variables:

```bash
# Apple Developer Configuration
APPLE_ID=your.apple.id@example.com
TEAM_ID=YOUR_TEAM_ID_HERE
APP_STORE_CONNECT_API_KEY_PATH=/path/to/AuthKey_XXXXXXXXXX.p8

# Security
KEYCHAIN_PASSWORD=your_secure_password

# Optional: Notifications
SLACK_URL=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK
```

### Code Signing Setup

1. **Automatic Signing** (Recommended for development)
   - Open project in Xcode
   - Select FortDocs target
   - Enable "Automatically manage signing"
   - Select your development team

2. **Manual Signing** (For production)
   ```bash
   # Setup certificates using Fastlane Match
   fastlane setup_certificates
   ```

### Development Workflow

1. **Create Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make Changes**
   - Follow Swift coding conventions
   - Add unit tests for new functionality
   - Update documentation as needed

3. **Run Tests**
   ```bash
   fastlane test
   ```

4. **Code Quality Check**
   ```bash
   swiftlint
   ```

5. **Commit and Push**
   ```bash
   git add .
   git commit -m "Add: your feature description"
   git push origin feature/your-feature-name
   ```

6. **Create Pull Request**
   - Open PR on GitHub
   - Ensure CI checks pass
   - Request code review

## Architecture Overview

### Project Structure

```
FortDocs/
├── FortDocs/
│   ├── Models/              # Core Data models
│   ├── Views/               # SwiftUI views
│   ├── ViewModels/          # MVVM view models
│   ├── Services/            # Business logic services
│   ├── Utils/               # Utility classes and extensions
│   └── Resources/           # Assets, localizations
├── Tests/
│   ├── Unit/                # Unit tests
│   ├── UI/                  # UI tests
│   └── Integration/         # Integration tests
├── fastlane/                # Deployment automation
├── scripts/                 # Build and deployment scripts
└── AppStore/                # App Store assets and metadata
```

### MVVM Architecture

FortDocs follows the Model-View-ViewModel (MVVM) pattern:

- **Models**: Core Data entities and data structures
- **Views**: SwiftUI views for user interface
- **ViewModels**: Business logic and state management
- **Services**: Shared business logic and external integrations

### Core Services

1. **CryptoVault**: Handles all encryption and decryption operations
2. **AuthenticationService**: Manages biometric and PIN authentication
3. **DocumentScanner**: Processes document scanning and OCR
4. **SearchIndex**: Manages search indexing and Core Spotlight integration
5. **CloudKitService**: Handles iCloud synchronization
6. **FolderStore**: Manages folder operations and organization

### Data Flow

1. User interacts with SwiftUI Views
2. Views communicate with ViewModels
3. ViewModels call appropriate Services
4. Services interact with Core Data and external APIs
5. Changes propagate back through the chain

## Security Implementation

### Encryption Architecture

FortDocs implements a zero-knowledge encryption architecture:

1. **Key Generation**: Uses CryptoKit to generate AES-256-GCM keys
2. **Key Storage**: Keys stored in iOS Secure Enclave when available
3. **Data Encryption**: All documents encrypted before storage
4. **Cloud Sync**: Only encrypted data synchronized to iCloud

### Authentication Flow

1. **Primary Authentication**: Face ID, Touch ID, or Optic ID
2. **Fallback Authentication**: 5-digit PIN with secure hashing
3. **Lockout Protection**: Progressive delays after failed attempts
4. **Security Hardening**: Anti-jailbreak and screenshot protection

### Security Best Practices

- Never store unencrypted sensitive data
- Use hardware-backed security when available
- Implement proper key rotation
- Regular security audits and updates
- Follow OWASP mobile security guidelines

## Deployment Guide

### Development Builds

```bash
# Build for development
./scripts/deploy.sh dev

# Or using Fastlane directly
fastlane build_dev
```

### Beta Deployment

```bash
# Internal beta
./scripts/deploy.sh beta

# External beta
./scripts/deploy.sh beta-ext
```

### Production Release

```bash
# Prepare release
./scripts/prepare_release.sh minor

# Deploy to App Store
./scripts/deploy.sh release

# Submit for review
fastlane submit_review
```

### Deployment Options

The deployment script supports various options:

```bash
# Skip tests (not recommended)
./scripts/deploy.sh --skip-tests beta

# Clean build
./scripts/deploy.sh --clean release

# Dry run (show what would happen)
./scripts/deploy.sh --dry-run release

# Verbose output
./scripts/deploy.sh --verbose beta
```

## Testing Strategy

### Unit Tests

Located in `Tests/Unit/`, covering:

- **Services**: CryptoVault, AuthenticationService, SearchIndex
- **ViewModels**: Business logic and state management
- **Models**: Data validation and transformations
- **Utils**: Helper functions and extensions

Run unit tests:
```bash
fastlane test
# or
xcodebuild test -project FortDocs.xcodeproj -scheme FortDocs -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

### UI Tests

Located in `Tests/UI/`, covering:

- **Authentication Flow**: Biometric and PIN authentication
- **Document Management**: Scanning, organizing, searching
- **Settings**: Security configuration and preferences

### Integration Tests

Located in `Tests/Integration/`, covering:

- **End-to-End Workflows**: Complete user journeys
- **iCloud Sync**: Multi-device synchronization
- **Performance**: Memory usage and response times

### Test Data

Use the provided test data generators:

```swift
// Generate test documents
let testDocument = TestDataGenerator.createDocument()

// Generate test folders
let testFolder = TestDataGenerator.createFolder()
```

### Continuous Integration

GitHub Actions automatically runs:

1. Unit tests on multiple iOS versions
2. UI tests on iPhone and iPad simulators
3. Security scans with SwiftLint and Semgrep
4. Performance tests and memory leak detection

## App Store Submission

### Pre-Submission Checklist

1. **Code Quality**
   - [ ] All tests passing
   - [ ] SwiftLint warnings resolved
   - [ ] Security scan completed
   - [ ] Performance testing completed

2. **App Store Assets**
   - [ ] App icons (all sizes)
   - [ ] Screenshots (iPhone and iPad)
   - [ ] App preview videos (optional)
   - [ ] App Store description
   - [ ] Keywords and categories

3. **Legal Requirements**
   - [ ] Privacy policy updated
   - [ ] Terms of service current
   - [ ] Export compliance documentation
   - [ ] Content rating appropriate

4. **Testing**
   - [ ] Internal testing completed
   - [ ] External beta testing (if applicable)
   - [ ] Accessibility testing
   - [ ] Localization testing

### Submission Process

1. **Upload Build**
   ```bash
   fastlane release
   ```

2. **Update Metadata**
   ```bash
   fastlane update_metadata
   ```

3. **Submit for Review**
   ```bash
   fastlane submit_review
   ```

4. **Monitor Review Status**
   - Check App Store Connect regularly
   - Respond to review feedback promptly
   - Address any rejection reasons

### Post-Approval

1. **Release Management**
   - Choose manual or automatic release
   - Monitor initial user feedback
   - Prepare for support inquiries

2. **Analytics Setup**
   - Configure App Store analytics
   - Monitor crash reports
   - Track user engagement metrics

## Maintenance & Updates

### Regular Maintenance Tasks

1. **Security Updates**
   - Monitor security advisories
   - Update dependencies regularly
   - Conduct security audits

2. **Performance Monitoring**
   - Monitor app performance metrics
   - Optimize based on user feedback
   - Address memory leaks and crashes

3. **Feature Updates**
   - Plan feature roadmap
   - Gather user feedback
   - Implement requested features

### Update Process

1. **Plan Update**
   ```bash
   ./scripts/prepare_release.sh patch  # or minor/major
   ```

2. **Develop Features**
   - Create feature branches
   - Implement and test changes
   - Update documentation

3. **Beta Testing**
   ```bash
   ./scripts/deploy.sh beta
   ```

4. **Release Update**
   ```bash
   ./scripts/deploy.sh release
   ```

### Version Management

FortDocs follows semantic versioning:

- **Major** (1.0.0 → 2.0.0): Breaking changes or major features
- **Minor** (1.0.0 → 1.1.0): New features, backward compatible
- **Patch** (1.0.0 → 1.0.1): Bug fixes and minor improvements

## Troubleshooting

### Common Issues

#### Build Errors

**Issue**: Code signing errors
```
Solution:
1. Check Team ID in .env file
2. Verify certificates in Keychain
3. Run: fastlane setup_certificates
```

**Issue**: Missing dependencies
```
Solution:
1. Clean derived data: Cmd+Shift+K
2. Reset package caches: File → Packages → Reset Package Caches
3. Rebuild project: Cmd+B
```

#### Deployment Issues

**Issue**: Fastlane authentication errors
```
Solution:
1. Verify App Store Connect API key
2. Check API key permissions
3. Ensure key file path is correct in .env
```

**Issue**: TestFlight upload failures
```
Solution:
1. Check build settings and provisioning
2. Verify app version and build number
3. Review upload logs in fastlane output
```

#### Runtime Issues

**Issue**: Core Data migration errors
```
Solution:
1. Check data model versions
2. Implement proper migration logic
3. Test with existing user data
```

**Issue**: iCloud sync problems
```
Solution:
1. Verify CloudKit configuration
2. Check iCloud account status
3. Test sync across multiple devices
```

### Debug Tools

1. **Xcode Debugger**
   - Set breakpoints in critical code paths
   - Use LLDB commands for advanced debugging
   - Monitor memory usage with Instruments

2. **Console Logging**
   ```swift
   import os.log
   
   let logger = Logger(subsystem: "com.fortdocs.app", category: "Security")
   logger.info("Encryption operation completed")
   ```

3. **Crash Reporting**
   - Monitor crash reports in App Store Connect
   - Use Xcode Organizer for detailed crash analysis
   - Implement custom crash reporting if needed

### Performance Optimization

1. **Memory Management**
   - Use weak references to avoid retain cycles
   - Implement proper image caching
   - Monitor memory usage with Instruments

2. **Battery Optimization**
   - Minimize background processing
   - Use efficient algorithms for search and encryption
   - Optimize Core Data queries

3. **Storage Optimization**
   - Implement document compression
   - Clean up temporary files
   - Optimize Core Data model

### Support Resources

- **Apple Developer Documentation**: https://developer.apple.com/documentation/
- **SwiftUI Documentation**: https://developer.apple.com/documentation/swiftui
- **Core Data Guide**: https://developer.apple.com/documentation/coredata
- **CryptoKit Documentation**: https://developer.apple.com/documentation/cryptokit
- **Fastlane Documentation**: https://docs.fastlane.tools/

### Getting Help

1. **Internal Documentation**
   - Check this developer guide
   - Review code comments and documentation
   - Consult architecture documentation

2. **Community Resources**
   - Stack Overflow for technical questions
   - Apple Developer Forums
   - Swift community forums

3. **Professional Support**
   - Apple Developer Technical Support
   - Third-party iOS development consultants
   - Security audit services

---

## Conclusion

FortDocs represents a comprehensive, security-first approach to document management on iOS. The application combines military-grade encryption with intuitive user experience, providing users with complete control over their sensitive documents.

The development infrastructure is designed for scalability and maintainability, with comprehensive testing, automated deployment, and thorough documentation. The zero-knowledge architecture ensures that user privacy is never compromised, while the professional-grade security implementation meets the highest industry standards.

This developer guide provides the foundation for maintaining and extending FortDocs. Regular updates to this documentation will ensure that future developers can effectively contribute to the project while maintaining the high standards of security and quality that define FortDocs.

For questions or support, please contact the development team or refer to the resources listed in this guide.

