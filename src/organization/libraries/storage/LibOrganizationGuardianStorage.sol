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
     * @dev Storage layout for guardian functionality
     * @custom:storage-location erc7201:den.mls-wallet.organization.guardian
     * @param guardian The address of the guardian authorized to submit transactions
     * @param pendingGuardian The proposed new guardian address (0 = no pending update)
     * @param pendingGuardianUpdateTimestamp When the pending update timelock expires (0 = no pending)
     * @param isGuardianUpdateReadyForAcceptance True after finalize, waiting for new guardian to accept
     * @param isRecoveryGuardianUpdate True if the pending update was initiated via recovery flow
     */
    struct Layout {
        address guardian;
        address pendingGuardian;
        uint256 pendingGuardianUpdateTimestamp;
        bool isGuardianUpdateReadyForAcceptance;
        bool isRecoveryGuardianUpdate;
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
