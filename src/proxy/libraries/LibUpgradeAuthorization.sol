// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { UpgradeAuthorizationStorage } from "./UpgradeAuthorizationStorage.sol";
import { IImplementationWhitelist } from "../../interfaces/IImplementationWhitelist.sol";
import { IAdminFacet, AdminOperationType } from "../../interfaces/IAdminFacet.sol";
import { IGuardianFacet } from "../../interfaces/IGuardianFacet.sol";

/**
 * @title Lib Upgrade Authorization
 * @notice Library for validating upgrade authorization
 * @author Den Technologies Inc
 */
library LibUpgradeAuthorization {
    /**
     * @notice Error thrown when upgrade authorization fails
     */
    error UpgradeAuthorizationFailed(string reason);

    /**
     * @notice Error thrown when implementation is not whitelisted
     */
    error ImplementationNotWhitelisted(address implementation);

    /**
     * @notice Validates upgrade authorization with guardian, admin, and whitelist checks
     * @param newImplementation The new implementation address
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures from admin(s) authorizing this upgrade
     */
    function validateUpgradeAuthorization(
        address newImplementation,
        uint256 salt,
        bytes memory signatures
    )
        internal
    {
        UpgradeAuthorizationStorage.Layout storage upgradeAuthLayout = UpgradeAuthorizationStorage.layout();

        // 1. Enforce guardian approval
        IGuardianFacet(address(this)).enforceOnlyGuardian();

        // 2. Validate admin authorization
        bytes memory operationData = abi.encode(newImplementation);
        try IAdminFacet(address(this)).validateAdminAuthorization(
            AdminOperationType.Upgrade, operationData, salt, signatures
        ) {
            // Validation successful
        } catch Error(string memory reason) {
            revert UpgradeAuthorizationFailed(reason);
        } catch {
            revert UpgradeAuthorizationFailed("Admin validation failed");
        }

        // 3. Validate implementation against whitelist
        if (upgradeAuthLayout.whitelistAddress == address(0)) {
            revert UpgradeAuthorizationFailed("Whitelist address not set");
        }

        IImplementationWhitelist.ContractType contractType = upgradeAuthLayout.contractType == 0
            ? IImplementationWhitelist.ContractType.Account
            : IImplementationWhitelist.ContractType.Organization;

        if (
            !IImplementationWhitelist(upgradeAuthLayout.whitelistAddress).validateImplementation(
                contractType, newImplementation
            )
        ) {
            revert ImplementationNotWhitelisted(newImplementation);
        }
    }
}
