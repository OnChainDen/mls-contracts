// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {OrganizationModifiersHarness} from "test/organization/common/OrganizationModifiersHarness.sol";

/**
 * @dev Gap-closing tests for `OrganizationModifiers` access-control behavior.
 */
contract OrganizationModifiersTest is Test {
    OrganizationModifiersHarness internal harness;

    address internal constant GUARDIAN = address(0xA101);
    address internal constant DEPLOYER = address(0xA102);
    address internal constant TX_RECOVERY = address(0xA103);
    address internal constant GUARDIAN_RECOVERY = address(0xA104);
    address internal constant PENDING_GUARDIAN = address(0xA105);
    address internal constant RECOVERY_PENDING_GUARDIAN = address(0xA106);
    address internal constant OTHER = address(0xA107);

    /**
     * @dev Deploys the modifier harness and seeds distinct default role holders.
     */
    function setUp() public {
        harness = new OrganizationModifiersHarness();
        _setDistinctRoles();
    }

    /**
     * @dev Verifies `onlyGuardian` admits the guardian and encodes exact revert parameters for outsiders.
     */
    /// OMOD-AGUARD-1
    /// OMOD-AGUARD-2
    /// OMOD-AGUARD-5
    function test_OMOD_AGUARD_1__OMOD_AGUARD_2__OMOD_AGUARD_5_onlyGuardian_authorizesExactHolderAndExactError()
        public
    {
        vm.prank(GUARDIAN);
        // Call: invoke the guardian-only action from the configured guardian.
        harness.guardianOnlyAction();
        assertEq(harness.lastModifierId(), 1, "guardian should pass guardian-only action");

        // Verify: non-guardian callers see the exact `(caller, guardian)` error payload.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, OTHER, GUARDIAN)
        );
        vm.prank(OTHER);
        harness.guardianOnlyAction();
    }

    /**
     * @dev Verifies `onlyDeployer` admits the deployer and rejects every other caller.
     */
    /// OMOD-ADEP-1
    /// OMOD-ADEP-2
    function test_OMOD_ADEP_1__OMOD_ADEP_2_onlyDeployer_authorizesExactHolderAndRejectsOutsiders() public {
        vm.prank(DEPLOYER);
        // Call: invoke the deployer-only action from the configured deployer.
        harness.deployerOnlyAction();
        assertEq(harness.lastModifierId(), 2, "deployer should pass deployer-only action");

        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(OTHER);
        // Call: invoke the deployer-only action from a non-deployer.
        harness.deployerOnlyAction();
    }

    /**
     * @dev Verifies `onlyTxRecoveryAddress` admits the configured holder and rejects exact outsiders.
     */
    /// OMOD-ATXREC-1
    /// OMOD-ATXREC-2
    /// OMOD-ATXREC-3
    function test_OMOD_ATXREC_1__OMOD_ATXREC_2__OMOD_ATXREC_3_onlyTxRecovery_authorizesExactHolderAndExactError()
        public
    {
        vm.prank(TX_RECOVERY);
        // Call: invoke the tx-recovery-only action from the configured recovery address.
        harness.txRecoveryOnlyAction();
        assertEq(harness.lastModifierId(), 3, "tx recovery holder should pass");

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationTxRecovery.UnauthorizedTxRecoveryAddress.selector, OTHER, TX_RECOVERY)
        );
        vm.prank(OTHER);
        harness.txRecoveryOnlyAction();
    }

    /**
     * @dev Verifies `onlyGuardianRecoveryAddress` admits the configured holder and rejects exact outsiders.
     */
    /// OMOD-AGREC-1
    /// OMOD-AGREC-2
    /// OMOD-AGREC-3
    function test_OMOD_AGREC_1__OMOD_AGREC_2__OMOD_AGREC_3_onlyGuardianRecovery_authorizesExactHolderAndExactError()
        public
    {
        vm.prank(GUARDIAN_RECOVERY);
        // Call: invoke the guardian-recovery-only action from the configured recovery address.
        harness.guardianRecoveryOnlyAction();
        assertEq(harness.lastModifierId(), 4, "guardian recovery holder should pass");

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector, OTHER, GUARDIAN_RECOVERY
            )
        );
        vm.prank(OTHER);
        harness.guardianRecoveryOnlyAction();
    }

    /**
     * @dev Verifies `onlyPendingGuardian` admits the pending guardian and clears access after acceptance.
     */
    /// OMOD-APENDG-1
    /// OMOD-APENDG-2
    /// OMOD-APENDG-4
    /// OMOD-AATOM-2
    function test_OMOD_APENDG_1__OMOD_APENDG_2__OMOD_APENDG_4__OMOD_AATOM_2_pendingGuardian_lifecycleEnforcesExactHolder()
        public
    {
        // Setup: configure a pending guardian ready for acceptance.
        harness.setGuardianState(GUARDIAN, PENDING_GUARDIAN, true);

        vm.prank(PENDING_GUARDIAN);
        // Call: pending guardian passes the modifier and accepts the transition.
        harness.acceptPendingGuardianAction();

        // Verify: the accepted address can no longer satisfy `onlyPendingGuardian` after state clears.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, PENDING_GUARDIAN, address(0)
            )
        );
        vm.prank(PENDING_GUARDIAN);
        harness.pendingGuardianOnlyAction();

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, OTHER, address(0))
        );
        vm.prank(OTHER);
        harness.pendingGuardianOnlyAction();
    }

    /**
     * @dev Verifies `onlyRecoveryPendingGuardian` admits the pending guardian and rejects outsiders beforehand.
     */
    /// OMOD-ARPENDG-1
    /// OMOD-ARPENDG-2
    function test_OMOD_ARPENDG_1__OMOD_ARPENDG_2_onlyRecoveryPendingGuardian_authorizesExactHolderAndRejectsOutsiders()
        public
    {
        harness.setGuardianRecoveryState(GUARDIAN_RECOVERY, RECOVERY_PENDING_GUARDIAN, true);

        vm.prank(RECOVERY_PENDING_GUARDIAN);
        // Call: invoke the recovery-pending-guardian action from the configured pending guardian.
        harness.recoveryPendingGuardianOnlyAction();
        assertEq(harness.lastModifierId(), 6, "recovery pending guardian should pass");

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector,
                OTHER,
                RECOVERY_PENDING_GUARDIAN
            )
        );
        vm.prank(OTHER);
        harness.recoveryPendingGuardianOnlyAction();
    }

    /**
     * @dev Verifies `onlyGuardianRecoveryAddress` fails closed with `expected = 0` when unset.
     */
    /// OMOD-AZERO-4
    function test_OMOD_AZERO_4_onlyGuardianRecovery_zeroRecoveryAddress_rejectsNonZeroCaller() public {
        harness.setGuardianRecoveryState(address(0), RECOVERY_PENDING_GUARDIAN, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector, OTHER, address(0)
            )
        );
        vm.prank(OTHER);
        harness.guardianRecoveryOnlyAction();
    }

    /**
     * @dev Verifies the previous guardian is rejected after a pending guardian accepts the transfer.
     */
    /// OMOD-AGUARD-3
    /// OMOD-AATOM-1
    function test_OMOD_AGUARD_3__OMOD_AATOM_1_oldGuardianRejected_afterPendingGuardianAccepts() public {
        // Setup: configure a pending guardian and complete acceptance through an `onlyPendingGuardian` function.
        harness.setGuardianState(GUARDIAN, PENDING_GUARDIAN, true);

        vm.prank(PENDING_GUARDIAN);
        // Call: accept the guardian transition through the modifier-guarded harness action.
        harness.acceptPendingGuardianAction();

        // Verify: only the new guardian can pass the guardian-only modifier after acceptance.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, GUARDIAN, PENDING_GUARDIAN)
        );
        vm.prank(GUARDIAN);
        harness.guardianOnlyAction();

        vm.prank(PENDING_GUARDIAN);
        harness.guardianOnlyAction();
        assertEq(harness.lastModifierId(), 1, "new guardian should pass guardian-only action");
    }

    /**
     * @dev Verifies the pending guardian cannot pass guardian-only functions before acceptance.
     */
    /// OMOD-AGUARD-4
    function test_OMOD_AGUARD_4_pendingGuardian_cannotPassGuardianOnlyModifier() public {
        // Setup: configure a pending guardian while keeping the current guardian unchanged.
        harness.setGuardianState(GUARDIAN, PENDING_GUARDIAN, false);

        // Verify: pending guardian is still rejected by `onlyGuardian`.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardian.selector, PENDING_GUARDIAN, GUARDIAN
            )
        );
        vm.prank(PENDING_GUARDIAN);
        // Call: invoke the guardian-only harness action from the pending guardian.
        harness.guardianOnlyAction();
    }

    /**
     * @dev Verifies `UnauthorizedDeployer()` carries only its selector and no leaked role data.
     */
    /// OMOD-ADEP-3
    function test_OMOD_ADEP_3_onlyDeployer_revertCarriesNoParameters() public {
        // Setup: configure a distinct deployer and choose a non-deployer caller.
        harness.setDeployer(DEPLOYER);

        vm.prank(OTHER);
        // Call: invoke the deployer-only action via low-level call to capture raw revert bytes.
        (bool success, bytes memory revertData) =
            address(harness).call(abi.encodeCall(harness.deployerOnlyAction, ()));

        // Verify: the revert contains exactly the selector and no encoded addresses.
        assertFalse(success, "non-deployer call should revert");
        assertEq(revertData, abi.encodeWithSelector(IOrganizationInitialization.UnauthorizedDeployer.selector));
        assertEq(revertData.length, 4, "unauthorized-deployer revert should not include parameters");
    }

    /**
     * @dev Verifies `onlyPendingGuardian` rejects all callers when no pending guardian is configured.
     */
    /// OMOD-APENDG-3
    /// OMOD-AZERO-5
    function test_OMOD_APENDG_3__OMOD_AZERO_5_onlyPendingGuardian_withoutPendingGuardian_rejectsAllCallers()
        public
    {
        // Setup: clear pending guardian while keeping other roles non-zero.
        harness.setGuardianState(GUARDIAN, address(0), false);

        // Verify: both the current guardian and an arbitrary outsider are rejected with `pendingGuardian = 0`.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, GUARDIAN, address(0))
        );
        vm.prank(GUARDIAN);
        harness.pendingGuardianOnlyAction();

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, OTHER, address(0))
        );
        vm.prank(OTHER);
        // Call: invoke the pending-guardian-only action with no pending guardian configured.
        harness.pendingGuardianOnlyAction();
    }

    /**
     * @dev Verifies the current guardian is rejected by `onlyPendingGuardian` when a different pending guardian exists.
     */
    /// OMOD-APENDG-5
    function test_OMOD_APENDG_5_currentGuardian_rejectedByOnlyPendingGuardian() public {
        // Setup: configure a distinct current guardian and pending guardian.
        harness.setGuardianState(GUARDIAN, PENDING_GUARDIAN, true);

        // Verify: the live guardian is not treated as the pending guardian.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, GUARDIAN, PENDING_GUARDIAN
            )
        );
        vm.prank(GUARDIAN);
        // Call: invoke the pending-guardian-only action from the current guardian.
        harness.pendingGuardianOnlyAction();
    }

    /**
     * @dev Verifies `onlyRecoveryPendingGuardian` rejects all callers when no recovery pending guardian exists.
     */
    /// OMOD-ARPENDG-3
    function test_OMOD_ARPENDG_3_onlyRecoveryPendingGuardian_withoutPendingGuardian_rejectsAllCallers() public {
        // Setup: clear recovery pending guardian while keeping the configured recovery address non-zero.
        harness.setGuardianRecoveryState(GUARDIAN_RECOVERY, address(0), false);

        // Verify: both the configured recovery address and a stranger are rejected with `pendingGuardian = 0`.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector,
                GUARDIAN_RECOVERY,
                address(0)
            )
        );
        vm.prank(GUARDIAN_RECOVERY);
        harness.recoveryPendingGuardianOnlyAction();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector, OTHER, address(0)
            )
        );
        vm.prank(OTHER);
        // Call: invoke the recovery-pending-guardian action when no pending guardian is configured.
        harness.recoveryPendingGuardianOnlyAction();
    }

    /**
     * @dev Verifies a cleared recovery pending guardian can no longer pass after acceptance.
     */
    /// OMOD-ARPENDG-4
    /// OMOD-AATOM-3
    function test_OMOD_ARPENDG_4__OMOD_AATOM_3_formerRecoveryPendingGuardian_rejectedAfterAcceptance() public {
        // Setup: configure and accept a recovery guardian update through the guarded acceptance action.
        harness.setGuardianRecoveryState(GUARDIAN_RECOVERY, RECOVERY_PENDING_GUARDIAN, true);

        vm.prank(RECOVERY_PENDING_GUARDIAN);
        // Call: accept the recovery-pending-guardian transition.
        harness.acceptRecoveryPendingGuardianAction();

        // Verify: the accepted address no longer passes the recovery-pending-guardian modifier after state clears.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector,
                RECOVERY_PENDING_GUARDIAN,
                address(0)
            )
        );
        vm.prank(RECOVERY_PENDING_GUARDIAN);
        harness.recoveryPendingGuardianOnlyAction();
    }

    /**
     * @dev Verifies the recovery address itself cannot pass `onlyRecoveryPendingGuardian`.
     */
    /// OMOD-ARPENDG-5
    function test_OMOD_ARPENDG_5_recoveryAddress_rejectedByOnlyRecoveryPendingGuardian() public {
        // Setup: configure distinct recovery and pending-guardian addresses.
        harness.setGuardianRecoveryState(GUARDIAN_RECOVERY, RECOVERY_PENDING_GUARDIAN, false);

        // Verify: the configured recovery address is not treated as the recovery pending guardian.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector,
                GUARDIAN_RECOVERY,
                RECOVERY_PENDING_GUARDIAN
            )
        );
        vm.prank(GUARDIAN_RECOVERY);
        // Call: invoke the recovery-pending-guardian action from the recovery address itself.
        harness.recoveryPendingGuardianOnlyAction();
    }

    /**
     * @dev Verifies `onlyGuardian` rejects every other tracked role holder.
     */
    /// OMOD-AROLE-1
    function test_OMOD_AROLE_1_onlyGuardian_rejectsAllOtherRoleHolders() public {
        _assertGuardianOnlyRejects(DEPLOYER);
        _assertGuardianOnlyRejects(TX_RECOVERY);
        _assertGuardianOnlyRejects(GUARDIAN_RECOVERY);
        _assertGuardianOnlyRejects(PENDING_GUARDIAN);
        _assertGuardianOnlyRejects(RECOVERY_PENDING_GUARDIAN);
    }

    /**
     * @dev Verifies `onlyDeployer` rejects every non-deployer role holder.
     */
    /// OMOD-AROLE-2
    function test_OMOD_AROLE_2_onlyDeployer_rejectsAllOtherRoleHolders() public {
        _assertOnlyDeployerRejects(GUARDIAN);
        _assertOnlyDeployerRejects(TX_RECOVERY);
        _assertOnlyDeployerRejects(GUARDIAN_RECOVERY);
        _assertOnlyDeployerRejects(PENDING_GUARDIAN);
        _assertOnlyDeployerRejects(RECOVERY_PENDING_GUARDIAN);
    }

    /**
     * @dev Verifies `onlyTxRecoveryAddress` rejects every non-recovery tracked role holder.
     */
    /// OMOD-AROLE-3
    function test_OMOD_AROLE_3_onlyTxRecovery_rejectsAllOtherRoleHolders() public {
        _assertTxRecoveryOnlyRejects(GUARDIAN);
        _assertTxRecoveryOnlyRejects(DEPLOYER);
        _assertTxRecoveryOnlyRejects(GUARDIAN_RECOVERY);
        _assertTxRecoveryOnlyRejects(PENDING_GUARDIAN);
        _assertTxRecoveryOnlyRejects(RECOVERY_PENDING_GUARDIAN);
    }

    /**
     * @dev Verifies `onlyGuardianRecoveryAddress` rejects every non-recovery tracked role holder.
     */
    /// OMOD-AROLE-4
    function test_OMOD_AROLE_4_onlyGuardianRecovery_rejectsAllOtherRoleHolders() public {
        _assertGuardianRecoveryOnlyRejects(GUARDIAN);
        _assertGuardianRecoveryOnlyRejects(DEPLOYER);
        _assertGuardianRecoveryOnlyRejects(TX_RECOVERY);
        _assertGuardianRecoveryOnlyRejects(PENDING_GUARDIAN);
        _assertGuardianRecoveryOnlyRejects(RECOVERY_PENDING_GUARDIAN);
    }

    /**
     * @dev Verifies `onlyPendingGuardian` rejects every non-pending tracked role holder.
     */
    /// OMOD-AROLE-5
    function test_OMOD_AROLE_5_onlyPendingGuardian_rejectsAllOtherRoleHolders() public {
        _assertPendingGuardianOnlyRejects(GUARDIAN);
        _assertPendingGuardianOnlyRejects(DEPLOYER);
        _assertPendingGuardianOnlyRejects(TX_RECOVERY);
        _assertPendingGuardianOnlyRejects(GUARDIAN_RECOVERY);
        _assertPendingGuardianOnlyRejects(RECOVERY_PENDING_GUARDIAN);
    }

    /**
     * @dev Verifies `onlyRecoveryPendingGuardian` rejects every non-pending tracked role holder.
     */
    /// OMOD-AROLE-6
    function test_OMOD_AROLE_6_onlyRecoveryPendingGuardian_rejectsAllOtherRoleHolders() public {
        _assertRecoveryPendingGuardianOnlyRejects(GUARDIAN);
        _assertRecoveryPendingGuardianOnlyRejects(DEPLOYER);
        _assertRecoveryPendingGuardianOnlyRejects(TX_RECOVERY);
        _assertRecoveryPendingGuardianOnlyRejects(GUARDIAN_RECOVERY);
        _assertRecoveryPendingGuardianOnlyRejects(PENDING_GUARDIAN);
    }

    /**
     * @dev Verifies one shared address can satisfy exactly the modifiers for the roles it currently holds.
     */
    /// OMOD-AROLE-7
    function test_OMOD_AROLE_7_dualRoleAddress_passesOwnedModifiers_only() public {
        // Setup: intentionally assign one address to both guardian and tx-recovery, leaving other roles distinct.
        address dualRole = address(0xB201);
        harness.setGuardianState(dualRole, PENDING_GUARDIAN, false);
        harness.setTxRecoveryAddress(dualRole);
        harness.setDeployer(DEPLOYER);
        harness.setGuardianRecoveryState(GUARDIAN_RECOVERY, RECOVERY_PENDING_GUARDIAN, false);

        vm.prank(dualRole);
        harness.guardianOnlyAction();
        vm.prank(dualRole);
        harness.txRecoveryOnlyAction();

        // Verify: the shared address passes only the modifiers for the two roles it actually holds.
        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(dualRole);
        harness.deployerOnlyAction();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector, dualRole, GUARDIAN_RECOVERY
            )
        );
        vm.prank(dualRole);
        harness.guardianRecoveryOnlyAction();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, dualRole, PENDING_GUARDIAN
            )
        );
        vm.prank(dualRole);
        harness.pendingGuardianOnlyAction();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector,
                dualRole,
                RECOVERY_PENDING_GUARDIAN
            )
        );
        vm.prank(dualRole);
        harness.recoveryPendingGuardianOnlyAction();
    }

    /**
     * @dev Verifies `onlyGuardian` fails closed for non-zero callers when guardian storage is unset.
     */
    /// OMOD-AZERO-1
    function test_OMOD_AZERO_1_onlyGuardian_zeroGuardian_rejectsNonZeroCaller() public {
        harness.setGuardianState(address(0), PENDING_GUARDIAN, false);

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, OTHER, address(0))
        );
        vm.prank(OTHER);
        harness.guardianOnlyAction();
    }

    /**
     * @dev Verifies `onlyDeployer` fails closed when deployer storage is unset.
     */
    /// OMOD-AZERO-2
    function test_OMOD_AZERO_2_onlyDeployer_zeroDeployer_rejectsNonZeroCaller() public {
        harness.setDeployer(address(0));

        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(OTHER);
        harness.deployerOnlyAction();
    }

    /**
     * @dev Verifies `onlyTxRecoveryAddress` fails closed with `expected = 0` when recovery is unset.
     */
    /// OMOD-AZERO-3
    function test_OMOD_AZERO_3_onlyTxRecovery_zeroRecoveryAddress_rejectsNonZeroCaller() public {
        harness.setTxRecoveryAddress(address(0));

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationTxRecovery.UnauthorizedTxRecoveryAddress.selector, OTHER, address(0))
        );
        vm.prank(OTHER);
        harness.txRecoveryOnlyAction();
    }

    /**
     * @dev Verifies `onlyRecoveryPendingGuardian` fails closed with `pendingGuardian = 0`.
     */
    /// OMOD-AZERO-6
    function test_OMOD_AZERO_6_onlyRecoveryPendingGuardian_zeroPendingGuardian_rejectsNonZeroCaller() public {
        harness.setGuardianRecoveryState(GUARDIAN_RECOVERY, address(0), false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector, OTHER, address(0)
            )
        );
        vm.prank(OTHER);
        harness.recoveryPendingGuardianOnlyAction();
    }

    /**
     * @dev Seeds one distinct holder for every role-based modifier slot.
     */
    function _setDistinctRoles() internal {
        harness.setGuardianState(GUARDIAN, PENDING_GUARDIAN, false);
        harness.setDeployer(DEPLOYER);
        harness.setTxRecoveryAddress(TX_RECOVERY);
        harness.setGuardianRecoveryState(GUARDIAN_RECOVERY, RECOVERY_PENDING_GUARDIAN, false);
    }

    /// @dev Asserts a caller is rejected by the guardian-only modifier with the expected typed error.
    function _assertGuardianOnlyRejects(address caller) internal {
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, caller, GUARDIAN));
        vm.prank(caller);
        harness.guardianOnlyAction();
    }

    /// @dev Asserts a caller is rejected by the deployer-only modifier.
    function _assertOnlyDeployerRejects(address caller) internal {
        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(caller);
        harness.deployerOnlyAction();
    }

    /// @dev Asserts a caller is rejected by the tx-recovery-only modifier with the expected typed error.
    function _assertTxRecoveryOnlyRejects(address caller) internal {
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationTxRecovery.UnauthorizedTxRecoveryAddress.selector, caller, TX_RECOVERY)
        );
        vm.prank(caller);
        harness.txRecoveryOnlyAction();
    }

    /// @dev Asserts a caller is rejected by the guardian-recovery-only modifier with the expected typed error.
    function _assertGuardianRecoveryOnlyRejects(address caller) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector, caller, GUARDIAN_RECOVERY
            )
        );
        vm.prank(caller);
        harness.guardianRecoveryOnlyAction();
    }

    /// @dev Asserts a caller is rejected by the pending-guardian-only modifier with the expected typed error.
    function _assertPendingGuardianOnlyRejects(address caller) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, caller, PENDING_GUARDIAN
            )
        );
        vm.prank(caller);
        harness.pendingGuardianOnlyAction();
    }

    /// @dev Asserts a caller is rejected by the recovery-pending-guardian modifier with the expected typed error.
    function _assertRecoveryPendingGuardianOnlyRejects(address caller) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector,
                caller,
                RECOVERY_PENDING_GUARDIAN
            )
        );
        vm.prank(caller);
        harness.recoveryPendingGuardianOnlyAction();
    }
}
