// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccountStorage } from "../storage/AccountStorage.sol";

/**
 * @title Account Initialization
 * @notice Initialization contract for OnchainCustodyAccount diamond
 * @author Den Technologies Inc
 */
contract AccountInit {
    /**
     * @notice Initializes the account contract with the organization address
     * @param onchainCustodyAddress The address of the onchain custody organization contract
     */
    function init(address onchainCustodyAddress) external {
        AccountStorage.Layout storage l = AccountStorage.layout();

        // Initialize organization address
        l.onchainCustodyAddress = onchainCustodyAddress;
    }
}
