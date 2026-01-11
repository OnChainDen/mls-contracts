// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {IImplementationWhitelist} from "./interfaces/IImplementationWhitelist.sol";
import {LibImplementationWhitelistStorage} from "./libraries/LibImplementationWhitelistStorage.sol";

/**
 * @title Implementation Whitelist
 * @notice Contract for managing whitelisted implementation addresses
 * @author Den Technologies Inc
 */
contract ImplementationWhitelistImplementation is Initializable, UUPSUpgradeable, Ownable, IImplementationWhitelist {
    /**
     * @notice Emitted when an implementation is whitelisted
     * @param contractType The type of contract (Account or Organization)
     * @param implementation The implementation address
     */
    event ImplementationWhitelisted(ContractType indexed contractType, address indexed implementation);

    /**
     * @notice Emitted when an implementation is removed from the whitelist
     * @param contractType The type of contract (Account or Organization)
     * @param implementation The implementation address
     */
    event ImplementationUnwhitelisted(ContractType indexed contractType, address indexed implementation);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() Ownable(msg.sender) {
        _disableInitializers();
    }

    /**
     * @notice Initialize the implementation whitelist
     * @param initialOwner The initial owner address
     */
    function initialize(address initialOwner) external initializer {
        _transferOwnership(initialOwner);
    }

    /**
     * @notice Whitelists and/or unwhitelists implementation addresses
     * @param contractType The type of contract (Account or Organization)
     * @param toWhitelist The implementation addresses to whitelist
     * @param toUnwhitelist The implementation addresses to remove from whitelist
     */
    function whitelistImplementations(
        ContractType contractType,
        address[] calldata toWhitelist,
        address[] calldata toUnwhitelist
    ) external onlyOwner {
        LibImplementationWhitelistStorage.Layout storage storageLayout = LibImplementationWhitelistStorage.layout();

        for (uint256 i = 0; i < toWhitelist.length; ++i) {
            storageLayout.whitelisted[contractType][toWhitelist[i]] = true;
            emit ImplementationWhitelisted(contractType, toWhitelist[i]);
        }

        for (uint256 i = 0; i < toUnwhitelist.length; ++i) {
            storageLayout.whitelisted[contractType][toUnwhitelist[i]] = false;
            emit ImplementationUnwhitelisted(contractType, toUnwhitelist[i]);
        }
    }

    /**
     * @notice Checks if an implementation address is whitelisted
     * @param contractType The type of contract (Account or Organization)
     * @param implementation The implementation address to check
     * @return True if the implementation is whitelisted, false otherwise
     */
    function isImplementationWhitelisted(ContractType contractType, address implementation)
        external
        view
        override
        returns (bool)
    {
        return LibImplementationWhitelistStorage.layout().whitelisted[contractType][implementation];
    }

    /**
     * @notice Validates that an implementation address is whitelisted, reverts if not
     * @param contractType The type of contract (Account or Organization)
     * @param implementation The implementation address to check
     */
    function validateIsImplementationWhitelistedOrRevert(ContractType contractType, address implementation)
        external
        view
        override
    {
        if (!LibImplementationWhitelistStorage.layout().whitelisted[contractType][implementation]) {
            revert ImplementationNotWhitelisted(implementation);
        }
    }

    /**
     * @notice Authorize an upgrade
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
