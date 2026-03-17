// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {
    LibOrganizationSignaturesHarness
} from "test/organization/libraries/LibOrganizationSignatures/LibOrganizationSignaturesHarness.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationSignatures` nonce derivation and consumption behavior.
 */
contract LibOrganizationSignaturesTest is Test {
    /// @dev Fresh harness deployed per test for isolated nonce storage.
    LibOrganizationSignaturesHarness internal harness;

    /**
     * @dev Deploys a fresh library harness before each test.
     */
    function setUp() public {
        harness = new LibOrganizationSignaturesHarness();
    }

    /// @dev Verifies `LibOrganizationSignatures.computeNonce` is deterministic for identical inputs.
    function test_NMSIG_CN_1__NMSIG_INV_3_computeNonce_sameInputsRemainDeterministic() public view {
        // Setup: define one nonce tuple with fixed operation type, payload, and salt.
        bytes memory operationData = abi.encode(address(0xA11CE), uint256(7));

        // Call: compute the nonce twice with the same inputs.
        uint256 nonceA = harness.computeNonceViaLibrary(OperationType.ModifyAdmins, operationData, 17);
        uint256 nonceB = harness.computeNonceViaLibrary(OperationType.ModifyAdmins, operationData, 17);

        // Verify: identical tuples must always map to the same nonce value.
        assertEq(nonceA, nonceB, "same tuple should compute the same nonce");
    }

    /// @dev Verifies `LibOrganizationSignatures.computeNonce` changes when any bound field changes.
    function test_NMSIG_CN_2__NMSIG_CN_3__NMSIG_CN_4__NMSIG_CN_5__NMSIG_INV_4__NMSIG_INV_5_computeNonce_changesWhenBoundFieldChanges()
        public
    {
        // Setup: define a baseline tuple and deploy a second harness to vary the organization address binding.
        bytes memory operationData = abi.encode(address(0xBEEF), uint256(11));
        LibOrganizationSignaturesHarness secondHarness = new LibOrganizationSignaturesHarness();

        // Call: compute the baseline nonce and one-field mutations across type, data, salt, and organization address.
        uint256 baseline = harness.computeNonceViaLibrary(OperationType.ModifyAdmins, operationData, 19);
        uint256 differentType = harness.computeNonceViaLibrary(OperationType.ModifyMembers, operationData, 19);
        uint256 differentData =
            harness.computeNonceViaLibrary(OperationType.ModifyAdmins, abi.encode(address(0xCAFE), uint256(11)), 19);
        uint256 differentSalt = harness.computeNonceViaLibrary(OperationType.ModifyAdmins, operationData, 20);
        uint256 differentOrganization =
            secondHarness.computeNonceViaLibrary(OperationType.ModifyAdmins, operationData, 19);

        // Verify: each bound field mutation must move the nonce into a different replay domain.
        assertTrue(baseline != differentType, "operation type should be bound");
        assertTrue(baseline != differentData, "operation data should be bound");
        assertTrue(baseline != differentSalt, "salt should be bound");
        assertTrue(baseline != differentOrganization, "organization address should be bound");
    }

    /// @dev Verifies `LibOrganizationSignatures.computeNonce` supports deterministic empty payloads.
    function test_NMSIG_CN_6_computeNonce_emptyOperationDataIsSupported() public view {
        // Setup: use an empty operation payload with a fixed operation type and salt.
        bytes memory emptyOperationData = bytes("");

        // Call: compute the nonce twice for the empty payload tuple.
        uint256 nonceA = harness.computeNonceViaLibrary(OperationType.Upgrade, emptyOperationData, 21);
        uint256 nonceB = harness.computeNonceViaLibrary(OperationType.Upgrade, emptyOperationData, 21);

        // Verify: empty payloads remain supported and deterministic.
        assertEq(nonceA, nonceB, "empty payload nonce should remain deterministic");
    }

    /// @dev Verifies `LibOrganizationSignatures.computeNonce` supports deterministic large payloads.
    function test_NMSIG_CN_7_computeNonce_largeOperationDataIsSupported() public view {
        // Setup: fill a large payload so hashing covers a non-trivial calldata size.
        bytes memory largeOperationData = new bytes(4096);
        for (uint256 i = 0; i < largeOperationData.length; i++) {
            largeOperationData[i] = bytes1(uint8(i));
        }

        // Call: compute the nonce twice for the large payload tuple.
        uint256 nonceA = harness.computeNonceViaLibrary(OperationType.ModifyPolicies, largeOperationData, 22);
        uint256 nonceB = harness.computeNonceViaLibrary(OperationType.ModifyPolicies, largeOperationData, 22);

        // Verify: large payload hashing remains deterministic.
        assertEq(nonceA, nonceB, "large payload nonce should remain deterministic");
    }

    /// @dev Verifies `LibOrganizationSignatures.validateAndConsumeNonceOrRevert` consumes a fresh nonce exactly once.
    function test_NMSIG_VCN_1__NMSIG_VCN_4_validateAndConsumeNonce_consumesFreshNonceAndUpdatesUsage() public {
        // Setup: derive a fresh nonce and assert its pre-consume view state.
        uint256 nonce = harness.computeNonceViaLibrary(OperationType.ModifyGroups, abi.encode(uint256(23)), 23);
        assertFalse(harness.isNonceUsedViaLibrary(nonce), "fresh nonce should start unused");

        // Call: consume the nonce through the library wrapper.
        harness.validateAndConsumeNonceOrRevertViaLibrary(nonce);

        // Verify: the first consume succeeds and flips the used flag to true.
        assertTrue(harness.isNonceUsedViaLibrary(nonce), "consumed nonce should be marked used");
    }

    /// @dev Verifies `LibOrganizationSignatures.validateAndConsumeNonceOrRevert` reverts with the exact reused nonce.
    function test_NMSIG_VCN_2__NMSIG_VCN_3__NMSIG_INV_2_validateAndConsumeNonce_reusedNonceRevertsWithExactValue()
        public
    {
        // Setup: consume one nonce once so the next attempt hits the replay path.
        uint256 nonce = harness.computeNonceViaLibrary(OperationType.ModifyMembers, abi.encode(uint256(24)), 24);
        harness.validateAndConsumeNonceOrRevertViaLibrary(nonce);

        // Verify: reusing the same nonce reverts with `NonceAlreadyUsed(nonce)`.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        // Call: attempt to consume the already-used nonce again.
        harness.validateAndConsumeNonceOrRevertViaLibrary(nonce);
    }

    /// @dev Verifies consuming one nonce does not mark an unrelated nonce as used.
    function test_NMSIG_VCN_5_validateAndConsumeNonce_consumingOneNonceDoesNotTouchAnother() public {
        // Setup: derive two nonces from different salts under the same operation tuple.
        bytes memory operationData = abi.encode(address(0xD00D), uint256(25));
        uint256 nonceA = harness.computeNonceViaLibrary(OperationType.ModifyAdmins, operationData, 25);
        uint256 nonceB = harness.computeNonceViaLibrary(OperationType.ModifyAdmins, operationData, 26);

        // Call: consume only the first nonce.
        harness.validateAndConsumeNonceOrRevertViaLibrary(nonceA);

        // Verify: the unrelated nonce remains untouched.
        assertTrue(harness.isNonceUsedViaLibrary(nonceA), "consumed nonce should be marked used");
        assertFalse(harness.isNonceUsedViaLibrary(nonceB), "unrelated nonce should remain unused");
    }

    /// @dev Verifies once a nonce is consumed it stays used across later successful nonce consumptions.
    function test_NMSIG_VCN_6__NMSIG_INV_1_validateAndConsumeNonce_consumedNonceRemainsMonotonicAcrossLaterOperations()
        public
    {
        // Setup: derive two distinct nonces in the same harness storage.
        uint256 nonceA = harness.computeNonceViaLibrary(OperationType.ModifyPolicies, abi.encode(uint256(26)), 27);
        uint256 nonceB = harness.computeNonceViaLibrary(OperationType.ModifyPolicies, abi.encode(uint256(27)), 28);

        // Call: consume both nonces in sequence.
        harness.validateAndConsumeNonceOrRevertViaLibrary(nonceA);
        harness.validateAndConsumeNonceOrRevertViaLibrary(nonceB);

        // Verify: earlier successful consumption must remain observable after later successes.
        assertTrue(harness.isNonceUsedViaLibrary(nonceA), "first consumed nonce should remain used");
        assertTrue(harness.isNonceUsedViaLibrary(nonceB), "second consumed nonce should be used");
    }
}
