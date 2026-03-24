// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OperationType} from "types/CommonTypes.sol";

/**
 * @title IOrganizationSignatures
 * @notice Interface for signature and nonce-related operations in Organization contracts
 * @dev Maps to LibOrganizationSignatures library functionality
 * @author Den Technologies Inc
 */
interface IOrganizationSignatures {
    // ═══════════════════════════════════════════════════════════════════════════
    // Errors
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Thrown when a nonce has already been used
     * @param nonce The nonce that was already used
     */
    error NonceAlreadyUsed(uint256 nonce);

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Checks if a nonce has already been used
     * @param nonce The nonce to check
     * @return True if the nonce has been used, false otherwise
     */
    function isNonceUsed(uint256 nonce) external view returns (bool);

    /**
     * @notice Computes the nonce for a given operation
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @return The computed nonce
     */
    function computeNonce(OperationType operationType, bytes calldata operationData, uint256 salt)
        external
        view
        returns (uint256);
}
