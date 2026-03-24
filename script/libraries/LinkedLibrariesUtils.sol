// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {LinkedLibraryInfo} from "script/libraries/Types.sol";

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

    /// @dev Validates that all libraries in the array are linked in the init code AND deployed
    /// @param initCode The bytecode to check for linked library addresses
    /// @param libraries Array of library info to validate (address and name)
    function validateLinkedLibrariesOrRevert(bytes memory initCode, LinkedLibraryInfo[] memory libraries)
        internal
        view
    {
        bool allValid = true;

        for (uint256 i = 0; i < libraries.length; ++i) {
            LinkedLibraryInfo memory lib = libraries[i];
            bool isLinked = isAddressInInitCode(initCode, lib.expectedAddress);
            bool isDeployed = Create2Utils.isContractDeployedAtAddress(lib.expectedAddress);

            // Case: Library is linked and deployed
            if (isLinked && isDeployed) {
                Logger.logPass(string.concat(lib.name, " linked and deployed"));
                continue;
            }

            // Case: Library is not linked
            if (!isLinked) {
                Logger.logFail(string.concat(lib.name, " NOT linked in bytecode"));
                Logger.logKeyValue("  Expected", lib.expectedAddress);
                allValid = false;
            }

            // Case: Library is not deployed
            if (!isDeployed) {
                Logger.logFail(string.concat(lib.name, " NOT deployed at expected address"));
                Logger.logKeyValue("  Expected", lib.expectedAddress);
                allValid = false;
            }
        }

        // Case: One or more libraries failed validation
        if (!allValid) {
            Logger.logEmptyLine();
            Logger.logWarn("WARNING: Some libraries are not linked or deployed!");
            Logger.logIndented("Ensure --libraries flag is used with correct addresses.");
            Logger.logEmptyLine();
            revert("Library validation failed. See logs above for details.");
        }
    }
}
