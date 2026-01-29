// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity >=0.7.0 <0.9.0;

/**
 * @title Types
 * @notice Type definitions for deployment scripts
 * @author Den Technologies Inc
 */

/// @dev Grouped addresses for deployed/computed platform libraries
struct PlatformLibraries {
    address policyAddress;
    address adminAddress;
    address initializationAddress;
    address accountSignatureAddress;
}

/// @dev Grouped addresses for independent libraries (no dependencies on other platform libraries)
struct IndependentLibraries {
    address policyAddress;
    address adminAddress;
}

/// @dev Grouped addresses for dependent libraries (depend on independent libraries being linked)
struct DependentLibraries {
    address initializationAddress;
    address accountSignatureAddress;
}

/// @dev Grouped addresses for deployed Safe infrastructure contracts
struct SafeInfrastructure {
    address singletonAddress;
    address proxyFactoryAddress;
    address fallbackHandlerAddress;
    address multiSendAddress;
    address multiSendCallOnlyAddress;
    address createCallAddress;
    address simulateTxAccessorAddress;
}

/// @dev Info for validating a linked library
struct LinkedLibraryInfo {
    address expectedAddress;
    string name;
}
