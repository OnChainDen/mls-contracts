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

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.members.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
