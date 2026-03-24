// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @title Organization Recovery Storage
 * @dev ERC-7201 namespaced storage for disaster recovery functionality.
 *      Stores recovery configuration (set at init) and recovery state.
 *      Storage is organized into two nested structs for clarity:
 *      - TxRecoveryState: Transaction and ERC1271 signature recovery
 *      - GuardianRecoveryState: Guardian update recovery
 *
 *      Struct types are defined in types/RecoveryTypes.sol since they are publicly exposed.
 * @author Den Technologies Inc
 */
library LibOrganizationRecoveryStorage {
    /**
     * @dev Main storage layout containing both recovery subsystems.
     * @custom:storage-location erc7201:den.mls-wallet.organization.recovery
     * @param txRecovery Storage for transaction and ERC1271 signature recovery
     * @param guardianRecovery Storage for guardian recovery
     */
    struct Layout {
        TxRecoveryState txRecovery;
        GuardianRecoveryState guardianRecovery;
    }

    /// @dev Storage location for RecoveryStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.recovery")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.recovery"`
    bytes32 internal constant STORAGE_LOCATION = 0x3422f7ce8e1ae9226ca4f03d7ea92f44f09e1e9e24da8779dcbf69ffe6d91c00;

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
