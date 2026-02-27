// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibAccountOrganizationAddressStorage
} from "account/libraries/storage/LibAccountOrganizationAddressStorage.sol";

/**
 * @dev Versioned account-proxy implementation used for constructor/delegation tests.
 */
contract AccountProxyBehaviorImplementationV1 {
    uint256 public initializedValue;
    uint256 public totalReceived;

    /**
     * @dev Initialization hook used for constructor data-path tests.
     */
    function initialize(uint256 value) external {
        initializedValue = value;
    }

    /**
     * @dev Version marker used to verify delegated behavior changes after beacon upgrades.
     */
    function version() external pure virtual returns (uint256) {
        return 1;
    }

    /**
     * @dev Returns beacon (organization) address from EIP-1967 beacon slot.
     */
    function getOrganizationAddress() external view returns (address) {
        return LibAccountOrganizationAddressStorage.getOrganizationAddress();
    }

    /**
     * @dev Receive hook used to verify ETH forwarding via proxy fallback/receive path.
     */
    receive() external payable {
        totalReceived += msg.value;
    }
}

/**
 * @dev Second version of account-proxy behavior implementation.
 */
contract AccountProxyBehaviorImplementationV2 is AccountProxyBehaviorImplementationV1 {
    /**
     * @dev Updated version marker for upgrade-propagation assertions.
     */
    function version() external pure override returns (uint256) {
        return 2;
    }
}
