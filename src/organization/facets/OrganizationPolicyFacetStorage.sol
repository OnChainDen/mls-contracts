// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Policies } from "../../libraries/Policies.sol";

/**
 * @title Organization Policy Facet Storage
 * @notice Storage layout for the OrganizationPolicyFacet
 * @author Den Technologies Inc
 */
library OrganizationPolicyFacetStorage {
    struct Layout {
        Policies.Policy[] policies;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.policy.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
