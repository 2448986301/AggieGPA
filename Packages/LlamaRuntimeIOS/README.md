# LlamaRuntimeIOS

This package contains the iOS device and iOS Simulator slices of the official
llama.cpp b10375 Apple XCFramework used by Aggie GPA's optional local AI
provider.

- Source release: https://github.com/ggml-org/llama.cpp/releases/tag/b10375
- Runtime license: MIT
- Release archive SHA-256: 904bbf9fd613ff4567bd22597d5d1391c3a88c69c327fb2ff2dd722f74231c77
- Model files are never bundled; AIModelStore keeps verified Qwen GGUF
  artifacts in Application Support and excludes them from backup.

The complete locally downloaded XCFramework remains outside this release
subset for provenance and future architecture needs. This checked-in package
contains only the two slices required by the iOS app and its simulator tests.
