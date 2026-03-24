// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/**
 * @title Account Proxy
 * @notice BeaconProxy for Account contracts where the Organization acts as the beacon
 * @dev This is a thin wrapper around OpenZeppelin's BeaconProxy for clarity.
 *      The Organization contract implements IBeacon and provides the implementation address.
 *      Note: The factory deploys OpenZeppelin's BeaconProxy directly, so this contract
 *      serves as documentation of the Account proxy pattern.
 * @author Den Technologies Inc
 */
contract AccountProxy is BeaconProxy {
    /**
     * @notice Constructor for the Account BeaconProxy
     * @param beacon The beacon address (Organization contract)
     * @param data Initialization data to call on the implementation (can be empty)
     */
    constructor(address beacon, bytes memory data) BeaconProxy(beacon, data) {}
}
