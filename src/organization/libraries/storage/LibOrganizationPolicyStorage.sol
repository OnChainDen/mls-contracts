// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Policy Storage
 * @notice Minimal storage layout for merkle-based policy functionality
 * @dev Policies are stored in a global merkle tree. Only the root is stored on-chain.
 *      Full policy data is stored off-chain (IPFS) and provided via calldata at validation time.
 * @author Den Technologies Inc
 */
library LibOrganizationPolicyStorage {
    struct Layout {
        /// @notice Global merkle root containing ALL policies
        /// @dev Each leaf is hash(policyId, Policy struct)
        bytes32 policiesRoot;
        /// @notice Time-based usage tracking: usageKey => timeWindow => usedAmount/count
        /// @dev usageKey is computed from policyId and scoped entities (account, destination, initiator)
        mapping(bytes32 => mapping(uint256 => uint256)) policyUsage;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("onchain.custody.organization.policy.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
