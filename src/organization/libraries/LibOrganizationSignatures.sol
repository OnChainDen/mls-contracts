// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationSignaturesStorage } from "./storage/LibOrganizationSignaturesStorage.sol";
import { OperationType } from "../../interfaces/IOrganization.sol";

/**
 * @title Lib Organization Signatures
 * @notice Library for signature and nonce-related operations for Organization contracts
 * @dev This library handles nonce management for all operation types (admin operations and account transactions)
 * @author Den Technologies Inc
 */
library LibOrganizationSignatures {
    /**
     * @notice Emitted when an operation uses a nonce that has already been used
     * @param nonce The nonce that was attempted to be used
     */
    error NonceAlreadyUsed(uint256 nonce);

    /**
     * @notice Checks if a nonce has been used
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
    function computeNonce(
        OperationType operationType,
        bytes memory operationData,
        uint256 salt
    )
        internal
        view
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(address(this), operationType, keccak256(operationData), salt)));
    }

    /**
     * @notice Validates that a nonce has not been used and marks it as used
     * @dev This function will revert if the nonce has already been used
     * @param nonce The nonce to validate and consume
     */
    function validateAndConsumeNonce(uint256 nonce) internal {
        LibOrganizationSignaturesStorage.Layout storage sigLayout = LibOrganizationSignaturesStorage.layout();

        if (sigLayout.usedNonces[nonce]) {
            revert NonceAlreadyUsed(nonce);
        }

        sigLayout.usedNonces[nonce] = true;
    }

    /**
     * @notice Extracts the signer address from a signature
     * @dev Assumes the first 20 bytes of the signature contain the signer address (ERC-1271 pattern)
     * @param signature The signature to extract the signer from
     * @return The signer address, or address(0) if invalid
     */
    function extractSigner(bytes memory signature) internal pure returns (address) {
        if (signature.length < 20) {
            return address(0);
        }

        address signer;
        /* solhint-disable no-inline-assembly */
        assembly {
            signer := mload(add(signature, 20))
        }
        return signer;
    }
}
