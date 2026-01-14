// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Groups Storage
 * @dev ERC-7201 namespaced storage for merkle-based groups functionality.
 *      Groups are stored in a nested merkle tree. Only the root is stored on-chain.
 *      Full group data is stored off-chain (IPFS) and provided via calldata at validation time.
 *      Each group leaf is hash(hash(groupId, groupMembersRoot)) where groupMembersRoot is
 *      a separate merkle tree containing the member addresses in that group.
 * @author Den Technologies Inc
 */
library LibOrganizationGroupsStorage {
    /**
     * @dev Storage layout for groups functionality
     * @custom:storage-location erc7201:den.mls-wallet.organization.groups
     * @param groupsRoot Global merkle root containing ALL groups.
     *        Each leaf is hash(hash(groupId, groupMembersRoot))
     */
    struct Layout {
        bytes32 groupsRoot;
    }

    /// @dev Storage location for GroupsStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.groups")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.groups"`
    bytes32 internal constant STORAGE_LOCATION = 0xf9619a082569050ac05ceff986096b3369f62becb728f8c488e07241ae3e2300;

    /**
     * @dev Returns the storage layout at the namespaced slot
     * @return _layout The storage layout struct
     */
    function layout() internal pure returns (Layout storage _layout) {
        assembly {
            _layout.slot := STORAGE_LOCATION
        }
    }
}
