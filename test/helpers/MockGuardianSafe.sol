// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @dev Minimal mock of a Safe-compatible guardian exposing `isModuleEnabled(address)`.
 */
contract MockGuardianSafe {
    mapping(address module => bool enabled) internal _enabledModules;

    /**
     * @dev Sets enabled state for a module address.
     */
    function setModuleEnabled(address module, bool enabled) external {
        _enabledModules[module] = enabled;
    }

    /**
     * @dev Safe-compatible module check.
     */
    function isModuleEnabled(address module) external view returns (bool) {
        return _enabledModules[module];
    }
}

/**
 * @dev Mock returning malformed (short) data for `isModuleEnabled(address)` staticcalls.
 */
contract MockGuardianSafeShortReturn {
    /**
     * @dev Returns a 1-byte payload regardless of calldata.
     */
    fallback() external payable {
        assembly {
            mstore(0x00, 0x01)
            return(0x00, 1)
        }
    }
}
