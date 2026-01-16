// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title Organization Guardian Storage
 * @dev ERC-7201 namespaced storage for organization guardian functionality.
 *      Includes state for timelocked 3-step guardian update flow (initiate → finalize → accept).
 * @author Den Technologies Inc
 */
library LibOrganizationGuardianStorage {
    /**
     * @dev Storage layout for guardian functionality (normal flow only).
     *      Struct is ordered for optimal storage packing (4 slots).
     * @custom:storage-location erc7201:den.mls-wallet.organization.guardian
     * @param guardian The address of the guardian authorized to submit transactions
     * @param isGuardianUpdateReadyForAcceptance True after finalize, waiting for new guardian to accept (normal flow)
     * @param pendingGuardian The proposed new guardian address for normal flow (0 = no pending update)
     * @param guardianTimelockDuration The duration in seconds for normal guardian update timelocks
     * @param pendingGuardianUpdateTimestamp When the normal flow pending update timelock expires (0 = no pending)
     */
    struct Layout {
        address guardian;
        bool isGuardianUpdateReadyForAcceptance;
        address pendingGuardian;
        uint256 guardianTimelockDuration;
        uint256 pendingGuardianUpdateTimestamp;
    }

    /// @dev Storage location for GuardianStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.guardian")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.guardian"`
    bytes32 internal constant STORAGE_LOCATION = 0x8d7ccf8ed44e95e19e0de7ed151b804ee39cc6d2f17befbe8f8a86d379957a00;

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
