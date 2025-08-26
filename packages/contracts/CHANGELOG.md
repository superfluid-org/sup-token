# Changelog

All notable changes to the Superfluid SPR contracts will be documented in this file.

## [v1.0.1] - 2025-08-26

### Added

- `FluidLocker::disconnectAndClaim` function to disconnect from pools no longer yielding SUP and claiming new units in one transaction.

### Changed

- `FluidLocker::claim` functions now use new internal `FluidLocker::_claim` & `FluidLocker::_claimBatch` functions.
- `FluidLocker::connectToPool` and `FluidLocker::disconnectFromPool` are renamed to `FluidLocker::connect` and `FluidLocker::disconnect` respectively.

### Fixed

No fixes in this release.

### Breaking

- `FluidLocker`interface is updated since `FluidLocker::connectToPool` & `FluidLocker::disconnectFromPool` functions are renamed.
