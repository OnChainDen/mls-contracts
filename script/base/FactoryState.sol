// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity >=0.7.0 <0.9.0;

/**
 * @title FactoryState
 * @notice Storage for CREATE2 factory state used across deployment scripts
 * @dev This abstract contract provides state variables that are set by
 *      validateAndInitializeFactoryOrRevert() in BaseDeployScript and used
 *      throughout the deployment script hierarchy.
 *
 *      This contract uses a floating pragma (>=0.7.0 <0.9.0) to allow reuse by both
 *      platform scripts (0.8.33) and Safe deployment scripts (0.7.6).
 *
 * @author Den Technologies Inc
 */
abstract contract FactoryState {
    /// @dev The CREATE2 factory address (set by validateAndInitializeFactoryOrRevert)
    address internal _factoryAddress;

    /// @dev The factory key for TOML lookups (e.g., "arachnid", "den-prod", "den-nonprod")
    string internal _factoryName;

    /// @dev The human-readable factory name for logging (e.g., "Arachnid Deterministic Deployment Proxy")
    string internal _factoryDisplayName;
}
