// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title LinkedLibrariesUtils
 * @notice Utility functions for working with linked library bytecode
 * @author Den Technologies Inc
 */
library LinkedLibrariesUtils {
    /// @dev Checks if an address is in the creation code of a contract
    /// @param initCode The byte array to search in
    /// @param targetAddress The address to search for
    /// @return True if the address is found in the creation code
    function isAddressInInitCode(bytes memory initCode, address targetAddress) internal pure returns (bool) {
        // Case: the byte array is too short to contain the address
        if (initCode.length < 20) {
            return false;
        }

        // Convert the address to a 20-byte bytes array
        bytes20 targetAddressBytes = bytes20(targetAddress);

        // Calculate the maximum index we need to iterate to
        // This is 20 bytes less than the length of the byte array, because each iteration of the loop
        // will check the next 20 bytes of `initCode` to see if they match `addrBytes`
        uint256 maxIndex = initCode.length - 20;

        // Iterate over each byte in `initCode` one by one, checking the next 20 bytes of `initCode` to
        // see if they match `addrBytes`
        for (uint256 i = 0; i <= maxIndex; ++i) {
            bool found = true;

            // Iterate through the next 20 bytes of `initCode` to see if each of the next 20 bytes match `addrBytes`
            for (uint256 j = 0; j < 20 && found; ++j) {
                // Case: one of the next 20 bytes of `initCode` does not match `addrBytes`
                if (initCode[i + j] != targetAddressBytes[j]) {
                    found = false;
                    break;
                }
            }

            // Case: we found the address in the byte array
            if (found) {
                return true;
            }
        }

        // Case: we didn't find the address in the byte array
        return false;
    }
}
