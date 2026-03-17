// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganization} from "interfaces/IOrganization.sol";
import {
    IUUPSOrgEntrypoints,
    OrganizationUpgradesCrossFileSuiteBase
} from "test/organization/integration/OrganizationUpgradesCrossFileSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {ContractType, OperationType} from "types/CommonTypes.sol";

/**
 * @dev Cross-file fuzz tests for organization/account upgrade security flows.
 */
contract OrganizationUpgradesCrossFileFuzzTest is OrganizationUpgradesCrossFileSuiteBase {
    /// @dev Verifies fuzzed non-whitelisted Organization upgrade targets are always rejected.
    function testFuzz_UPG_FZ_1__IWC_FUZZ_1__FOI_UPGRADE_134__FIWI_ENFORCE_142_fuzz_nonWhitelistedOrganizationTargetsAreRejected(address candidate)
        public
    {
        // Setup: configure valid guardian/admin auth for an arbitrary non-zero candidate without whitelisting it.
        _setSingleAdminThresholdOne();
        vm.assume(candidate != address(0));
        vm.assume(!whitelist.isImplementationWhitelisted(ContractType.Organization, candidate));

        (AdminAuthParams memory auth,) = _buildUpgradeAuth({
            newImplementation: candidate,
            salt: uint256(uint160(candidate)) + 141_020,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: candidate is rejected before any implementation pointer change.
        vm.expectRevert(
            abi.encodeWithSelector(IImplementationWhitelist.ImplementationNotWhitelisted.selector, candidate)
        );
        vm.prank(GUARDIAN);
        // Call: attempt wrapper upgrade to non-whitelisted candidate.
        organizationProxy.upgradeToAndCallWithAuthorization(candidate, bytes(""), auth);
    }

    /// @dev Verifies fuzzed non-whitelisted Account implementation targets are always rejected.
    function testFuzz_UPG_FZ_2__IWC_FUZZ_1__FIWI_ENFORCE_142_fuzz_nonWhitelistedAccountTargetsAreRejected(address candidate)
        public
    {
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
        vm.expectRevert(
            abi.encodeWithSelector(IImplementationWhitelist.ImplementationNotWhitelisted.selector, candidate)
        );
        vm.prank(GUARDIAN);
        // Call: attempt account implementation update with non-whitelisted target.
        organizationProxy.setAccountImplementation(candidate, auth);
    }

    /// @dev Verifies fuzzed successful upgrade sequences preserve core state across repeated upgrades.
    function testFuzz_UPG_FZ_3__IWC_FUZZ_4__FOI_UPGRADE_134_fuzz_successfulUpgradeSequences_preserveState(uint8 rounds)
        public
    {
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

        // Call: execute upgrade with malformed migration payload.
        vm.prank(GUARDIAN);
        (bool success,) = address(organizationProxy)
            .call(
                abi.encodeCall(
                    IOrganization.upgradeToAndCallWithAuthorization, (address(implementationV2), malformedData, auth)
                )
            );

        // Verify: malformed data path reverts and implementation pointer remains unchanged.
        assertFalse(success, "malformed migration payload should revert");
        assertEq(_readProxyImplementation(address(organizationProxy)), implementationBefore, "impl changed on revert");
    }

    /// @dev Verifies fuzzed nested migration payloads cannot trigger an unauthorized second upgrade.
    /// SAG-FUZ-7
    function testFuzz_UPG_FZ_5__IWC_FUZZ_5__FOI_UPGRADE_137__SAG_FUZ_7_fuzz_nestedUpgradeFromRandomPayload_reverts(bytes memory randomData)
        public
    {
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
        vm.expectRevert(IOrganization.UnauthorizedUpgrade.selector);
        vm.prank(GUARDIAN);
        // Call: execute first upgrade with nested-upgrade migration payload.
        organizationProxy.upgradeToAndCallWithAuthorization(address(implementationV2), nestedData, auth);
    }

    /// @dev Verifies direct `upgradeToAndCall` calls always revert `UnauthorizedUpgrade` without wrapper auth.
    /// @param useGuardianCaller Fuzzed switch selecting guardian vs non-guardian caller for the direct call.
    /// @param randomData Fuzzed migration calldata passed into the direct UUPS entrypoint.
    function testFuzz_FOI_AUTH_135_directUpgradeToAndCallWithoutWrapperAuthAlwaysReverts(
        bool useGuardianCaller,
        bytes memory randomData
    ) public {
        // Setup: choose a caller for the direct upgrade path without seeding wrapper authorization state.
        address caller = useGuardianCaller ? GUARDIAN : NON_GUARDIAN;

        // Call: invoke the raw UUPS upgrade entrypoint directly, expecting `UnauthorizedUpgrade`.
        vm.expectRevert(IOrganization.UnauthorizedUpgrade.selector);
        vm.prank(caller);
        IUUPSOrgEntrypoints(address(organizationProxy)).upgradeToAndCall(address(implementationV2), randomData);

        // Verify: bypassing the wrapper should never authorize a direct upgrade call.
    }

    /// @dev Verifies the authorized-upgrade flag stays cleared before and after a successful wrapper-driven upgrade.
    /// @param useV3Target Fuzzed switch selecting which whitelisted upgrade target to use.
    /// @param saltSeed Fuzzed entropy used to derive the admin-auth salt.
    function testFuzz_FOI_FLAG_136_authorizedUpgradeFlagIsFalseOutsideWrapperExecution(
        bool useV3Target,
        uint256 saltSeed
    ) public {
        // Setup: whitelist the candidate targets and confirm the auth flag starts cleared.
        _setSingleAdminThresholdOne();
        _setOrganizationImplementationWhitelisted(address(implementationV2), true);
        _setOrganizationImplementationWhitelisted(address(implementationV3), true);
        address target = useV3Target ? address(implementationV3) : address(implementationV2);
        (, address authorizedBefore) = organizationProxy.getUpgradeState();
        assertEq(authorizedBefore, address(0), "authorized-upgrade flag should start cleared");

        (AdminAuthParams memory auth,) = _buildAuthForOrganization({
            organization: address(organizationProxy),
            operationType: OperationType.Upgrade,
            operationData: _encodeOperationDataForUpgrade(target),
            isApproval: true,
            salt: uint256(keccak256(abi.encode(saltSeed, target))),
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: execute one successful authorized upgrade through the wrapper.
        vm.prank(GUARDIAN);
        organizationProxy.upgradeToAndCallWithAuthorization(target, bytes(""), auth);

        // Verify: once wrapper execution completes, the auth flag should be cleared again.
        (, address authorizedAfter) = organizationProxy.getUpgradeState();
        assertEq(authorizedAfter, address(0), "authorized-upgrade flag should be false outside active execution");
    }
}
