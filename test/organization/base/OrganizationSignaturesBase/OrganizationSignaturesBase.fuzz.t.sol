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

    /// @dev Verifies `validateAndConsumeNonceOrRevert` flips a fresh nonce from `false` to `true` exactly once and
    /// reverts on replay with the exact nonce value.
    /// @param rawOperationType Fuzzed operation-type seed bounded into the valid enum range.
    /// @param operationData Fuzzed operation payload used to derive the nonce.
    /// @param salt Fuzzed salt used to derive the nonce.
    function testFuzz_validateAndConsumeNonce_consumesFreshNonceOnceAndRevertsOnReplay(
        uint8 rawOperationType,
        bytes calldata operationData,
        uint256 salt
    ) public {
        // Setup: derive one fresh nonce from the fuzzed tuple and confirm it starts unused.
        OperationType operationType =
            OperationType(bound(uint256(rawOperationType), 0, uint256(OperationType.AccountTransaction)));
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
    function testFuzz_validateAndConsumeNonce_rollsBackUsageWhenParentCallReverts(
        uint8 rawOperationType,
        bytes calldata operationData,
        uint256 salt
    ) public {
        // Setup: derive one fresh nonce from the rollback harness and confirm it starts unused.
        OperationType operationType =
            OperationType(bound(uint256(rawOperationType), 0, uint256(OperationType.AccountTransaction)));
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
}
