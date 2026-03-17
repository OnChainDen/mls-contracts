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
 * @dev Fuzz tests for `OrganizationModifiers` access-control boundaries.
 */
contract OrganizationModifiersFuzzTest is Test {
    OrganizationModifiersHarness internal harness;

    address internal constant FALLBACK_GUARDIAN = address(0xC101);
    address internal constant FALLBACK_DEPLOYER = address(0xC102);
    address internal constant FALLBACK_TX_RECOVERY = address(0xC103);
    address internal constant FALLBACK_GUARDIAN_RECOVERY = address(0xC104);
    address internal constant FALLBACK_PENDING_GUARDIAN = address(0xC105);
    address internal constant FALLBACK_RECOVERY_PENDING_GUARDIAN = address(0xC106);

    /**
     * @dev Deploys the shared modifier harness.
     */
    function setUp() public {
        harness = new OrganizationModifiersHarness();
    }

    /// @dev Verifies only the stored guardian can pass the guardian-only modifier.
    function testFuzz_randomCaller_onlyGuardianExactMatchPasses(address guardian, address caller) public {
        vm.assume(guardian != address(0));

        // Setup: configure the guardian slot with the fuzzed guardian and seed fallback values elsewhere.
        _seedFallbackRoles();
        harness.setGuardianState(guardian, FALLBACK_PENDING_GUARDIAN, false);

        // Call: invoke the guardian-only action from the fuzzed caller.
        _assertCallOutcome(caller, abi.encodeCall(harness.guardianOnlyAction, ()), caller == guardian);
    }

    /// @dev Verifies only the stored deployer can pass the deployer-only modifier.
    function testFuzz_randomCaller_onlyDeployerExactMatchPasses(address deployer, address caller) public {
        vm.assume(deployer != address(0));

        // Setup: configure the deployer slot with the fuzzed deployer and seed fallback values elsewhere.
        _seedFallbackRoles();
        harness.setDeployer(deployer);

        // Call: invoke the deployer-only action from the fuzzed caller.
        _assertCallOutcome(caller, abi.encodeCall(harness.deployerOnlyAction, ()), caller == deployer);
    }

    /// @dev Verifies only the stored tx-recovery address can pass the tx-recovery-only modifier.
    function testFuzz_randomCaller_onlyTxRecoveryExactMatchPasses(address txRecovery, address caller) public {
        vm.assume(txRecovery != address(0));

        // Setup: configure the tx-recovery slot with the fuzzed address and seed fallback values elsewhere.
        _seedFallbackRoles();
        harness.setTxRecoveryAddress(txRecovery);

        // Call: invoke the tx-recovery-only action from the fuzzed caller.
        _assertCallOutcome(caller, abi.encodeCall(harness.txRecoveryOnlyAction, ()), caller == txRecovery);
    }

    /// @dev Verifies only the stored guardian-recovery address can pass the guardian-recovery-only modifier.
    function testFuzz_randomCaller_onlyGuardianRecoveryExactMatchPasses(address guardianRecovery, address caller)
        public
    {
        vm.assume(guardianRecovery != address(0));

        // Setup: configure the guardian-recovery slot with the fuzzed address and seed fallback values elsewhere.
        _seedFallbackRoles();
        harness.setGuardianRecoveryState(guardianRecovery, FALLBACK_RECOVERY_PENDING_GUARDIAN, false);

        // Call: invoke the guardian-recovery-only action from the fuzzed caller.
        _assertCallOutcome(caller, abi.encodeCall(harness.guardianRecoveryOnlyAction, ()), caller == guardianRecovery);
    }

    /// @dev Verifies only the stored pending guardian can pass the pending-guardian-only modifier.
    function testFuzz_randomCaller_onlyPendingGuardianExactMatchPasses(address pendingGuardian, address caller) public {
        vm.assume(pendingGuardian != address(0));

        // Setup: configure the pending-guardian slot with the fuzzed address and seed fallback values elsewhere.
        _seedFallbackRoles();
        harness.setGuardianState(FALLBACK_GUARDIAN, pendingGuardian, false);

        // Call: invoke the pending-guardian-only action from the fuzzed caller.
        _assertCallOutcome(caller, abi.encodeCall(harness.pendingGuardianOnlyAction, ()), caller == pendingGuardian);
    }

    /// @dev Verifies only the stored recovery pending guardian can pass its acceptance modifier.
    function testFuzz_randomCaller_onlyRecoveryPendingGuardianExactMatchPasses(
        address recoveryPendingGuardian,
        address caller
    ) public {
        vm.assume(recoveryPendingGuardian != address(0));

        // Setup: configure the recovery-pending-guardian slot with the fuzzed address and seed fallback values
        // elsewhere.
        _seedFallbackRoles();
        harness.setGuardianRecoveryState(FALLBACK_GUARDIAN_RECOVERY, recoveryPendingGuardian, false);

        // Call: invoke the recovery-pending-guardian-only action from the fuzzed caller.
        _assertCallOutcome(
            caller, abi.encodeCall(harness.recoveryPendingGuardianOnlyAction, ()), caller == recoveryPendingGuardian
        );
    }

    /// @dev Verifies guardian-only access returns the exact typed guardian revert for non-matching callers.
    function testFuzz_randomGuardianAddress_exactMatchPassesOtherwiseTypedRevert(
        address configuredGuardian,
        address caller
    ) public {
        vm.assume(configuredGuardian != address(0));

        // Setup: seed fallback state and overwrite only the guardian slot under test.
        _seedFallbackRoles();
        harness.setGuardianState(configuredGuardian, FALLBACK_PENDING_GUARDIAN, false);

        // Call: invoke the guardian-only action from the fuzzed caller.
        _assertTypedRevertOrSuccess({
            caller: caller,
            callData: abi.encodeCall(harness.guardianOnlyAction, ()),
            expectedRevertData: abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardian.selector, caller, configuredGuardian
            ),
            shouldSucceed: caller == configuredGuardian
        });
    }

    /// @dev Verifies deployer-only access returns the exact typed deployer revert for non-matching callers.
    function testFuzz_randomDeployerAddress_exactMatchPassesOtherwiseTypedRevert(
        address configuredDeployer,
        address caller
    ) public {
        vm.assume(configuredDeployer != address(0));

        // Setup: seed fallback state and overwrite only the deployer slot under test.
        _seedFallbackRoles();
        harness.setDeployer(configuredDeployer);

        // Call: invoke the deployer-only action from the fuzzed caller.
        _assertTypedRevertOrSuccess({
            caller: caller,
            callData: abi.encodeCall(harness.deployerOnlyAction, ()),
            expectedRevertData: abi.encodeWithSelector(IOrganizationInitialization.UnauthorizedDeployer.selector),
            shouldSucceed: caller == configuredDeployer
        });
    }

    /// @dev Verifies tx-recovery-only access returns the exact typed revert for non-matching callers.
    function testFuzz_randomTxRecoveryAddress_exactMatchPassesOtherwiseTypedRevert(
        address configuredTxRecovery,
        address caller
    ) public {
        vm.assume(configuredTxRecovery != address(0));

        // Setup: seed fallback state and overwrite only the tx-recovery slot under test.
        _seedFallbackRoles();
        harness.setTxRecoveryAddress(configuredTxRecovery);

        // Call: invoke the tx-recovery-only action from the fuzzed caller.
        _assertTypedRevertOrSuccess({
            caller: caller,
            callData: abi.encodeCall(harness.txRecoveryOnlyAction, ()),
            expectedRevertData: abi.encodeWithSelector(
                IOrganizationTxRecovery.UnauthorizedTxRecoveryAddress.selector, caller, configuredTxRecovery
            ),
            shouldSucceed: caller == configuredTxRecovery
        });
    }

    /// @dev Verifies guardian-recovery-only access returns the exact typed revert for non-matching callers.
    function testFuzz_randomGuardianRecoveryAddress_exactMatchPassesOtherwiseTypedRevert(
        address configuredGuardianRecovery,
        address caller
    ) public {
        vm.assume(configuredGuardianRecovery != address(0));

        // Setup: seed fallback state and overwrite only the guardian-recovery slot under test.
        _seedFallbackRoles();
        harness.setGuardianRecoveryState(configuredGuardianRecovery, FALLBACK_RECOVERY_PENDING_GUARDIAN, false);

        // Call: invoke the guardian-recovery-only action from the fuzzed caller.
        _assertTypedRevertOrSuccess({
            caller: caller,
            callData: abi.encodeCall(harness.guardianRecoveryOnlyAction, ()),
            expectedRevertData: abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector,
                caller,
                configuredGuardianRecovery
            ),
            shouldSucceed: caller == configuredGuardianRecovery
        });
    }

    /// @dev Verifies pending-guardian-only access returns the exact typed revert for non-matching callers.
    function testFuzz_randomPendingGuardianAddress_exactMatchPassesOtherwiseTypedRevert(
        address configuredPendingGuardian,
        address caller
    ) public {
        vm.assume(configuredPendingGuardian != address(0));

        // Setup: seed fallback state and overwrite only the pending-guardian slot under test.
        _seedFallbackRoles();
        harness.setGuardianState(FALLBACK_GUARDIAN, configuredPendingGuardian, false);

        // Call: invoke the pending-guardian-only action from the fuzzed caller.
        _assertTypedRevertOrSuccess({
            caller: caller,
            callData: abi.encodeCall(harness.pendingGuardianOnlyAction, ()),
            expectedRevertData: abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, caller, configuredPendingGuardian
            ),
            shouldSucceed: caller == configuredPendingGuardian
        });
    }

    /// @dev Verifies recovery-pending-guardian-only access returns the exact typed revert for non-matching callers.
    function testFuzz_randomRecoveryPendingGuardianAddress_exactMatchPassesOtherwiseTypedRevert(
        address configuredRecoveryPendingGuardian,
        address caller
    ) public {
        vm.assume(configuredRecoveryPendingGuardian != address(0));

        // Setup: seed fallback state and overwrite only the recovery-pending-guardian slot under test.
        _seedFallbackRoles();
        harness.setGuardianRecoveryState(FALLBACK_GUARDIAN_RECOVERY, configuredRecoveryPendingGuardian, false);

        // Call: invoke the recovery-pending-guardian-only action from the fuzzed caller.
        _assertTypedRevertOrSuccess({
            caller: caller,
            callData: abi.encodeCall(harness.recoveryPendingGuardianOnlyAction, ()),
            expectedRevertData: abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector,
                caller,
                configuredRecoveryPendingGuardian
            ),
            shouldSucceed: caller == configuredRecoveryPendingGuardian
        });
    }

    /// @dev Seeds all modifier slots with fallback non-zero values so each fuzz test can overwrite one role at a time.
    function _seedFallbackRoles() internal {
        harness.setGuardianState(FALLBACK_GUARDIAN, FALLBACK_PENDING_GUARDIAN, false);
        harness.setDeployer(FALLBACK_DEPLOYER);
        harness.setTxRecoveryAddress(FALLBACK_TX_RECOVERY);
        harness.setGuardianRecoveryState(FALLBACK_GUARDIAN_RECOVERY, FALLBACK_RECOVERY_PENDING_GUARDIAN, false);
    }

    /// @dev Executes one call as `caller` and asserts whether it should succeed.
    function _assertCallOutcome(address caller, bytes memory callData, bool shouldSucceed) internal {
        vm.prank(caller);
        (bool success,) = address(harness).call(callData);
        assertEq(success, shouldSucceed, "modifier success should match exact stored-role equality");
    }

    /// @dev Executes one guarded call and checks either success or the exact typed revert payload.
    function _assertTypedRevertOrSuccess(
        address caller,
        bytes memory callData,
        bytes memory expectedRevertData,
        bool shouldSucceed
    ) internal {
        vm.prank(caller);
        (bool success, bytes memory revertData) = address(harness).call(callData);

        if (shouldSucceed) {
            assertTrue(success, "exact stored role should pass");
            return;
        }

        assertFalse(success, "non-matching caller should revert");
        assertEq(revertData, expectedRevertData, "non-matching caller should get the exact typed revert");
    }
}
