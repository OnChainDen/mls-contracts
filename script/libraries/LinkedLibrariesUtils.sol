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
}
