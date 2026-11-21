# Contributing to SuperStore

Thank you for your interest in contributing to SuperStore! SuperStore is a community-driven project, and contributions from the community help make it better for everyone.

By contributing to SuperStore, you agree to the Developer Certificate of Origin outlined in [CERTIFICATE-OF-ORIGIN.md](CERTIFICATE-OF-ORIGIN.md). All contributions made after its introduction are subject to its terms.

## Ways to Contribute

You don't have to be a developer to help out. There are plenty of ways to contribute:

- **Documentation:** Improve guides and documentation at [SuperStore Docs](https://github.com/SuperStore/Superstore-Docs).
- **Bug Reports & Feature Requests:** Report bugs, suggest improvements, or request features through [GitHub Issues](https://github.com/izzv/SuperStore/issues/new/choose).
- **Community Support:** Help other users troubleshoot problems and answer questions.
- **Discussions:** Share ideas and participate in conversations through [GitHub Discussions](https://github.com/izzv/SuperStore/discussions).
- **Discord:** Join our community and connect with other contributors at [Discord](https://discord.gg/eqCMBW6ZQ7).

This guide covers the development setup and workflow for contributing code. If you run into problems along the way, feel free to ask for help in our [Discord server](https://discord.gg/eqCMBW6ZQ7).

## Requirements

Before getting started, make sure you have:

- macOS
- Xcode installed
- Basic command-line knowledge
- Basic Git knowledge (GitHub Desktop is recommended if you're new to Git)
- Basic Swift and iOS development knowledge

## Getting Started

### 1. Fork the Repository

Fork the SuperStore repository on GitHub to your own account.

### 2. Clone Your Fork

Clone your fork, including its submodules:

```bash
git clone https://github.com/izzv/SuperStore.git --recurse-submodules
```

If you're using GitHub Desktop, follow the [GitHub guide to cloning and forking repositories](https://docs.github.com/en/desktop/contributing-and-collaborating-using-github-desktop/adding-and-cloning-repositories-from-github-desktop).

### 3. Configure Code Signing

Copy `CodeSigning.xcconfig.sample` to `CodeSigning.xcconfig` and fill in the required values for your development environment.

### 4. Configure Your Device (Development Only)

If you're running SideStore directly through Xcode, update `ALTDeviceID` in `Info.plist` with your device's UDID.

Normally, SideServer automatically embeds your device's UDID into SideStore's `Info.plist` during installation. When running through Xcode, however, you'll need to set it manually so SideStore can properly resign and install apps for your device.

### 5. Open the Project

Open `AltStore.xcodeproj` in Xcode and you're ready to start developing.

Once you've made and tested your changes, commit and push them to your fork, then open a pull request.

## Prebuilt Binaries

SuperStore uses prebuilt static libraries for `minimuxer` and `em_proxy`. These are built through GitHub Actions to speed up development and eliminate the need to install Rust when working on the project.

Before each build, Xcode runs [`SideStore/fetch-prebuilt.sh`](./SideStore/fetch-prebuilt.sh) to check whether the downloaded binaries need updating. Updates are checked every six hours.

To force a check for new binaries, run:

```bash
bash ./SideStore/fetch-prebuilt.sh force
```

## Building with Xcode

Install CocoaPods if you haven't already:

```bash
brew install cocoapods
```

Then install the project dependencies from the repository root:

```bash
pod install
```

After CocoaPods finishes installing the dependencies, you can build and run the project directly through Xcode.

## Building an IPA

You can build a signed IPA from the command line using the included Makefile.

### Install Dependencies

```bash
brew install cocoapods
pod install
```

### Build Configurations

The default build configuration is `Release`.

| Build Type | Command |
|---|---|
| Stable Release | `make build fakesign ipa` |
| Stable Debug | `export BUILD_CONFIG=Debug; make build fakesign ipa` |
| Alpha Release | `export IS_ALPHA=1; make build fakesign ipa` |
| Alpha Debug | `export IS_ALPHA=1; export BUILD_CONFIG=Debug; make build fakesign ipa` |
| Beta Release | `export IS_BETA=1; make build fakesign ipa` |
| Beta Debug | `export IS_BETA=1; export BUILD_CONFIG=Debug; make build fakesign ipa` |

After a successful build, the generated IPA will be named `SideStore.ipa`.

### Custom Bundle Identifier

By default, command-line builds use the bundle identifier:

`com.SideStore.SideStore`

If you need a custom bundle identifier, set `BUNDLE_ID_SUFFIX` before building:

```bash
export BUNDLE_ID_SUFFIX=XYZ0123456
make build fakesign ipa
```

For a debug build:

```bash
export BUNDLE_ID_SUFFIX=XYZ0123456
export BUILD_CONFIG=Debug
make build fakesign ipa
```

When building through Xcode, `BUNDLE_ID_SUFFIX` defaults to the value of `DEVELOPMENT_TEAM`. You can override or remove this setting in your `CodeSigning.xcconfig` file.

## Privacy Warning

Builds may contain paths referencing your local Xcode DerivedData directory and, if you built `minimuxer` locally, paths referencing your `$HOME/.cargo` directory. These paths can expose your local username.

If you want to avoid exposing your username in the build, we recommend using GitHub Actions to build the IPA instead of building locally.
