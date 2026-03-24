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

    /// @dev Verifies nonce consumption is monotonic from `false -> true` and any replay attempt reverts.
    /// @param rawOperationType Fuzzed operation type seed bounded into the valid enum range.
    /// @param operationData Fuzzed operation payload used to derive the nonce.
    /// @param salt Fuzzed salt used to derive the nonce.
    function testFuzz_validateAndConsumeNonce_monotonicAndReplayProtected(
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
    function testFuzz_failedParentTransaction_rollsBackNonceConsumption(
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
        // casting to bytes4 is safe because revertData always starts with a 4-byte selector
        // forge-lint: disable-next-item(unsafe-typecast)
        assertEq(
            bytes4(revertData),
            LibOrganizationSignaturesHarness.ForcedRollback.selector,
            "forced rollback path should revert with the harness error"
        );
        assertFalse(harness.isNonceUsedViaLibrary(nonce), "parent revert should roll back nonce consumption");
    }
}
