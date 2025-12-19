// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Policies } from "../../../libraries/Policies.sol";

/**
 * @title Organization Policy Storage
 * @notice Storage layout for organization policy functionality
 * @author Den Technologies Inc
 */
library LibOrganizationPolicyStorage {
    struct Layout {
        mapping(uint256 => Policies.Policy) policies;
        mapping(uint256 => bool) policyExists;
        uint256 nextPolicyId;
        // Time-based usage tracking: usageKey => timeWindow => usedAmount/count
        // usageKey is computed from policyId and scoped entities (account, destination, initiator)
        mapping(bytes32 => mapping(uint256 => uint256)) policyUsage;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.policy.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
