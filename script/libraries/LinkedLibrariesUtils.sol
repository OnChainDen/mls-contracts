// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {LibOrganizationAccountSignature} from "organization/libraries/LibOrganizationAccountSignature.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationInitialization} from "organization/libraries/LibOrganizationInitialization.sol";
import {LibOrganizationPolicy} from "organization/libraries/LibOrganizationPolicy.sol";
import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Create2Deployer} from "script/libraries/Create2Deployer.sol";
import {PlatformLibraries} from "script/libraries/Types.sol";

/**
 * @title LinkedLibrariesUtils
 * @notice Utility functions for computing and working with platform library addresses
 * @dev Provides a single source of truth for computing deterministic library addresses
 *      used across deployment scripts to avoid code duplication
 * @author Den Technologies Inc
 */
library LinkedLibrariesUtils {
    /// @dev Computes the deterministic addresses for all platform libraries
    /// @param factoryAddress Address of the CREATE2 factory used for address computation
    /// @return libs Struct containing computed library addresses
    function computePlatformLibraryAddresses(address factoryAddress)
        internal
        pure
        returns (PlatformLibraries memory libs)
    {
        libs.policy = Create2Deployer.computeAddress(
            factoryAddress, DeploymentConfig.LIB_ORG_POLICY_SALT, type(LibOrganizationPolicy).creationCode
        );
        libs.admin = Create2Deployer.computeAddress(
            factoryAddress, DeploymentConfig.LIB_ORG_ADMIN_SALT, type(LibOrganizationAdmin).creationCode
        );
        libs.initialization = Create2Deployer.computeAddress(
            factoryAddress, DeploymentConfig.LIB_ORG_INIT_SALT, type(LibOrganizationInitialization).creationCode
        );
        libs.accountSignature = Create2Deployer.computeAddress(
            factoryAddress,
            DeploymentConfig.LIB_ORG_ACCOUNT_SIG_SALT,
            type(LibOrganizationAccountSignature).creationCode
        );
    }

    /// @dev Checks if an address is in the creation code of a contract
    /// @param initCode The byte array to search in
    /// @param addr The address to search for
    /// @return True if the address is found in the creation code
    function isAddressInInitCode(bytes memory initCode, address addr) internal pure returns (bool) {
        // Case: the byte array is too short to contain the address
        if (initCode.length < 20) {
            return false;
        }

        // Convert the address to a 20-byte bytes array
        bytes20 addrBytes = bytes20(addr);

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
                if (initCode[i + j] != addrBytes[j]) {
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
