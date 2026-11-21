# Contributing to SuperStore

SuperStore is an open-source project shaped by the people who use, maintain, and contribute to it. Contributions of all kinds help improve the project, whether that's fixing a problem, adding functionality, improving documentation, or helping other users.

This guide explains how to prepare your development environment, work with the source code, and submit changes.

## Ways to get involved

There are plenty of ways to contribute outside of development. You can:

- Improve our [documentation](https://github.com/SuperStore/Superstore-Docs).
- Report bugs or request features through [GitHub Issues](https://github.com/izzv/SuperStore/issues/new/choose).
- Help others troubleshoot and answer questions.
- Share ideas through [GitHub Discussions](https://github.com/izzv/SuperStore/discussions).
- Join the community on [Discord](https://discord.gg/eqCMBW6ZQ7).

If you need help with development or setup, you're welcome to ask in our [Discord server](https://discord.gg/eqCMBW6ZQ7).

## Requirements

Development requires:

- macOS
- Xcode
- Git
- Basic terminal knowledge
- Familiarity with Swift and iOS development

If you're unfamiliar with Git, [GitHub Desktop](https://desktop.github.com/) can make managing repositories and commits much easier.

## Setting up your environment

### Clone the repository

Fork the SuperStore repository on GitHub, then clone your fork with its submodules:

```bash
git clone https://github.com/izzv/SuperStore.git --recurse-submodules
```

You can also use [GitHub Desktop](https://docs.github.com/en/desktop/contributing-and-collaborating-using-github-desktop/adding-and-cloning-repositories-from-github-desktop) to fork and clone the project.

### Configure signing

Copy `CodeSigning.xcconfig.sample` to `CodeSigning.xcconfig` and enter the signing values required for your development environment.

For local device builds, set `ALTDeviceID` in `Info.plist` to your device's UDID. This value is normally configured automatically during installation, but running the project directly from Xcode requires it to be set manually for signing and installation to work correctly.

Once configured, open the project in Xcode using its `.xcodeproj` file.

## Submitting changes

Keep your changes focused, test them before submitting, and avoid including unrelated modifications.

When you're ready to contribute:

1. Commit your work.
2. Push your branch to your fork.
3. Open a pull request against the main repository.
4. Explain what changed and include any relevant testing information.

All contributions must comply with the [Developer Certificate of Origin](CERTIFICATE-OF-ORIGIN.md).

## Precompiled dependencies

Some dependencies are distributed as precompiled static libraries to make development and builds faster. These binaries are generated through GitHub Actions, so you don't need Rust installed for standard development builds.

The build process checks for updated binaries automatically. Checks are cached for six hours.

To force a fresh download, run:

```bash
bash ./SuperStore/fetch-prebuilt.sh force
```

## Building from source

### Install dependencies

Install CocoaPods using Homebrew if it's not already available:

```bash
brew install cocoapods
```

From the repository root, install the project's dependencies:

```bash
pod install
```

After installation finishes, you can build and run the project through Xcode.

## Creating an IPA

SuperStore includes a Makefile for generating IPA builds.

The default configuration is `Release`.

| Build type | Command |
|---|---|
| Release | `make build fakesign ipa` |
| Debug | `export BUILD_CONFIG=Debug; make build fakesign ipa` |
| Alpha | `export IS_ALPHA=1; make build fakesign ipa` |
| Alpha Debug | `export IS_ALPHA=1; export BUILD_CONFIG=Debug; make build fakesign ipa` |
| Beta | `export IS_BETA=1; make build fakesign ipa` |
| Beta Debug | `export IS_BETA=1; export BUILD_CONFIG=Debug; make build fakesign ipa` |

The resulting file will be named `SuperStore.ipa`.

### Custom bundle identifiers

The default bundle identifier should be configured for SuperStore. If you need to use a different identifier for command-line builds, set `BUNDLE_ID_SUFFIX` before building:

```bash
export BUNDLE_ID_SUFFIX=XYZ0123456
make build fakesign ipa
```

For debug builds:

```bash
export BUNDLE_ID_SUFFIX=XYZ0123456
export BUILD_CONFIG=Debug
make build fakesign ipa
```

When building from Xcode, the suffix defaults to your development team identifier. This can be customized through `CodeSigning.xcconfig`.

## Privacy considerations

Build artifacts may contain local filesystem paths from your Xcode build environment. These can include your DerivedData directory and, if dependencies were built locally, your Cargo directory.

Such paths may expose your system username. If you want to avoid including local information in your build, use GitHub Actions to build the IPA instead.
