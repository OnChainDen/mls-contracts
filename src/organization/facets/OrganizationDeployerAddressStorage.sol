// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Deployer Address Storage
 * @notice Storage layout for the deployer address used in organization initialization
 * @author Den Technologies Inc
 */
library OrganizationDeployerAddressStorage {
    struct Layout {
        address deployerAddress; // Address authorized for post-deployment initialization
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.deployer.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
