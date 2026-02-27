// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationAccountFactoryStorage
} from "organization/libraries/storage/LibOrganizationAccountFactoryStorage.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";

/**
 * @dev Shared account-factory state harness surface.
 *      Extends admin/auth helpers with account-factory and upgrade storage setters/getters.
 */
contract OrganizationAccountFactoryStateHarness is OrganizationAdminStateHarness {
    /**
     * @dev Sets deployed-account status in account-factory storage.
     */
    function setDeployedAccount(address account, bool isDeployed) external {
        LibOrganizationAccountFactoryStorage.layout().deployedAccounts[account] = isDeployed;
    }

    /**
     * @dev Reads deployed-account status in account-factory storage.
     */
    function isDeployedAccount(address account) external view returns (bool) {
        return LibOrganizationAccountFactoryStorage.layout().deployedAccounts[account];
    }

    /**
     * @dev Sets account implementation storage directly.
     */
    function setAccountImplementationStorage(address accountImplementation) external {
        LibOrganizationAccountFactoryStorage.layout().accountImplementation = accountImplementation;
    }

    /**
     * @dev Reads account implementation storage directly.
     */
    function getAccountImplementationStorage() external view returns (address) {
        return LibOrganizationAccountFactoryStorage.layout().accountImplementation;
    }

    /**
     * @dev Sets organization-upgrade namespace values.
     */
    function setUpgradeState(address whitelistAddress, bool isUpgradeAuthorized) external {
        LibOrganizationUpgradeStorage.layout().whitelistAddress = whitelistAddress;
        LibOrganizationUpgradeStorage.layout().isUpgradeAuthorized = isUpgradeAuthorized;
    }

    /**
     * @dev Reads organization-upgrade namespace values.
     */
    function getUpgradeState() external view returns (address whitelistAddress, bool isUpgradeAuthorized) {
        whitelistAddress = LibOrganizationUpgradeStorage.layout().whitelistAddress;
        isUpgradeAuthorized = LibOrganizationUpgradeStorage.layout().isUpgradeAuthorized;
    }

    /**
     * @dev Encodes operation data exactly as `OrganizationAccountFactoryBase.deployAccount`.
     */
    function encodeDeployAccountOperationData(bytes32 create2Salt) external pure returns (bytes memory) {
        return abi.encode(create2Salt);
    }

    /**
     * @dev Encodes operation data exactly as `OrganizationAccountFactoryBase.setAccountImplementation`.
     */
    function encodeSetAccountImplementationOperationData(address newImplementation)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(newImplementation);
    }
}
