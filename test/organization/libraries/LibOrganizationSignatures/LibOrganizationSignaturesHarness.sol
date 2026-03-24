// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationSignatures} from "organization/libraries/LibOrganizationSignatures.sol";
import {LibOrganizationSignaturesStorage} from "organization/libraries/storage/LibOrganizationSignaturesStorage.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Library-focused harness exposing nonce helpers from `LibOrganizationSignatures`.
 */
contract LibOrganizationSignaturesHarness {
    /// @dev Error used to force a state-reverting parent transaction after nonce consumption.
    error ForcedRollback();

    /**
     * @dev Exposes `LibOrganizationSignatures.validateAndConsumeNonceOrRevert`.
     * @param nonce The nonce to validate and consume.
     */
    function validateAndConsumeNonceOrRevertViaLibrary(uint256 nonce) external {
        LibOrganizationSignatures.validateAndConsumeNonceOrRevert(nonce);
    }

    /**
     * @dev Consumes a nonce through the library and then reverts the parent transaction.
     * @param nonce The nonce to validate and consume before reverting.
     */
    function validateAndConsumeNonceThenRevertViaLibrary(uint256 nonce) external {
        LibOrganizationSignatures.validateAndConsumeNonceOrRevert(nonce);
        revert ForcedRollback();
    }

    /**
     * @dev Exposes `LibOrganizationSignatures.isNonceUsed`.
     * @param nonce The nonce to query.
     * @return isUsed True when the nonce has already been consumed.
     */
    function isNonceUsedViaLibrary(uint256 nonce) external view returns (bool isUsed) {
        return LibOrganizationSignatures.isNonceUsed(nonce);
    }

    /**
     * @dev Exposes `LibOrganizationSignatures.computeNonce`.
     * @param operationType The operation domain used for nonce binding.
     * @param operationData The ABI-encoded operation payload.
     * @param salt The caller-provided replay salt.
     * @return nonce The computed deterministic nonce.
     */
    function computeNonceViaLibrary(OperationType operationType, bytes calldata operationData, uint256 salt)
        external
        view
        returns (uint256 nonce)
    {
        return LibOrganizationSignatures.computeNonce(operationType, operationData, salt);
    }

    /**
     * @dev Writes the raw used-nonce flag for test setup.
     * @param nonce The nonce to mutate.
     * @param isUsed The value to store.
     */
    function setUsedNonce(uint256 nonce, bool isUsed) external {
        LibOrganizationSignaturesStorage.layout().usedNonces[nonce] = isUsed;
    }
}
