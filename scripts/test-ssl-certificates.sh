#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_root="$repo_root/.build/ssl-certificate-tests"

# Keep these Foundation-only tests independent of the iOS signing toolchain.
mkdir -p "$test_root/Sources/RyukSign" "$test_root/Tests/RyukSignTests"
cp "$repo_root/RyukSign/Utilities/SSLCertificateUpdater.swift" "$test_root/Sources/RyukSign/"
cp "$repo_root/RyukSignTests/SSLCertificateUpdaterTests.swift" "$test_root/Tests/RyukSignTests/"
cat > "$test_root/Package.swift" <<'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SSLCertificateRegressionTests",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "RyukSign"),
        .testTarget(name: "RyukSignTests", dependencies: ["RyukSign"])
    ]
)
EOF

swift test --package-path "$test_root" "$@"
