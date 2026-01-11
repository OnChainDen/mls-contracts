// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibOrganizationAdmin} from "../organization/libraries/LibOrganizationAdmin.sol";

/**
 * @title IUpgradeable
 * @notice Interface for upgradeable contracts with authorization
 * @author Den Technologies Inc
 */
interface IUpgradeable {
    /**
     * @notice Upgrade the implementation to a new address with authorization
     * @param newImplementation The new implementation address
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param signatures The signatures from admin(s) authorizing this upgrade
     * @param adminProofs The Merkle proofs for admin membership verification
     */
    function upgradeToWithAuthorization(
        address newImplementation,
        uint256 salt,
        uint256 expirationTimestamp,
        bytes calldata signatures,
        LibOrganizationAdmin.AdminProofs calldata adminProofs
    ) external;

    /**
     * @notice Upgrade the implementation to a new address and call a function with authorization
     * @param newImplementation The new implementation address
     * @param data The calldata to call on the new implementation
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param signatures The signatures from admin(s) authorizing this upgrade
     * @param adminProofs The Merkle proofs for admin membership verification
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
