// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title ArrayUtils
 * @notice Helper library for array operations in deployment scripts
 * @author Den Technologies Inc
 */
library ArrayUtils {
    /// @dev Compares two address arrays for equality via hash comparison
    /// @param a First address array
    /// @param b Second address array
    /// @return True if both arrays have the same length and elements in the same order
    function equal(address[] memory a, address[] memory b) internal pure returns (bool) {
        return keccak256(abi.encode(a)) == keccak256(abi.encode(b));
    }
}
