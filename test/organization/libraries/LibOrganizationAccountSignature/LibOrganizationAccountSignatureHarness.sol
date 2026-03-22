// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {LibOrganizationAccountSignature} from "organization/libraries/LibOrganizationAccountSignature.sol";
import {OrganizationPolicyStateHarness} from "test/organization/shared/OrganizationPolicyStateHarness.sol";
import {ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @dev Library-focused test harness for `LibOrganizationAccountSignature`.
 *      Exposes policy-signature validation entry points and internal helper wrappers.
 */
contract LibOrganizationAccountSignatureHarness is OrganizationPolicyStateHarness {
    /**
     * @dev Wrapper around `LibOrganizationAccountSignature.isValidSignature`.
     */
    function isValidSignatureViaLibrary(address account, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4)
    {
        (bool success, bytes memory result) =
            address(this).staticcall(abi.encodeCall(this.isValidSignatureUnsafe, (account, hash, signature)));

        if (!success || result.length < 32) {
            return SignatureUtils.ERC1271_INVALID_VALUE;
        }

        return abi.decode(result, (bytes4));
    }

    /**
     * @dev Raw wrapper around `LibOrganizationAccountSignature.isValidSignature`.
     */
    function isValidSignatureUnsafe(address account, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4)
    {
        return LibOrganizationAccountSignature.isValidSignature(account, hash, signature);
    }

    /**
     * @dev Wrapper around `_validateRecoverySignature`.
     */
    function validateRecoverySignatureViaLibrary(address account, bytes32 hash, bytes calldata signatureData)
        external
        view
        returns (bytes4)
    {
        return LibOrganizationAccountSignature._validateRecoverySignature(account, hash, signatureData);
    }

    /**
     * @dev Wrapper around `_getRecoverySignatureHash`.
     */
    function getRecoverySignatureHashViaLibrary(address account, bytes32 hash) external view returns (bytes32) {
        return LibOrganizationAccountSignature._getRecoverySignatureHash(account, hash);
    }

    /**
     * @dev Wrapper around `_validatePolicyBasedSignature`.
     */
    function validatePolicyBasedSignatureViaLibrary(address account, bytes32 hash, bytes calldata signatureData)
        external
        view
        returns (bytes4)
    {
        (bool success, bytes memory result) = address(this)
            .staticcall(abi.encodeCall(this.validatePolicyBasedSignatureUnsafe, (account, hash, signatureData)));

        if (!success || result.length < 32) {
            return SignatureUtils.ERC1271_INVALID_VALUE;
        }

        return abi.decode(result, (bytes4));
    }

    /**
     * @dev Raw wrapper around `_validatePolicyBasedSignature`.
     */
    function validatePolicyBasedSignatureUnsafe(address account, bytes32 hash, bytes calldata signatureData)
        external
        view
        returns (bytes4)
    {
        return LibOrganizationAccountSignature._validatePolicyBasedSignature(account, hash, signatureData);
    }

    /**
     * @dev Wrapper around `_isValidGuardianSignature`.
     */
    function isValidGuardianSignatureViaLibrary(bytes calldata guardianSignature, bytes32 messageHash)
        external
        view
        returns (bool)
    {
        return LibOrganizationAccountSignature._isValidGuardianSignature(guardianSignature, messageHash);
    }

    /**
     * @dev Wrapper around `_isERC1271SignatureAllowedByPolicy`.
     */
    function isERC1271SignatureAllowedByPolicyViaLibrary(
        address account,
        address initiator,
        uint256 policyId,
        ValidationProofs calldata proofs
    ) external view returns (bool) {
        ValidationProofs memory proofsMemory = proofs;
        return
            LibOrganizationAccountSignature._isERC1271SignatureAllowedByPolicy(
                account, initiator, policyId, proofsMemory
            );
    }

    /**
     * @dev Wrapper around `_getInitiatorSignatureHash`.
     */
    function getInitiatorSignatureHashViaLibrary(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp
    ) external view returns (bytes32) {
        return LibOrganizationAccountSignature._getInitiatorSignatureHash(account, hash, policyId, expirationTimestamp);
    }

    /**
     * @dev Wrapper around `_getReviewSignatureHash`.
     */
    function getReviewSignatureHashViaLibrary(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes calldata initiatorSignature
    ) external view returns (bytes32) {
        return LibOrganizationAccountSignature._getReviewSignatureHash(
            account, hash, policyId, expirationTimestamp, initiatorSignature
        );
    }
}
