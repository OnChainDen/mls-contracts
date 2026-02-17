// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibImplementationWhitelistStorage
} from "implementation-whitelist/libraries/storage/LibImplementationWhitelistStorage.sol";
import {
    LibOrganizationAccountFactoryStorage
} from "organization/libraries/storage/LibOrganizationAccountFactoryStorage.sol";
import {
    LibOrganizationAdminOperationTimelockStorage
} from "organization/libraries/storage/LibOrganizationAdminOperationTimelockStorage.sol";
import {LibOrganizationAdminStorage} from "organization/libraries/storage/LibOrganizationAdminStorage.sol";
import {
    LibOrganizationDeployerAddressStorage
} from "organization/libraries/storage/LibOrganizationDeployerAddressStorage.sol";
import {LibOrganizationGroupsStorage} from "organization/libraries/storage/LibOrganizationGroupsStorage.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationMembersStorage} from "organization/libraries/storage/LibOrganizationMembersStorage.sol";
import {LibOrganizationPolicyStorage} from "organization/libraries/storage/LibOrganizationPolicyStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {LibOrganizationSignaturesStorage} from "organization/libraries/storage/LibOrganizationSignaturesStorage.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";

/**
 * @dev Storage Layout Slots
 *      Canonical storage slots and namespaces used by storage layout tests.
 */
library StorageLayoutSlots {
    /// @dev Slot index for organization account-factory namespace.
    uint256 internal constant SLOT_INDEX_ORGANIZATION_ACCOUNT_FACTORY = 0;

    /// @dev Slot index for organization admin-operation-timelock namespace.
    uint256 internal constant SLOT_INDEX_ORGANIZATION_ADMIN_OPERATION_TIMELOCK = 1;

    /// @dev Slot index for organization admin namespace.
    uint256 internal constant SLOT_INDEX_ORGANIZATION_ADMIN = 2;

    /// @dev Slot index for organization deployer namespace.
    uint256 internal constant SLOT_INDEX_ORGANIZATION_DEPLOYER = 3;

    /// @dev Slot index for organization groups namespace.
    uint256 internal constant SLOT_INDEX_ORGANIZATION_GROUPS = 4;

    /// @dev Slot index for organization guardian namespace.
    uint256 internal constant SLOT_INDEX_ORGANIZATION_GUARDIAN = 5;

    /// @dev Slot index for organization members namespace.
    uint256 internal constant SLOT_INDEX_ORGANIZATION_MEMBERS = 6;

    /// @dev Slot index for organization policy namespace.
    uint256 internal constant SLOT_INDEX_ORGANIZATION_POLICY = 7;

    /// @dev Slot index for organization recovery namespace.
    uint256 internal constant SLOT_INDEX_ORGANIZATION_RECOVERY = 8;

    /// @dev Slot index for organization signatures namespace.
    uint256 internal constant SLOT_INDEX_ORGANIZATION_SIGNATURES = 9;

    /// @dev Slot index for organization upgrade namespace.
    uint256 internal constant SLOT_INDEX_ORGANIZATION_UPGRADE = 10;

    /// @dev Slot index for implementation-whitelist namespace.
    uint256 internal constant SLOT_INDEX_IMPLEMENTATION_WHITELIST = 11;

    /// @dev Organization admin namespace.
    string internal constant NAMESPACE_ORGANIZATION_ADMIN = "den.mls-wallet.organization.admin";

    /// @dev Organization account factory namespace.
    string internal constant NAMESPACE_ORGANIZATION_ACCOUNT_FACTORY = "den.mls-wallet.organization.account-factory";

    /// @dev Organization deployer namespace.
    string internal constant NAMESPACE_ORGANIZATION_DEPLOYER = "den.mls-wallet.organization.deployer";

    /// @dev Organization groups namespace.
    string internal constant NAMESPACE_ORGANIZATION_GROUPS = "den.mls-wallet.organization.groups";

    /// @dev Organization guardian namespace.
    string internal constant NAMESPACE_ORGANIZATION_GUARDIAN = "den.mls-wallet.organization.guardian";

    /// @dev Organization members namespace.
    string internal constant NAMESPACE_ORGANIZATION_MEMBERS = "den.mls-wallet.organization.members";

    /// @dev Organization policy namespace.
    string internal constant NAMESPACE_ORGANIZATION_POLICY = "den.mls-wallet.organization.policy";

    /// @dev Organization signatures namespace.
    string internal constant NAMESPACE_ORGANIZATION_SIGNATURES = "den.mls-wallet.organization.signatures";

    /// @dev Organization upgrade namespace.
    string internal constant NAMESPACE_ORGANIZATION_UPGRADE = "den.mls-wallet.organization.upgrade";

    /// @dev Organization recovery namespace.
    string internal constant NAMESPACE_ORGANIZATION_RECOVERY = "den.mls-wallet.organization.recovery";

    /// @dev Organization admin-operation-timelock namespace.
    string internal constant NAMESPACE_ORGANIZATION_ADMIN_OPERATION_TIMELOCK =
        "den.mls-wallet.organization.admin-operation-timelock";

    /// @dev Implementation whitelist namespace.
    string internal constant NAMESPACE_IMPLEMENTATION_WHITELIST = "den.mls-wallet.implementation-whitelist.main";

    /**
     * @dev Returns all project ERC-7201 storage slots covered by the storage layout plan.
     */
    function allProjectStorageSlots() internal pure returns (bytes32[] memory slots) {
        slots = new bytes32[](12);

        slots[0] = LibOrganizationAccountFactoryStorage.STORAGE_LOCATION;
        slots[1] = LibOrganizationAdminOperationTimelockStorage.STORAGE_LOCATION;
        slots[2] = LibOrganizationAdminStorage.STORAGE_LOCATION;
        slots[3] = LibOrganizationDeployerAddressStorage.STORAGE_LOCATION;
        slots[4] = LibOrganizationGroupsStorage.STORAGE_LOCATION;
        slots[5] = LibOrganizationGuardianStorage.STORAGE_LOCATION;
        slots[6] = LibOrganizationMembersStorage.STORAGE_LOCATION;
        slots[7] = LibOrganizationPolicyStorage.STORAGE_LOCATION;
        slots[8] = LibOrganizationRecoveryStorage.STORAGE_LOCATION;
        slots[9] = LibOrganizationSignaturesStorage.STORAGE_LOCATION;
        slots[10] = LibOrganizationUpgradeStorage.STORAGE_LOCATION;
        slots[11] = LibImplementationWhitelistStorage.STORAGE_LOCATION;
    }
}
