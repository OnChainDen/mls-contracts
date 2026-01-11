// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibOrganizationAdmin} from "../organization/libraries/LibOrganizationAdmin.sol";

/**
 * @title IUpgradeable
 * @notice Interface for upgradeable contracts with admin-authorized upgrades
 * @dev Contracts implementing this interface use a multi-signature authorization pattern
 *      where admin signatures + merkle proofs are required to authorize an upgrade.
 *      This is designed for use with UUPS-style proxy patterns.
 * @author Den Technologies Inc
 */
interface IUpgradeable {
    /**
     * @notice Upgrade the implementation to a new address and optionally call a function
     * @dev This is the only authorized upgrade path. Pass empty bytes for `data` if no
     *      post-upgrade initialization call is needed.
     *
     *      Authorization requirements:
     *      1. Caller must be authorized (e.g., guardian)
     *      2. Admin signatures must meet the voting threshold
     *      3. New implementation must be on the whitelist
     *
     * @param newImplementation The new implementation address (must be whitelisted)
     * @param data Optional calldata to execute on the new implementation after upgrade.
     *             Pass empty bytes ("") if no post-upgrade call is needed.
     * @param salt A user-provided salt for nonce computation (prevents replay attacks)
     * @param expirationTimestamp The timestamp after which the admin signatures are no longer valid
     * @param signatures The concatenated signatures from admin(s) authorizing this upgrade
     * @param adminProofs The Merkle proofs verifying the signers are admins
     */
    function upgradeToAndCallWithAuthorization(
        address newImplementation,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        bytes calldata signatures,
        LibOrganizationAdmin.AdminProofs calldata adminProofs
    ) external;
}
