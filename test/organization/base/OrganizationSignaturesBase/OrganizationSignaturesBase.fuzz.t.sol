// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {LibOrganizationSignatures} from "organization/libraries/LibOrganizationSignatures.sol";
import {
    OrganizationSignaturesBaseHarness
} from "test/organization/base/OrganizationSignaturesBase/OrganizationSignaturesBaseHarness.sol";
import {OperationType} from "types/CommonTypes.sol";

/// @dev Expected revert used to model parent-call rollback after nonce consumption.
error ForcedRollback();

/**
 * @dev Harness exposing a consume-then-revert flow for rollback fuzz coverage.
 */
contract OrganizationSignaturesRollbackHarness is OrganizationSignaturesBaseHarness {
    /**
     * @dev Consumes a nonce and reverts in the same call so storage writes should roll back.
     * @param nonce Nonce to consume before the forced revert.
     */
    function consumeNonceAndRevert(uint256 nonce) external {
        LibOrganizationSignatures.validateAndConsumeNonceOrRevert(nonce);
        revert ForcedRollback();
    }
}

/**
 * @dev Fuzz tests for `OrganizationSignaturesBase`.
 */
contract OrganizationSignaturesBaseFuzzTest is Test {
    /// @dev Primary base-wrapper harness used for nonce sensitivity and monotonic-consumption checks.
    OrganizationSignaturesBaseHarness internal harness;

    /// @dev Secondary harness used to prove organization-address isolation in nonce derivation.
    OrganizationSignaturesBaseHarness internal secondHarness;

    /// @dev Rollback harness used to prove revert semantics restore nonce state.
    OrganizationSignaturesRollbackHarness internal rollbackHarness;

    /**
     * @dev Deploys fresh nonce harnesses before each test.
     */
    function setUp() public {
        harness = new OrganizationSignaturesBaseHarness();
        secondHarness = new OrganizationSignaturesBaseHarness();
        rollbackHarness = new OrganizationSignaturesRollbackHarness();
    }

    /// @dev Verifies `computeNonce` changes whenever any field in `(operationType, operationData, salt)` changes.
    /// @param rawOperationTypeA Fuzzed operation-type seed for the first nonce tuple.
    /// @param operationDataA Fuzzed operation payload for the first nonce tuple.
    /// @param saltA Fuzzed salt for the first nonce tuple.
    /// @param rawOperationTypeB Fuzzed operation-type seed for the second nonce tuple.
    /// @param operationDataB Fuzzed operation payload for the second nonce tuple.
    /// @param saltB Fuzzed salt for the second nonce tuple.
    function testFuzz_FLOS_NONCE_30_computeNonce_changesWhenOperationTupleChanges(
        uint8 rawOperationTypeA,
        bytes calldata operationDataA,
        uint256 saltA,
        uint8 rawOperationTypeB,
        bytes calldata operationDataB,
        uint256 saltB
    ) public {
        // Setup: bound both operation types into the valid enum range and skip the identical control tuple.
        OperationType operationTypeA =
            OperationType(bound(uint256(rawOperationTypeA), 0, uint256(OperationType.AccountTransactionRejection)));
        OperationType operationTypeB =
            OperationType(bound(uint256(rawOperationTypeB), 0, uint256(OperationType.AccountTransactionRejection)));
        vm.assume(
            operationTypeA != operationTypeB || keccak256(operationDataA) != keccak256(operationDataB) || saltA != saltB
        );

        // Call: compute both nonces through the external base-wrapper surface.
        uint256 nonceA = harness.computeNonce(operationTypeA, operationDataA, saltA);
        uint256 nonceB = harness.computeNonce(operationTypeB, operationDataB, saltB);

        // Verify: any tuple mutation should move the nonce into a different replay domain.
        assertTrue(nonceA != nonceB, "nonce should change whenever any bound tuple field changes");
    }

    /// @dev Verifies `computeNonce` isolates the same tuple across different organization addresses.
    /// @param rawOperationType Fuzzed operation-type seed bounded into the valid enum range.
    /// @param operationData Fuzzed operation payload shared across both organizations.
    /// @param salt Fuzzed salt shared across both organizations.
    function testFuzz_FLOS_NONCE_31_computeNonce_isolatesOrganizationsForSameTuple(
        uint8 rawOperationType,
        bytes calldata operationData,
        uint256 salt
    ) public {
        // Setup: bound the operation type into the valid enum range.
        OperationType operationType =
            OperationType(bound(uint256(rawOperationType), 0, uint256(OperationType.AccountTransactionRejection)));

        // Call: compute the same tuple on two different organization-address wrappers.
        uint256 firstNonce = harness.computeNonce(operationType, operationData, salt);
        uint256 secondNonce = secondHarness.computeNonce(operationType, operationData, salt);

        // Verify: organization address is part of nonce derivation, so the replay domains stay isolated.
        assertTrue(firstNonce != secondNonce, "same tuple should derive different nonces across organizations");
    }

    /// @dev Verifies `validateAndConsumeNonceOrRevert` flips a fresh nonce from `false` to `true` exactly once and
    /// reverts on replay with the exact nonce value.
    /// @param rawOperationType Fuzzed operation-type seed bounded into the valid enum range.
    /// @param operationData Fuzzed operation payload used to derive the nonce.
    /// @param salt Fuzzed salt used to derive the nonce.
    function testFuzz_FLOS_NONCE_32_validateAndConsumeNonce_consumesFreshNonceOnceAndRevertsOnReplay(
        uint8 rawOperationType,
        bytes calldata operationData,
        uint256 salt
    ) public {
        // Setup: derive one fresh nonce from the fuzzed tuple and confirm it starts unused.
        OperationType operationType =
            OperationType(bound(uint256(rawOperationType), 0, uint256(OperationType.AccountTransactionRejection)));
        uint256 nonce = harness.computeNonce(operationType, operationData, salt);
        assertFalse(harness.isNonceUsed(nonce), "fresh nonce should start unused");

        // Call: consume the nonce once, then attempt a replay expecting the exact reuse error.
        harness.consumeNonceViaLibrary(nonce);
        assertTrue(harness.isNonceUsed(nonce), "successful consumption should flip the used flag");

        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        harness.consumeNonceViaLibrary(nonce);

        // Verify: nonce usage is monotonic and replay attempts always revert with the consumed nonce value.
    }

    /// @dev Verifies parent-call reverts roll nonce consumption back so failed paths do not burn replay protection.
    /// @param rawOperationType Fuzzed operation-type seed bounded into the valid enum range.
    /// @param operationData Fuzzed operation payload used to derive the nonce.
    /// @param salt Fuzzed salt used to derive the nonce.
    function testFuzz_FLOS_ROLL_33_validateAndConsumeNonce_rollsBackUsageWhenParentCallReverts(
        uint8 rawOperationType,
        bytes calldata operationData,
        uint256 salt
    ) public {
        // Setup: derive one fresh nonce from the rollback harness and confirm it starts unused.
        OperationType operationType =
            OperationType(bound(uint256(rawOperationType), 0, uint256(OperationType.AccountTransactionRejection)));
        uint256 nonce = rollbackHarness.computeNonce(operationType, operationData, salt);
        assertFalse(rollbackHarness.isNonceUsed(nonce), "fresh nonce should start unused");

        // Call: consume and revert in one parent call, then consume successfully in a later call.
        vm.expectRevert(ForcedRollback.selector);
        rollbackHarness.consumeNonceAndRevert(nonce);
        assertFalse(rollbackHarness.isNonceUsed(nonce), "rollback path should not burn the nonce");

        rollbackHarness.consumeNonceViaLibrary(nonce);

        // Verify: reverted parent paths leave nonce state untouched, while later successful consumption still works.
        assertTrue(rollbackHarness.isNonceUsed(nonce), "later successful consume should still mark the nonce used");
    }

    /// @dev Verifies the base nonce views are caller-independent, match the direct library formula, and reflect
    /// successful versus reverted consume paths accurately.
    /// @param callerA First arbitrary caller used to read `computeNonce`.
    /// @param callerB Second arbitrary caller used to read `computeNonce`.
    /// @param rawOperationType Fuzzed operation-type seed bounded into the valid enum range.
    /// @param operationData Fuzzed operation payload used to derive the nonce.
    /// @param salt Fuzzed salt used to derive the nonce.
    function testFuzz_FOSB_NONCE_34_computeNonceAndIsNonceUsed_remainCallerIndependentAndOutcomeConsistent(
        address callerA,
        address callerB,
        uint8 rawOperationType,
        bytes calldata operationData,
        uint256 salt
    ) public {
        // Setup: bound the operation type into the valid enum range and choose two distinct arbitrary readers.
        OperationType operationType =
            OperationType(bound(uint256(rawOperationType), 0, uint256(OperationType.AccountTransactionRejection)));
        vm.assume(callerA != callerB);

        // Call: compute the nonce from two caller contexts, then exercise reverted and successful consume paths.
        vm.prank(callerA);
        uint256 nonceFromCallerA = rollbackHarness.computeNonce(operationType, operationData, salt);

        vm.prank(callerB);
        uint256 nonceFromCallerB = rollbackHarness.computeNonce(operationType, operationData, salt);

        uint256 expected =
            uint256(keccak256(abi.encode(address(rollbackHarness), operationType, keccak256(operationData), salt)));

        vm.expectRevert(ForcedRollback.selector);
        rollbackHarness.consumeNonceAndRevert(nonceFromCallerA);
        bool afterRollback = rollbackHarness.isNonceUsed(nonceFromCallerA);

        rollbackHarness.consumeNonceViaLibrary(nonceFromCallerA);
        bool afterSuccess = rollbackHarness.isNonceUsed(nonceFromCallerA);

        // Verify: caller context does not affect nonce derivation, the wrapper matches the library formula, and
        // `isNonceUsed` tracks reverted versus successful consumption outcomes.
        assertEq(nonceFromCallerA, nonceFromCallerB, "nonce derivation should be caller-independent");
        assertEq(nonceFromCallerA, expected, "base wrapper should match the direct library formula");
        assertFalse(afterRollback, "reverted parent path should leave nonce usage false");
        assertTrue(afterSuccess, "successful consume should make nonce usage visible");
    }
}
