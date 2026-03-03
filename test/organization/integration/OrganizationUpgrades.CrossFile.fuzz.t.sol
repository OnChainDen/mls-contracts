// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationUpgradesCrossFileSuiteBase
} from "test/organization/integration/OrganizationUpgradesCrossFileSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {ContractType, OperationType} from "types/CommonTypes.sol";

/**
 * @dev Cross-file fuzz tests for organization/account upgrade security flows.
 */
contract OrganizationUpgradesCrossFileFuzzTest is OrganizationUpgradesCrossFileSuiteBase {
    /// @dev Verifies fuzzed non-whitelisted Organization upgrade targets are always rejected.
    function test_UPG_FZ_1_fuzz_nonWhitelistedOrganizationTargetsAreRejected(address candidate) public {
        // Setup: configure valid guardian/admin auth for arbitrary candidate without whitelisting it.
        _setSingleAdminThresholdOne();
        vm.assume(!whitelist.isImplementationWhitelisted(ContractType.Organization, candidate));

        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: candidate,
            salt: uint256(uint160(candidate)) + 141_020,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: candidate is rejected before any implementation pointer change.
        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: attempt wrapper upgrade to non-whitelisted candidate.
        organizationProxy.upgradeToAndCallWithAuthorization(candidate, bytes(""), auth);
    }

    /// @dev Verifies fuzzed non-whitelisted Account implementation targets are always rejected.
    function test_UPG_FZ_2_fuzz_nonWhitelistedAccountTargetsAreRejected(address candidate) public {
        // Setup: configure valid admin auth for arbitrary account implementation candidate without whitelisting.
        _setSingleAdminThresholdOne();
        vm.assume(!whitelist.isImplementationWhitelisted(ContractType.Account, candidate));

        (AdminAuthParams memory auth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(candidate),
            isApproval: true,
            salt: uint256(uint160(candidate)) + 141_021,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: account implementation update rejects non-whitelisted candidates.
        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: attempt account implementation update with non-whitelisted target.
        organizationProxy.setAccountImplementation(candidate, auth);
    }

    /// @dev Verifies fuzzed successful upgrade sequences preserve core state across repeated upgrades.
    function test_UPG_FZ_3_fuzz_successfulUpgradeSequences_preserveState(uint8 rounds) public {
        // Setup: bound rounds and seed stable core state to verify persistence.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        _setOrganizationImplementationWhitelisted(address(implementationV3), true);
        rounds = uint8(bound(uint256(rounds), 1, 8));

        organizationProxy.setGroupStatus(77, true);
        organizationProxy.setPoliciesRoot(bytes32(uint256(0xAA55)));

        // Call: perform a bounded sequence of valid upgrades between V2 and V3.
        for (uint256 i = 0; i < rounds; ++i) {
            address target = i % 2 == 0 ? address(implementationV2) : address(implementationV3);
            (AdminAuthParams memory auth,) = _buildAuthForOrganization({
                organization: address(organizationProxy),
                operationType: OperationType.Upgrade,
                operationData: _encodeOperationDataForUpgrade(target),
                isApproval: true,
                salt: 141_100 + i,
                expirationTimestamp: block.timestamp + 1 hours,
                privateKeys: buildUint256Array(ADMIN_PK_1)
            });

            vm.prank(GUARDIAN);
            organizationProxy.upgradeToAndCallWithAuthorization(target, bytes(""), auth);
        }

        // Verify: expected core state remains consistent after repeated successful upgrades.
        assertTrue(organizationProxy.getGroupStatus(77), "group state changed");
        assertEq(organizationProxy.getPoliciesRoot(), bytes32(uint256(0xAA55)), "policies root changed");
    }

    /// @dev Verifies fuzzed malformed migration calldata reverts atomically with no partial implementation change.
    function test_UPG_FZ_4_fuzz_malformedMigrationCalldata_revertsAtomically(bytes calldata malformedData) public {
        // Setup: whitelist V2 target and fuzz malformed migration payload.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        vm.assume(malformedData.length > 0);

        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            migrationData: malformedData,
            salt: 141_200,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        address implementationBefore = _readProxyImplementation(address(organizationProxy));

        // Verify: malformed data path reverts and implementation pointer remains unchanged.
        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: execute upgrade with malformed migration payload.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), malformedData, auth);

        assertEq(_readProxyImplementation(address(organizationProxy)), implementationBefore, "impl changed on revert");
    }

    /// @dev Verifies fuzzed nested migration payloads cannot trigger an unauthorized second upgrade.
    function test_UPG_FZ_5_fuzz_nestedUpgradeFromRandomPayload_reverts(bytes memory randomData) public {
        // Setup: whitelist both V2 and V3 and craft migration payload that attempts nested second upgrade.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        _setOrganizationImplementationWhitelisted(address(implementationV3), true);
        bytes memory nestedData =
            abi.encodeCall(implementationV2.migrationNestedUpgrade, (address(implementationV3), randomData));
        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: address(implementationV2),
            migrationData: nestedData,
            salt: 141_201,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: nested second-upgrade attempts are rejected.
        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: execute first upgrade with nested-upgrade migration payload.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), nestedData, auth);
    }
}
