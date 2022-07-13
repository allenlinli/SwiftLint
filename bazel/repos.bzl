load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def swiftlint_repos():
    """Fetches SwiftLint repositories"""
    http_archive(
        name = "com_github_jpsim_sourcekitten",
        url = "https://github.com/jpsim/SourceKitten/archive/391ed9e9781749fdc55ee17512906fd466b889c9.tar.gz",
        sha256 = "23cf838c98f14a62051b479704f96c595bac4ba44b319b3d995677d29e57dbc5",
        strip_prefix = "SourceKitten-391ed9e9781749fdc55ee17512906fd466b889c9",
    )

    SWIFTY_TEXT_TABLE_VERSION = "0.9.0"
    http_archive(
        name = "swiftlint_com_github_scottrhoyt_swifty_text_table",
        url = "https://github.com/scottrhoyt/SwiftyTextTable/archive/refs/tags/%s.tar.gz" % SWIFTY_TEXT_TABLE_VERSION,
        sha256 = "b77d403db9f33686caeb2a12986997fb02a0819e029e669c6b9554617c4fd6ae",
        build_file = "@com_github_realm_swiftlint//bazel:SwiftyTextTable.BUILD",
        strip_prefix = "SwiftyTextTable-%s" % SWIFTY_TEXT_TABLE_VERSION,
    )

    SWIFT_SYNTAX_VERSION = "13.3.13E113"
    http_archive(
        name = "com_github_keith_swift_syntax_bazel",
        sha256 = "f83b8449f84e29d263d2b0ceb9d2ae7f88c9f2a81f4b10035e94073664507507",
        strip_prefix = "swift-syntax-bazel-%s" % SWIFT_SYNTAX_VERSION,
        url = "https://github.com/keith/swift-syntax-bazel/archive/refs/tags/%s.tar.gz" % SWIFT_SYNTAX_VERSION,
    )

    CRYPTO_SWIFT_VERSION = "1.5.1"
    http_archive(
        name = "com_github_krzyzanowskim_cryptoswift",
        sha256 = "8460b44f8378c4201d15bd2617b2d8d1dbf5fef28cb8886ced4b72ad201e2361",
        build_file = "@com_github_realm_swiftlint//bazel:CryptoSwift.BUILD",
        strip_prefix = "CryptoSwift-%s" % CRYPTO_SWIFT_VERSION,
        url = "https://github.com/krzyzanowskim/CryptoSwift/archive/refs/tags/%s.tar.gz" % CRYPTO_SWIFT_VERSION,
    )
