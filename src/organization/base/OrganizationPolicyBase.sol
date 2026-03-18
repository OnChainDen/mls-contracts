// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationPolicy} from "organization/libraries/LibOrganizationPolicy.sol";
import {LibOrganizationPolicyStorage} from "organization/libraries/storage/LibOrganizationPolicyStorage.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";
import {Policy} from "types/PolicyTypes.sol";

/**
 * @title OrganizationPolicyBase
 * @dev Abstract contract implementing IOrganizationPolicy.
 *      Handles policy management operations including setting policies and querying policy usage.
 * @author Den Technologies Inc
 */
abstract contract OrganizationPolicyBase is OrganizationModifiers, IOrganizationPolicy {
    /// @inheritdoc IOrganizationPolicy
    function setPolicies(bytes32 newPoliciesRoot, string calldata ipfsCid, AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newPoliciesRoot, keccak256(bytes(ipfsCid)));

        // Validate that the current admin has authorized this operation (isApproval = true for execution)
        uint256 nonce = LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyPolicies,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Execute via low-level self-call so that a revert does not bubble up.
        /* solhint-disable avoid-low-level-calls */
        // slither-disable-next-line low-level-calls,reentrancy-events
        (bool success, bytes memory revertData) =
            address(this).call(abi.encodeCall(this.executeSetPolicies, (newPoliciesRoot, ipfsCid)));
        /* solhint-enable avoid-low-level-calls */

        if (!success) {
            emit IOrganizationAdmin.AdminOperationExecutionReverted(OperationType.ModifyPolicies, nonce, revertData);
        }
    }

    /// @inheritdoc IOrganizationPolicy
    function executeSetPolicies(bytes32 newPoliciesRoot, string calldata ipfsCid) external override onlySelf {
        LibOrganizationPolicy.setPolicies(newPoliciesRoot, ipfsCid);
    }

    /// @inheritdoc IOrganizationPolicy
    function policiesRoot() external view override returns (bytes32) {
        return LibOrganizationPolicyStorage.layout().policiesRoot;
    }

    /// @inheritdoc IOrganizationPolicy
    function getPolicyUsage(
        uint256 policyId,
        Policy calldata policy,
        address account,
        address destination,
        address initiator,
        bytes32[] calldata policyProof
    ) external view override returns (uint256) {
        // Verify policy exists in merkle tree
        if (!LibOrganizationPolicy.isPolicyInOrg(policyId, policy, policyProof)) {
            revert PolicyVerificationFailed(policyId);
        }

        return LibOrganizationPolicy.getCurrentUsage({
            policyId: policyId, policy: policy, account: account, destination: destination, initiator: initiator
        });
    }
}
