// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Guardian Facet Storage
 * @notice Storage layout for the OrganizationGuardianFacet
 * @author Den Technologies Inc
 */
library OrganizationGuardianFacetStorage {
    struct Layout {
        address guardian;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.guardian.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
