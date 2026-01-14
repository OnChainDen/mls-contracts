// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Members Storage
 * @dev ERC-7201 namespaced storage for merkle-based members functionality.
 *      Members are stored in a merkle tree. Only the root is stored on-chain.
 *      Full member data is stored off-chain (IPFS) and provided via calldata at validation time.
 * @author Den Technologies Inc
 */
library LibOrganizationMembersStorage {
    /**
     * @dev Storage layout for members functionality
     * @custom:storage-location erc7201:den.mls-wallet.organization.members
     * @param membersRoot Global merkle root containing ALL members.
     *        Each leaf is hash(hash(memberAddress))
     */
    struct Layout {
        bytes32 membersRoot;
    }

    /// @dev Storage location for MembersStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.members")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.members"`
    bytes32 internal constant STORAGE_LOCATION = 0xb80799cfa22e7d42bb36b2b397b5d0bd56930d54ee4f345397b8ece603c6f300;

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
