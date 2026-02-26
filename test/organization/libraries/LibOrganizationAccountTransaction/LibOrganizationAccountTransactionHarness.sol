// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationAccountTransaction} from "organization/libraries/LibOrganizationAccountTransaction.sol";
import {OrganizationPolicyStateHarness} from "test/organization/shared/OrganizationPolicyStateHarness.sol";
import {Policy, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @dev Library-focused test harness for `LibOrganizationAccountTransaction`.
 *      Exposes entry points and internal helper wrappers for policy-coupled transaction validation.
 */
contract LibOrganizationAccountTransactionHarness is OrganizationPolicyStateHarness {
    /**
     * @dev Wrapper around `validateTransactionApprovalOrRevert`.
     */
    function validateTransactionApprovalOrRevertViaLibrary(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata initiatorSignature,
        bytes calldata reviewSignatures,
        ValidationProofs calldata proofs
    ) external {
        LibOrganizationAccountTransaction.validateTransactionApprovalOrRevert(
            account, to, value, data, salt, expirationTimestamp, policyId, initiatorSignature, reviewSignatures, proofs
        );
    }

    /**
     * @dev Wrapper around `validateTransactionRejectionOrRevert`.
     */
    function validateTransactionRejectionOrRevertViaLibrary(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata initiatorSignature,
        bytes calldata reviewSignatures,
        ValidationProofs calldata proofs
    ) external view {
        LibOrganizationAccountTransaction.validateTransactionRejectionOrRevert(
            account, to, value, data, salt, expirationTimestamp, policyId, initiatorSignature, reviewSignatures, proofs
        );
    }

    /**
     * @dev Wrapper around `_validateAndUpdateRateLimitOrRevert`.
     */
    function validateAndUpdateRateLimitOrRevertViaLibrary(
        address account,
        address to,
        uint256 value,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata data,
        address initiator,
        Policy calldata policy
    ) external {
        LibOrganizationAccountTransaction.TxParams memory params =
            LibOrganizationAccountTransaction.TxParams({
                account: account,
                to: to,
                value: value,
                salt: salt,
                expirationTimestamp: expirationTimestamp,
                policyId: policyId
            });
        LibOrganizationAccountTransaction._validateAndUpdateRateLimitOrRevert(params, data, initiator, policy);
    }

    /**
     * @dev Wrapper around `_validateAutoApproveRejectionOrRevert`.
     */
    function validateAutoApproveRejectionOrRevertViaLibrary(
        address account,
        address to,
        uint256 value,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata data,
        bytes calldata reviewSignatures,
        ValidationProofs calldata proofs
    ) external view {
        LibOrganizationAccountTransaction.TxParams memory params =
            LibOrganizationAccountTransaction.TxParams({
                account: account,
                to: to,
                value: value,
                salt: salt,
                expirationTimestamp: expirationTimestamp,
                policyId: policyId
            });
        LibOrganizationAccountTransaction._validateAutoApproveRejectionOrRevert(params, data, reviewSignatures, proofs);
    }

    /**
     * @dev Wrapper around `_validateManualConfirmationOrRevert`.
     */
    function validateManualConfirmationOrRevertViaLibrary(
        address account,
        address to,
        uint256 value,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata data,
        bytes calldata reviewSignatures,
        bytes calldata initiatorSignature,
        ValidationProofs calldata proofs,
        bool isApproval
    ) external view {
        LibOrganizationAccountTransaction.TxParams memory params =
            LibOrganizationAccountTransaction.TxParams({
                account: account,
                to: to,
                value: value,
                salt: salt,
                expirationTimestamp: expirationTimestamp,
                policyId: policyId
            });
        LibOrganizationAccountTransaction._validateManualConfirmationOrRevert(
            params, data, reviewSignatures, initiatorSignature, proofs, isApproval
        );
    }

    /**
     * @dev Wrapper around `_computeInitiatorHashFromParams`.
     */
    function computeInitiatorHashFromParamsViaLibrary(
        address account,
        address to,
        uint256 value,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata data,
        bool isApproval
    ) external view returns (bytes32) {
        LibOrganizationAccountTransaction.TxParams memory params =
            LibOrganizationAccountTransaction.TxParams({
                account: account,
                to: to,
                value: value,
                salt: salt,
                expirationTimestamp: expirationTimestamp,
                policyId: policyId
            });
        return LibOrganizationAccountTransaction._computeInitiatorHashFromParams(params, data, isApproval);
    }

    /**
     * @dev Wrapper around `_computeReviewHashFromParams`.
     */
    function computeReviewHashFromParamsViaLibrary(
        address account,
        address to,
        uint256 value,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata data,
        bool isApproval,
        bytes calldata initiatorSignature
    ) external view returns (bytes32) {
        LibOrganizationAccountTransaction.TxParams memory params =
            LibOrganizationAccountTransaction.TxParams({
                account: account,
                to: to,
                value: value,
                salt: salt,
                expirationTimestamp: expirationTimestamp,
                policyId: policyId
            });
        return
            LibOrganizationAccountTransaction._computeReviewHashFromParams(params, data, isApproval, initiatorSignature);
    }
}
