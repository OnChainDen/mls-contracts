// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {LibOrganizationSignaturesStorage} from "organization/libraries/storage/LibOrganizationSignaturesStorage.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @title Lib Organization Signatures
 * @dev Library for signature and nonce-related operations for Organization contracts.
 *      This library handles nonce management for all operation types (admin operations and account transactions).
 * @author Den Technologies Inc
 */
library LibOrganizationSignatures {
    /**
     * @dev Validates that a nonce has not been used and marks it as used.
     *      Reverts if the nonce has already been used.
     * @param nonce The nonce to validate and consume
     */
    function validateAndConsumeNonceOrRevert(uint256 nonce) internal {
        LibOrganizationSignaturesStorage.Layout storage sigLayout = LibOrganizationSignaturesStorage.layout();

        if (sigLayout.usedNonces[nonce]) {
            revert IOrganizationSignatures.NonceAlreadyUsed(nonce);
        }

        sigLayout.usedNonces[nonce] = true;
    }

    /**
     * @dev Checks if a nonce has been used
     * @param nonce The nonce to check
     * @return True if the nonce has been used, false otherwise
     */
    function isNonceUsed(uint256 nonce) internal view returns (bool) {
        return LibOrganizationSignaturesStorage.layout().usedNonces[nonce];
    }

    /**
     * @notice Computes a deterministic nonce from operation data and salt
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @return The computed nonce
     */
    function computeNonce(OperationType operationType, bytes memory operationData, uint256 salt)
        internal
        view
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(address(this), operationType, keccak256(operationData), salt)));
    }
}
