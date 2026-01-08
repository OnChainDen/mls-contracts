// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Groups Storage
 * @notice Minimal storage layout for merkle-based groups functionality
 * @dev Groups are stored in a nested merkle tree. Only the root is stored on-chain.
 *      Full group data is stored off-chain (IPFS) and provided via calldata at validation time.
 *      Each group leaf is hash(hash(groupId, groupMembersRoot)) where groupMembersRoot is
 *      a separate merkle tree containing the member addresses in that group.
 * @author Den Technologies Inc
 */
library LibOrganizationGroupsStorage {
    struct Layout {
        /// @notice Global merkle root containing ALL groups
        /// @dev Each leaf is hash(hash(groupId, groupMembersRoot))
        bytes32 groupsRoot;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.groups.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
