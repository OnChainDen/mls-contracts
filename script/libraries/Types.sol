// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title Types
 * @notice Type definitions for deployment scripts
 * @author Den Technologies Inc
 */

/// @dev Grouped addresses for deployed/computed platform libraries
struct PlatformLibraries {
    address policy;
    address admin;
    address initialization;
    address accountSignature;
}
