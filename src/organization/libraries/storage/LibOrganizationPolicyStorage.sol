// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Policies } from "../../libraries/Policies.sol";

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
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.policy.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
