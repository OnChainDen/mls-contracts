// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Members Storage
 * @notice Minimal storage layout for merkle-based members functionality
 * @dev Members are stored in a merkle tree. Only the root is stored on-chain.
 *      Full member data is stored off-chain (IPFS) and provided via calldata at validation time.
 * @author Den Technologies Inc
 */
library LibOrganizationMembersStorage {
    struct Layout {
        /// @notice Global merkle root containing ALL members
        /// @dev Each leaf is hash(hash(memberAddress))
        bytes32 membersRoot;
    }

    /// @dev Storage slot for the members storage layout, computed as
    /// keccak256("onchain.custody.organization.members.storage")
    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.members.storage");

    /**
     * @notice Returns the storage layout at the namespaced slot
     * @dev Uses assembly to access storage at the precomputed slot
     * @return _layout The storage layout struct
     */
    function layout() internal pure returns (Layout storage _layout) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            _layout.slot := slot
        }
    }
}
