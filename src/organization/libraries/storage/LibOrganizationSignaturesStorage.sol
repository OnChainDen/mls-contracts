// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title Organization Signatures Storage
 * @dev ERC-7201 namespaced storage for organization signature and nonce functionality.
 *      Used for all operation types (admin operations and account transactions).
 * @author Den Technologies Inc
 */
library LibOrganizationSignaturesStorage {
    /**
     * @dev Storage layout for signature nonce tracking
     * @custom:storage-location erc7201:den.mls-wallet.organization.signatures
     * @param usedNonces Mapping of nonces that have been consumed (nonce => used)
     */
    struct Layout {
        mapping(uint256 => bool) usedNonces;
    }

    /// @dev Storage location for SignaturesStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.signatures")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.signatures"`
    bytes32 internal constant STORAGE_LOCATION = 0xc2c9390e01b456a9509adb9185877a8c7db0879f855902e11d3da18ed83cef00;

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
