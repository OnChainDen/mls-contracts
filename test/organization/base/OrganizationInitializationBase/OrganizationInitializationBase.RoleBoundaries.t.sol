// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganization} from "interfaces/IOrganization.sol";
import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Cross-file tests for initialized role-boundary isolation between guardian and recovery roles.
 */
contract OrganizationInitializationBaseRoleBoundariesTest is InitializationSuiteBase {
    /// @dev Verifies guardian, tx-recovery, and guardian-recovery entrypoints remain disjoint after initialization.
    function test_initializedRoleChecksRemainDisjointAcrossGuardianAndRecoveryEntrypoints() public {
        // Setup: deploy one initialized organization whose guardian, guardian-recovery, and tx-recovery roles are all
        // distinct addresses.
        IOrganization organization =
            IOrganization(_deployOrganization(bytes32(uint256(14_401)), _defaultInitializationParams()));

        // Call: attempt each privileged subsystem entrypoint from the wrong privileged role.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationTxRecovery.UnauthorizedTxRecoveryAddress.selector, GUARDIAN, TX_RECOVERY
            )
        );
        vm.prank(GUARDIAN);
        IOrganizationTxRecovery(address(organization)).initiateEnableTransactionAndERC1271Recovery();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector, GUARDIAN, GUARDIAN_RECOVERY
            )
        );
        vm.prank(GUARDIAN);
        IOrganizationGuardianRecovery(address(organization)).initiateRecoveryGuardianUpdate(MEMBER_1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector,
                TX_RECOVERY,
                GUARDIAN_RECOVERY
            )
        );
        vm.prank(TX_RECOVERY);
        IOrganizationGuardianRecovery(address(organization)).cancelRecoveryGuardianUpdate();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationTxRecovery.UnauthorizedTxRecoveryAddress.selector, GUARDIAN_RECOVERY, TX_RECOVERY
            )
        );
        vm.prank(GUARDIAN_RECOVERY);
        IOrganizationTxRecovery(address(organization)).disableTransactionAndERC1271Recovery();

        // Verify: rejected cross-role calls leave each configured role binding unchanged.
        TxRecoveryState memory txRecovery = IOrganizationTxRecovery(address(organization)).getTxRecoveryState();
        GuardianRecoveryState memory guardianRecovery =
            IOrganizationGuardianRecovery(address(organization)).getGuardianRecoveryState();
        assertEq(organization.guardian(), GUARDIAN, "guardian binding should remain unchanged");
        assertEq(txRecovery.recoveryAddress, TX_RECOVERY, "tx-recovery binding should remain unchanged");
        assertEq(
            guardianRecovery.recoveryAddress, GUARDIAN_RECOVERY, "guardian-recovery binding should remain unchanged"
        );
    }

    /// @dev Verifies recovery roles cannot call guardian-only entrypoints unless they are also the current guardian.
    function test_recoveryRolesCannotCallGuardianOnlyEntrypointsUnlessAlsoGuardian() public {
        // Setup: deploy one initialized organization and build an auth struct whose contents are irrelevant because
        // role checks should fail before admin-auth validation.
        IOrganization organization =
            IOrganization(_deployOrganization(bytes32(uint256(14_402)), _defaultInitializationParams()));
        AdminAuthParams memory emptyAuth = _emptyAdminAuth();

        // Call: attempt guardian-only normal-flow entrypoints from both recovery roles.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, TX_RECOVERY, GUARDIAN)
        );
        vm.prank(TX_RECOVERY);
        IOrganizationGuardian(address(organization)).initiateGuardianUpdate(MEMBER_2, emptyAuth);

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, GUARDIAN_RECOVERY, GUARDIAN)
        );
        vm.prank(GUARDIAN_RECOVERY);
        IOrganizationGuardian(address(organization)).cancelGuardianUpdate(emptyAuth);

        // Verify: no guardian-only pending state is created and the live guardian remains unchanged.
        assertEq(organization.guardian(), GUARDIAN, "guardian should remain unchanged");
        assertEq(
            IOrganizationGuardian(address(organization)).pendingGuardian(),
            address(0),
            "pending guardian should remain clear"
        );
        assertEq(
            IOrganizationGuardian(address(organization)).pendingGuardianUpdateTimestamp(),
            0,
            "pending guardian timestamp should remain clear"
        );
        assertFalse(
            IOrganizationGuardian(address(organization)).isGuardianUpdateReadyForAcceptance(),
            "ready flag should remain false"
        );
    }

    /// @dev Builds a minimal admin-auth struct for entrypoints whose role guards should fail before auth validation.
    /// @return auth Zero-signature auth payload used only to satisfy calldata shape requirements.
    function _emptyAdminAuth() internal view returns (AdminAuthParams memory auth) {
        auth = AdminAuthParams({salt: 0, expirationTimestamp: block.timestamp + 1 days, signatures: bytes("")});
    }
}
