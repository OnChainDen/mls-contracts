// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Organization Account Factory Storage
 * @dev ERC-7201 namespaced storage for organization account factory functionality
 * @author Den Technologies Inc
 */
library LibOrganizationAccountFactoryStorage {
    /**
     * @dev Storage layout for account factory functionality
     * @custom:storage-location erc7201:den.mls-wallet.organization.account-factory
     * @param deployedAccounts Mapping of account addresses deployed by this organization
     * @param accountImplementation The current implementation address for all Account beacon proxies
     */
    struct Layout {
        mapping(address => bool) deployedAccounts;
        address accountImplementation;
    }

    /// @dev Storage location for AccountFactoryStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.account-factory")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.account-factory"`
    bytes32 internal constant STORAGE_LOCATION = 0x3de57912ebfc3c01c4dfd99cd7387714a27cc82aab23759619e872b797d5d300;

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
