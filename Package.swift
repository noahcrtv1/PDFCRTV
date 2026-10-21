// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PDFCRTV",
    platforms: [.macOS("26.0")],
    targets: [
        // Operações de PDF sem interface: páginas, junção, exportação, OCR, assinaturas. Testável.
        .target(
            name: "PDFCore",
            path: "Sources/PDFCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PDFCRTV",
            dependencies: ["PDFCore"],
            path: "Sources/PDFCRTV",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PDFCoreTests",
            dependencies: ["PDFCore"],
            path: "Tests/PDFCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
