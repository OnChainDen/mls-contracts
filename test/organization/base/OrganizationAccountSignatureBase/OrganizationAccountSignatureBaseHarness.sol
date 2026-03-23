// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationAccountSignatureBase} from "organization/base/OrganizationAccountSignatureBase.sol";
import {LibOrganizationAccountSignature} from "organization/libraries/LibOrganizationAccountSignature.sol";
import {OrganizationPolicyStateHarness} from "test/organization/shared/OrganizationPolicyStateHarness.sol";

/**
 * @dev Base-contract-focused test harness for `OrganizationAccountSignatureBase`.
 *      Combines shared policy/account state setters with real external base-contract entry points.
 */
contract OrganizationAccountSignatureBaseHarness is OrganizationPolicyStateHarness, OrganizationAccountSignatureBase {
    /**
     * @dev Exposes `_getInitiatorSignatureHash` for external-base-path fixtures.
     * @param account The account bound into the hash.
     * @param hash The message hash.
     * @param policyId The policy id.
     * @param expirationTimestamp The expiration timestamp.
     * @return signatureHash The computed initiator hash.
     */
    function getInitiatorSignatureHashViaLibrary(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp
    ) external view returns (bytes32 signatureHash) {
        return LibOrganizationAccountSignature._getInitiatorSignatureHash(account, hash, policyId, expirationTimestamp);
    }

    /**
     * @dev Exposes `_getReviewSignatureHash` for external-base-path fixtures.
     * @param account The account bound into the hash.
     * @param hash The message hash.
     * @param policyId The policy id.
     * @param expirationTimestamp The expiration timestamp.
     * @param initiatorSignature The initiator signature bytes.
     * @return signatureHash The computed review hash.
     */
    function getReviewSignatureHashViaLibrary(
        address account,
        bytes32 hash,
        uint256 policyId,
        uint256 expirationTimestamp,
        bytes calldata initiatorSignature
    ) external view returns (bytes32 signatureHash) {
        return LibOrganizationAccountSignature._getReviewSignatureHash(
            account, hash, policyId, expirationTimestamp, initiatorSignature
        );
    }

    /**
     * @dev Exposes `_getRecoverySignatureHash` for external-base-path fixtures.
     * @param account The account bound into the hash.
     * @param hash The message hash.
     * @param expirationTimestamp The expiration timestamp.
     * @return signatureHash The computed recovery hash.
     */
    function getRecoverySignatureHashViaLibrary(address account, bytes32 hash, uint256 expirationTimestamp)
        external
        view
        returns (bytes32 signatureHash)
    {
        return LibOrganizationAccountSignature._getRecoverySignatureHash(account, hash, expirationTimestamp);
    }
}
