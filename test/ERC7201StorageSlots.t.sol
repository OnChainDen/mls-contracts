// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {Test} from "forge-std/Test.sol";

// Organization storage libraries
import {
    LibOrganizationAccountFactoryStorage
} from "organization/libraries/storage/LibOrganizationAccountFactoryStorage.sol";
import {LibOrganizationAdminStorage} from "organization/libraries/storage/LibOrganizationAdminStorage.sol";
import {
    LibOrganizationDeployerAddressStorage
} from "organization/libraries/storage/LibOrganizationDeployerAddressStorage.sol";
import {LibOrganizationGroupsStorage} from "organization/libraries/storage/LibOrganizationGroupsStorage.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationMembersStorage} from "organization/libraries/storage/LibOrganizationMembersStorage.sol";
import {LibOrganizationPolicyStorage} from "organization/libraries/storage/LibOrganizationPolicyStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {
    LibOrganizationSecureTimelockStorage
} from "organization/libraries/storage/LibOrganizationSecureTimelockStorage.sol";
import {LibOrganizationSignaturesStorage} from "organization/libraries/storage/LibOrganizationSignaturesStorage.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";

// Implementation whitelist storage libraries
import {
    LibImplementationWhitelistStorage
} from "implementation-whitelist/libraries/storage/LibImplementationWhitelistStorage.sol";

/**
 * @title ERC7201 Storage Slots Test
 * @notice Tests to verify ERC-7201 storage slots are correctly computed
 * @dev These tests ensure:
 *      1. Each storage slot matches the ERC-7201 formula
 *      2. All storage slots are unique (no collisions)
 *      3. Storage slots end with 0x00 (required by ERC-7201 for struct alignment)
 *
 *      Uses OpenZeppelin's SlotDerivation.erc7201Slot() to compute expected values.
 *
 * @author Den Technologies Inc
 */
contract ERC7201StorageSlotsTest is Test {
    // ============================================================
    // Organization Storage Slot Tests
    // ============================================================

    function test_organizationAdminStorage_slotIsCorrect() public pure {
        assertEq(
            LibOrganizationAdminStorage.STORAGE_LOCATION,
            SlotDerivation.erc7201Slot("den.mls-wallet.organization.admin"),
            "LibOrganizationAdminStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.admin'"
        );
    }

    function test_organizationAccountFactoryStorage_slotIsCorrect() public pure {
        assertEq(
            LibOrganizationAccountFactoryStorage.STORAGE_LOCATION,
            SlotDerivation.erc7201Slot("den.mls-wallet.organization.account-factory"),
            "LibOrganizationAccountFactoryStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.account-factory'"
        );
    }

    function test_organizationDeployerAddressStorage_slotIsCorrect() public pure {
        assertEq(
            LibOrganizationDeployerAddressStorage.STORAGE_LOCATION,
            SlotDerivation.erc7201Slot("den.mls-wallet.organization.deployer"),
            "LibOrganizationDeployerAddressStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.deployer'"
        );
    }

    function test_organizationGroupsStorage_slotIsCorrect() public pure {
        assertEq(
            LibOrganizationGroupsStorage.STORAGE_LOCATION,
            SlotDerivation.erc7201Slot("den.mls-wallet.organization.groups"),
            "LibOrganizationGroupsStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.groups'"
        );
    }

    function test_organizationGuardianStorage_slotIsCorrect() public pure {
        assertEq(
            LibOrganizationGuardianStorage.STORAGE_LOCATION,
            SlotDerivation.erc7201Slot("den.mls-wallet.organization.guardian"),
            "LibOrganizationGuardianStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.guardian'"
        );
    }

    function test_organizationMembersStorage_slotIsCorrect() public pure {
        assertEq(
            LibOrganizationMembersStorage.STORAGE_LOCATION,
            SlotDerivation.erc7201Slot("den.mls-wallet.organization.members"),
            "LibOrganizationMembersStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.members'"
        );
    }

    function test_organizationPolicyStorage_slotIsCorrect() public pure {
        assertEq(
            LibOrganizationPolicyStorage.STORAGE_LOCATION,
            SlotDerivation.erc7201Slot("den.mls-wallet.organization.policy"),
            "LibOrganizationPolicyStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.policy'"
        );
    }

    function test_organizationSignaturesStorage_slotIsCorrect() public pure {
        assertEq(
            LibOrganizationSignaturesStorage.STORAGE_LOCATION,
            SlotDerivation.erc7201Slot("den.mls-wallet.organization.signatures"),
            "LibOrganizationSignaturesStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.signatures'"
        );
    }

    function test_organizationUpgradeStorage_slotIsCorrect() public pure {
        assertEq(
            LibOrganizationUpgradeStorage.STORAGE_LOCATION,
            SlotDerivation.erc7201Slot("den.mls-wallet.organization.upgrade"),
            "LibOrganizationUpgradeStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.upgrade'"
        );
    }

    function test_organizationSecureTimelockStorage_slotIsCorrect() public pure {
        assertEq(
            LibOrganizationSecureTimelockStorage.STORAGE_LOCATION,
            SlotDerivation.erc7201Slot("den.mls-wallet.organization.secure-timelock"),
            "LibOrganizationSecureTimelockStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.secure-timelock'"
        );
    }

    function test_organizationRecoveryStorage_slotIsCorrect() public pure {
        assertEq(
            LibOrganizationRecoveryStorage.STORAGE_LOCATION,
            SlotDerivation.erc7201Slot("den.mls-wallet.organization.recovery"),
            "LibOrganizationRecoveryStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.organization.recovery'"
        );
    }

    // ============================================================
    // Implementation Whitelist Storage Slot Tests
    // ============================================================

    function test_implementationWhitelistStorage_slotIsCorrect() public pure {
        assertEq(
            LibImplementationWhitelistStorage.STORAGE_LOCATION,
            SlotDerivation.erc7201Slot("den.mls-wallet.implementation-whitelist.main"),
            "LibImplementationWhitelistStorage slot mismatch. Verify with: cast index-erc7201 'den.mls-wallet.implementation-whitelist.main'"
        );
    }

    // ============================================================
    // Storage Slot Uniqueness Tests
    // ============================================================

    /**
     * @notice Verifies all storage slots are unique to prevent collisions
     * @dev Collisions would cause storage corruption between different libraries
     */
    function test_allStorageSlots_areUnique() public pure {
        bytes32[] memory slots = new bytes32[](12);

        // Organization storage slots
        slots[0] = LibOrganizationAdminStorage.STORAGE_LOCATION;
        slots[1] = LibOrganizationAccountFactoryStorage.STORAGE_LOCATION;
        slots[2] = LibOrganizationDeployerAddressStorage.STORAGE_LOCATION;
        slots[3] = LibOrganizationGroupsStorage.STORAGE_LOCATION;
        slots[4] = LibOrganizationGuardianStorage.STORAGE_LOCATION;
        slots[5] = LibOrganizationMembersStorage.STORAGE_LOCATION;
        slots[6] = LibOrganizationPolicyStorage.STORAGE_LOCATION;
        slots[7] = LibOrganizationSignaturesStorage.STORAGE_LOCATION;
        slots[8] = LibOrganizationUpgradeStorage.STORAGE_LOCATION;
        slots[9] = LibOrganizationRecoveryStorage.STORAGE_LOCATION;
        slots[10] = LibOrganizationSecureTimelockStorage.STORAGE_LOCATION;

        // Implementation whitelist storage slots
        slots[11] = LibImplementationWhitelistStorage.STORAGE_LOCATION;

        // Check all pairs for uniqueness
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

    // ============================================================
    // ERC-7201 Format Compliance Tests
    // ============================================================

    /**
     * @notice Verifies all storage slots end with 0x00 as required by ERC-7201
     * @dev ERC-7201 requires the last byte to be 0x00 to ensure struct alignment
     */
    function test_allStorageSlots_endWithZeroByte() public pure {
        bytes32[] memory slots = new bytes32[](12);

        slots[0] = LibOrganizationAdminStorage.STORAGE_LOCATION;
        slots[1] = LibOrganizationAccountFactoryStorage.STORAGE_LOCATION;
        slots[2] = LibOrganizationDeployerAddressStorage.STORAGE_LOCATION;
        slots[3] = LibOrganizationGroupsStorage.STORAGE_LOCATION;
        slots[4] = LibOrganizationGuardianStorage.STORAGE_LOCATION;
        slots[5] = LibOrganizationMembersStorage.STORAGE_LOCATION;
        slots[6] = LibOrganizationPolicyStorage.STORAGE_LOCATION;
        slots[7] = LibOrganizationSignaturesStorage.STORAGE_LOCATION;
        slots[8] = LibOrganizationUpgradeStorage.STORAGE_LOCATION;
        slots[9] = LibOrganizationRecoveryStorage.STORAGE_LOCATION;
        slots[10] = LibOrganizationSecureTimelockStorage.STORAGE_LOCATION;
        slots[11] = LibImplementationWhitelistStorage.STORAGE_LOCATION;

        for (uint256 i = 0; i < slots.length; i++) {
            // Check that the last byte is 0x00
            assertEq(
                uint8(uint256(slots[i]) & 0xff),
                0,
                string.concat("Storage slot at index ", vm.toString(i), " does not end with 0x00 (ERC-7201 violation)")
            );
        }
    }
}
