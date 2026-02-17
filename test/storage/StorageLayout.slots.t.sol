// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";

import {StorageLayoutSlots} from "test/helpers/storage/StorageLayoutSlots.sol";
import {StorageLayoutTestBase} from "test/helpers/storage/StorageLayoutTestBase.sol";

/**
 * @dev Storage Layout Slots Test
 *      Slot-level checks for ERC-7201 derivation correctness, uniqueness, format compliance,
 *      and collision-safety against ERC-1967/OpenZeppelin namespaces.
 */
contract StorageLayoutSlotsTest is StorageLayoutTestBase {
    /**
     * @dev Verifies organization admin slot derivation is correct.
     */
    function test_organizationAdminStorage_slotIsCorrect() public pure {
        assertEq(
            _projectSlotAt(StorageLayoutSlots.SLOT_INDEX_ORGANIZATION_ADMIN),
            SlotDerivation.erc7201Slot(StorageLayoutSlots.NAMESPACE_ORGANIZATION_ADMIN),
            "LibOrganizationAdminStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.admin'"
        );
    }

    /**
     * @dev Verifies organization account factory slot derivation is correct.
     */
    function test_organizationAccountFactoryStorage_slotIsCorrect() public pure {
        assertEq(
            _projectSlotAt(StorageLayoutSlots.SLOT_INDEX_ORGANIZATION_ACCOUNT_FACTORY),
            SlotDerivation.erc7201Slot(StorageLayoutSlots.NAMESPACE_ORGANIZATION_ACCOUNT_FACTORY),
            "LibOrganizationAccountFactoryStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.account-factory'"
        );
    }

    /**
     * @dev Verifies organization deployer slot derivation is correct.
     */
    function test_organizationDeployerAddressStorage_slotIsCorrect() public pure {
        assertEq(
            _projectSlotAt(StorageLayoutSlots.SLOT_INDEX_ORGANIZATION_DEPLOYER),
            SlotDerivation.erc7201Slot(StorageLayoutSlots.NAMESPACE_ORGANIZATION_DEPLOYER),
            "LibOrganizationDeployerAddressStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.deployer'"
        );
    }

    /**
     * @dev Verifies organization groups slot derivation is correct.
     */
    function test_organizationGroupsStorage_slotIsCorrect() public pure {
        assertEq(
            _projectSlotAt(StorageLayoutSlots.SLOT_INDEX_ORGANIZATION_GROUPS),
            SlotDerivation.erc7201Slot(StorageLayoutSlots.NAMESPACE_ORGANIZATION_GROUPS),
            "LibOrganizationGroupsStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.groups'"
        );
    }

    /**
     * @dev Verifies organization guardian slot derivation is correct.
     */
    function test_organizationGuardianStorage_slotIsCorrect() public pure {
        assertEq(
            _projectSlotAt(StorageLayoutSlots.SLOT_INDEX_ORGANIZATION_GUARDIAN),
            SlotDerivation.erc7201Slot(StorageLayoutSlots.NAMESPACE_ORGANIZATION_GUARDIAN),
            "LibOrganizationGuardianStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.guardian'"
        );
    }

    /**
     * @dev Verifies organization members slot derivation is correct.
     */
    function test_organizationMembersStorage_slotIsCorrect() public pure {
        assertEq(
            _projectSlotAt(StorageLayoutSlots.SLOT_INDEX_ORGANIZATION_MEMBERS),
            SlotDerivation.erc7201Slot(StorageLayoutSlots.NAMESPACE_ORGANIZATION_MEMBERS),
            "LibOrganizationMembersStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.members'"
        );
    }

    /**
     * @dev Verifies organization policy slot derivation is correct.
     */
    function test_organizationPolicyStorage_slotIsCorrect() public pure {
        assertEq(
            _projectSlotAt(StorageLayoutSlots.SLOT_INDEX_ORGANIZATION_POLICY),
            SlotDerivation.erc7201Slot(StorageLayoutSlots.NAMESPACE_ORGANIZATION_POLICY),
            "LibOrganizationPolicyStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.policy'"
        );
    }

    /**
     * @dev Verifies organization signatures slot derivation is correct.
     */
    function test_organizationSignaturesStorage_slotIsCorrect() public pure {
        assertEq(
            _projectSlotAt(StorageLayoutSlots.SLOT_INDEX_ORGANIZATION_SIGNATURES),
            SlotDerivation.erc7201Slot(StorageLayoutSlots.NAMESPACE_ORGANIZATION_SIGNATURES),
            "LibOrganizationSignaturesStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.signatures'"
        );
    }

    /**
     * @dev Verifies organization upgrade slot derivation is correct.
     */
    function test_organizationUpgradeStorage_slotIsCorrect() public pure {
        assertEq(
            _projectSlotAt(StorageLayoutSlots.SLOT_INDEX_ORGANIZATION_UPGRADE),
            SlotDerivation.erc7201Slot(StorageLayoutSlots.NAMESPACE_ORGANIZATION_UPGRADE),
            "LibOrganizationUpgradeStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.upgrade'"
        );
    }

    /**
     * @dev Verifies organization admin operation timelock slot derivation is correct.
     */
    function test_organizationAdminOperationTimelockStorage_slotIsCorrect() public pure {
        assertEq(
            _projectSlotAt(StorageLayoutSlots.SLOT_INDEX_ORGANIZATION_ADMIN_OPERATION_TIMELOCK),
            SlotDerivation.erc7201Slot(StorageLayoutSlots.NAMESPACE_ORGANIZATION_ADMIN_OPERATION_TIMELOCK),
            "LibOrganizationAdminOperationTimelockStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.admin-operation-timelock'"
        );
    }

    /**
     * @dev Verifies organization recovery slot derivation is correct.
     */
    function test_organizationRecoveryStorage_slotIsCorrect() public pure {
        assertEq(
            _projectSlotAt(StorageLayoutSlots.SLOT_INDEX_ORGANIZATION_RECOVERY),
            SlotDerivation.erc7201Slot(StorageLayoutSlots.NAMESPACE_ORGANIZATION_RECOVERY),
            "LibOrganizationRecoveryStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.recovery'"
        );
    }

    /**
     * @dev Verifies implementation whitelist slot derivation is correct.
     */
    function test_implementationWhitelistStorage_slotIsCorrect() public pure {
        assertEq(
            _projectSlotAt(StorageLayoutSlots.SLOT_INDEX_IMPLEMENTATION_WHITELIST),
            SlotDerivation.erc7201Slot(StorageLayoutSlots.NAMESPACE_IMPLEMENTATION_WHITELIST),
            "LibImplementationWhitelistStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.implementation-whitelist.main'"
        );
    }

    /**
     * @dev Verifies all project storage slots are unique.
     *      Collisions would cause storage corruption between independent storage libraries.
     */
    function test_allStorageSlots_areUnique() public pure {
        bytes32[] memory slots = _allProjectStorageSlots();

        for (uint256 i = 0; i < slots.length; i++) {
            for (uint256 j = i + 1; j < slots.length; j++) {
                assertTrue(
                    slots[i] != slots[j],
                    string.concat(
                        "Storage slot collision detected between index ", vm.toString(i), " and ", vm.toString(j)
                    )
                );
            }
        }
    }

    /**
     * @dev Verifies all project storage slots end with 0x00 as required by ERC-7201.
     */
    function test_allStorageSlots_endWithZeroByte() public pure {
        bytes32[] memory slots = _allProjectStorageSlots();

        for (uint256 i = 0; i < slots.length; i++) {
            assertEq(
                uint8(uint256(slots[i]) & 0xff),
                0,
                string.concat("Storage slot at index ", vm.toString(i), " does not end with 0x00 (ERC-7201 violation)")
            );
        }
    }

    /**
     * @dev Verifies no ERC-7201 storage slot collides with ERC-1967 implementation slot.
     */
    function test_namespaceSlots_doNotCollideWithERC1967ImplementationSlot() public pure {
        _assertNoCollisionWithSlot(_allProjectStorageSlots(), ERC1967_IMPLEMENTATION_SLOT, "ERC-1967 implementation");
    }

    /**
     * @dev Verifies no ERC-7201 storage slot collides with ERC-1967 admin slot.
     */
    function test_namespaceSlots_doNotCollideWithERC1967AdminSlot() public pure {
        _assertNoCollisionWithSlot(_allProjectStorageSlots(), ERC1967_ADMIN_SLOT, "ERC-1967 admin");
    }

    /**
     * @dev Verifies no ERC-7201 storage slot collides with ERC-1967 beacon slot.
     */
    function test_namespaceSlots_doNotCollideWithERC1967BeaconSlot() public pure {
        _assertNoCollisionWithSlot(_allProjectStorageSlots(), ERC1967_BEACON_SLOT, "ERC-1967 beacon");
    }

    /**
     * @dev Verifies no project namespace collides with OZ Initializable namespace.
     */
    function test_namespaceSlots_doNotCollideWithOpenZeppelinInitializableNamespace() public pure {
        bytes32 initializableSlot = SlotDerivation.erc7201Slot(OZ_INITIALIZABLE_NAMESPACE);
        _assertNoCollisionWithSlot(_allProjectStorageSlots(), initializableSlot, "openzeppelin.storage.Initializable");
    }

    /**
     * @dev Verifies no project namespace collides with OZ OwnableUpgradeable namespace.
     */
    function test_namespaceSlots_doNotCollideWithOpenZeppelinOwnableUpgradeableNamespace() public pure {
        bytes32 ownableSlot = SlotDerivation.erc7201Slot(OZ_OWNABLE_UPGRADEABLE_NAMESPACE);
        _assertNoCollisionWithSlot(_allProjectStorageSlots(), ownableSlot, "openzeppelin.storage.Ownable");
    }

    /**
     * @dev Returns the project storage slot at `slotIndex`.
     * @param slotIndex Index in the canonical storage-slot ordering.
     */
    function _projectSlotAt(uint256 slotIndex) internal pure returns (bytes32) {
        return StorageLayoutSlots.allProjectStorageSlots()[slotIndex];
    }
}
