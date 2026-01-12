// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Account Organization Address Storage
 * @notice Reads the organization address from the EIP-1967 Beacon slot
 * @dev Since the Account is a BeaconProxy and the Organization acts as the Beacon,
 *      the organization address is stored in the standard EIP-1967 Beacon slot.
 * @author Den Technologies Inc
 */
library LibAccountOrganizationAddressStorage {
    /// @dev EIP-1967 Beacon storage slot where the organization (beacon) address is stored.
    /// Computed as bytes32(uint256(keccak256('eip1967.proxy.beacon')) - 1)
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @notice Gets the organization address (beacon address) from the EIP-1967 Beacon slot
     * @return organizationAddress The address of the organization contract (beacon)
     */
    function getOrganizationAddress() internal view returns (address organizationAddress) {
        assembly {
            organizationAddress := sload(BEACON_SLOT)
        }
    }
}
