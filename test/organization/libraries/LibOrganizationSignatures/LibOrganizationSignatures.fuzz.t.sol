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
 * @dev Fuzz tests for `LibOrganizationSignatures`.
 */
contract LibOrganizationSignaturesFuzzTest is Test {
    /// @dev Library harness under test.
    LibOrganizationSignaturesHarness internal harness;

    /**
     * @dev Deploys a fresh library harness before each test.
     */
    function setUp() public {
        harness = new LibOrganizationSignaturesHarness();
    }

    /// @dev Verifies changing `operationType`, `operationData`, or `salt` always changes the computed nonce.
    /// @param rawOperationType Fuzzed operation type seed bounded into the valid enum range.
    /// @param operationData Fuzzed baseline operation payload.
    /// @param salt Fuzzed baseline salt.
    function testFuzz_FLOS_NONCE_30_computeNonce_isSensitiveToEveryBoundField(
        uint8 rawOperationType,
        bytes calldata operationData,
        uint256 salt
    ) public {
        // Setup: choose one valid operation type plus guaranteed-different mutations for type, data, and salt.
        uint256 operationTypeCount = uint256(OperationType.AccountTransactionRejection) + 1;
        OperationType operationType = OperationType(bound(uint256(rawOperationType), 0, operationTypeCount - 1));
        OperationType differentOperationType = OperationType((uint256(operationType) + 1) % operationTypeCount);
        bytes memory differentOperationData = abi.encodePacked(operationData, bytes1(uint8(1)));
        uint256 differentSalt = salt == type(uint256).max ? salt - 1 : salt + 1;

        // Call: compute the nonce once for the baseline tuple and once for each single-field mutation.
        uint256 baseline = harness.computeNonceViaLibrary(operationType, operationData, salt);
        uint256 differentType = harness.computeNonceViaLibrary(differentOperationType, operationData, salt);
        uint256 differentData = harness.computeNonceViaLibrary(operationType, differentOperationData, salt);
        uint256 differentSaltNonce = harness.computeNonceViaLibrary(operationType, operationData, differentSalt);

        // Verify: mutating any bound input should move the nonce into a different replay domain.
        assertTrue(baseline != differentType, "operation type should affect nonce derivation");
        assertTrue(baseline != differentData, "operation data should affect nonce derivation");
        assertTrue(baseline != differentSaltNonce, "salt should affect nonce derivation");
    }

    /// @dev Verifies the same nonce tuple on different organization addresses always produces different nonces.
    /// @param rawOperationType Fuzzed operation type seed bounded into the valid enum range.
    /// @param operationData Fuzzed operation payload reused across both organizations.
    /// @param salt Fuzzed salt reused across both organizations.
    function testFuzz_FLOS_NONCE_31_computeNonce_isolatedAcrossOrganizations(
        uint8 rawOperationType,
        bytes calldata operationData,
        uint256 salt
    ) public {
        // Setup: deploy a second harness so the same tuple executes under a different organization address.
        uint256 operationTypeCount = uint256(OperationType.AccountTransactionRejection) + 1;
        OperationType operationType = OperationType(bound(uint256(rawOperationType), 0, operationTypeCount - 1));
        LibOrganizationSignaturesHarness otherHarness = new LibOrganizationSignaturesHarness();

        // Call: compute the same nonce tuple on both harnesses.
        uint256 nonceA = harness.computeNonceViaLibrary(operationType, operationData, salt);
        uint256 nonceB = otherHarness.computeNonceViaLibrary(operationType, operationData, salt);

        // Verify: the organization address should isolate nonce space.
        assertTrue(nonceA != nonceB, "different organization addresses should isolate nonce space");
    }

    /// @dev Verifies nonce consumption is monotonic from `false -> true` and any replay attempt reverts.
    /// @param rawOperationType Fuzzed operation type seed bounded into the valid enum range.
    /// @param operationData Fuzzed operation payload used to derive the nonce.
    /// @param salt Fuzzed salt used to derive the nonce.
    function testFuzz_FLOS_NONCE_32_validateAndConsumeNonce_monotonicAndReplayProtected(
        uint8 rawOperationType,
        bytes calldata operationData,
        uint256 salt
    ) public {
        // Setup: derive one fresh nonce from a fuzzed valid operation tuple.
        uint256 operationTypeCount = uint256(OperationType.AccountTransactionRejection) + 1;
        OperationType operationType = OperationType(bound(uint256(rawOperationType), 0, operationTypeCount - 1));
        uint256 nonce = harness.computeNonceViaLibrary(operationType, operationData, salt);
        assertFalse(harness.isNonceUsedViaLibrary(nonce), "fresh nonce should start unused");

        // Call: consume the nonce once, then attempt to replay it.
        harness.validateAndConsumeNonceOrRevertViaLibrary(nonce);
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        harness.validateAndConsumeNonceOrRevertViaLibrary(nonce);

        // Verify: the first consume flips the nonce to used and the replay path cannot unset it.
        assertTrue(harness.isNonceUsedViaLibrary(nonce), "consumed nonce should remain marked used");
    }

    /// @dev Verifies a parent transaction revert rolls back nonce consumption entirely.
    /// @param rawOperationType Fuzzed operation type seed bounded into the valid enum range.
    /// @param operationData Fuzzed operation payload used to derive the nonce.
    /// @param salt Fuzzed salt used to derive the nonce.
    function testFuzz_FLOS_ROLL_33_failedParentTransaction_rollsBackNonceConsumption(
        uint8 rawOperationType,
        bytes calldata operationData,
        uint256 salt
    ) public {
        // Setup: derive one fresh nonce from a fuzzed valid operation tuple.
        uint256 operationTypeCount = uint256(OperationType.AccountTransactionRejection) + 1;
        OperationType operationType = OperationType(bound(uint256(rawOperationType), 0, operationTypeCount - 1));
        uint256 nonce = harness.computeNonceViaLibrary(operationType, operationData, salt);

        // Call: consume the nonce inside a parent transaction that deliberately reverts.
        (bool success, bytes memory revertData) =
            address(harness).call(abi.encodeCall(harness.validateAndConsumeNonceThenRevertViaLibrary, (nonce)));

        // Verify: the forced parent revert should leave the nonce unused.
        assertFalse(success, "forced rollback path should revert");
        assertEq(
            bytes4(revertData),
            LibOrganizationSignaturesHarness.ForcedRollback.selector,
            "forced rollback path should revert with the harness error"
        );
        assertFalse(harness.isNonceUsedViaLibrary(nonce), "parent revert should roll back nonce consumption");
    }
}
