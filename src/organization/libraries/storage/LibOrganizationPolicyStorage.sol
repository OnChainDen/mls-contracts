// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title Organization Policy Storage
 * @dev ERC-7201 namespaced storage for merkle-based policy functionality.
 *      Policies are stored in a global merkle tree. Only the root is stored on-chain.
 *      Full policy data is stored off-chain (IPFS) and provided via calldata at validation time.
 * @author Den Technologies Inc
 */
library LibOrganizationPolicyStorage {
    /**
     * @dev Storage layout for policy functionality
     * @custom:storage-location erc7201:den.mls-wallet.organization.policy
     * @param policiesRoot Global merkle root containing ALL policies.
     *        Each leaf is hash(policyId, Policy struct)
     * @param policyUsage Time-based usage tracking: usageKey => timeWindow => usedAmount/count.
     *        usageKey is computed from policyId and scoped entities (account, destination, initiator)
     */
    struct Layout {
        bytes32 policiesRoot;
        mapping(bytes32 => mapping(uint256 => uint256)) policyUsage;
    }

    /// @dev Storage location for PolicyStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.policy")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.policy"`
    bytes32 internal constant STORAGE_LOCATION = 0x3dd17025b978cb0623dedaddffeab8b6f146372bd98577f4daffa1ab83af1c00;

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
