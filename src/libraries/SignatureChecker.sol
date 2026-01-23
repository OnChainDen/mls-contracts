// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
// Adapted from OpenZeppelin Contracts v5.4.0 (utils/cryptography/SignatureChecker.sol)
// Removed ERC-7913 support to avoid Bytes.sol dependency which uses mcopy (Cancun opcode)

pragma solidity 0.8.33;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title SignatureChecker
 * @dev Signature verification helper that can be used instead of `ECDSA.recover` to seamlessly support:
 *      - ECDSA signatures from externally owned accounts (EOAs)
 *      - ERC-1271 signatures from smart contract wallets like Argent and Safe Wallet (previously Gnosis Safe)
 *
 *      This is a minimal version adapted from OpenZeppelin, without ERC-7913 support to avoid
 *      the Bytes.sol dependency which uses the mcopy opcode (Cancun). This allows compilation
 *      with Paris EVM version for cross-chain bytecode compatibility.
 *
 * @author OpenZeppelin (original), Den Technologies Inc (adaptation)
 */
library SignatureChecker {
    /**
     * @dev Checks if a signature is valid for a given signer and data hash. If the signer has code, the
     *      signature is validated against it using ERC-1271, otherwise it's validated using `ECDSA.recover`.
     *
     *      NOTE: Unlike ECDSA signatures, contract signatures are revocable, and the outcome of this function
     *      can thus change through time. It could return true at block N and false at block N+1 (or the opposite).
     */
    function isValidSignatureNow(address signer, bytes32 hash, bytes memory signature) internal view returns (bool) {
        if (signer.code.length == 0) {
            (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
            return err == ECDSA.RecoverError.NoError && recovered == signer;
        } else {
            return isValidERC1271SignatureNow(signer, hash, signature);
        }
    }

    /**
     * @dev Checks if a signature is valid for a given signer and data hash. The signature is validated
     *      against the signer smart contract using ERC-1271.
     *
     *      NOTE: Unlike ECDSA signatures, contract signatures are revocable, and the outcome of this function
     *      can thus change through time. It could return true at block N and false at block N+1 (or the opposite).
     */
    function isValidERC1271SignatureNow(address signer, bytes32 hash, bytes memory signature)
        internal
        view
        returns (bool)
    {
        (bool success, bytes memory result) =
            signer.staticcall(abi.encodeCall(IERC1271.isValidSignature, (hash, signature)));
        return (success && result.length >= 32
                && abi.decode(result, (bytes32)) == bytes32(IERC1271.isValidSignature.selector));
    }
}
