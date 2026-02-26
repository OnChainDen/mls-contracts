// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AccountImplementation} from "account/AccountImplementation.sol";

/**
 * @dev Test harness that exposes internal helpers from `AccountImplementation`.
 */
contract AccountImplementationHarness is AccountImplementation {
    /**
     * @dev Wrapper around `_execute`.
     */
    function executeViaInternal(address to, uint256 value, bytes calldata data, uint256 txGas) external returns (bool) {
        return _execute(to, value, data, txGas);
    }

    /**
     * @dev Wrapper around `_onlyOrganization`.
     */
    function onlyOrganizationViaInternal() external view {
        _onlyOrganization();
    }
}
