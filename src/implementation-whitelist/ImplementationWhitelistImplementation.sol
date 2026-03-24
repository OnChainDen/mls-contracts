// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Ownable2StepUpgradeable} from "@openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {
    LibImplementationWhitelistStorage
} from "implementation-whitelist/libraries/storage/LibImplementationWhitelistStorage.sol";
import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {ContractType} from "types/CommonTypes.sol";

/**
 * @title Implementation Whitelist
 * @notice Contract for managing whitelisted implementation addresses
 * @author Den Technologies Inc
 */
contract ImplementationWhitelistImplementation is
    Initializable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    IImplementationWhitelist
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IImplementationWhitelist
    function initialize(
        address initialOwner,
        address[] calldata organizationImplementations,
        address[] calldata accountImplementations
    ) external override initializer {
        __Ownable_init(initialOwner);
        __Ownable2Step_init();

        _addToWhitelist(ContractType.Organization, organizationImplementations);
        _addToWhitelist(ContractType.Account, accountImplementations);

        emit ImplementationWhitelistInitialized(initialOwner);
    }

    /// @inheritdoc IImplementationWhitelist
    function whitelistImplementations(
        ContractType contractType,
        address[] calldata toWhitelist,
        address[] calldata toUnwhitelist
    ) external override onlyOwner {
        _addToWhitelist(contractType, toWhitelist);
        _removeFromWhitelist(contractType, toUnwhitelist);
    }

    /// @inheritdoc IImplementationWhitelist
    function isInitialized() external view override returns (bool) {
        return owner() != address(0);
    }

    /// @inheritdoc IImplementationWhitelist
    function isImplementationWhitelisted(ContractType contractType, address implementation)
        external
        view
        override
        returns (bool)
    {
        return LibImplementationWhitelistStorage.layout().whitelisted[contractType][implementation];
    }

    /// @inheritdoc IImplementationWhitelist
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
     * @dev Adds implementation addresses to the whitelist.
     * @param contractType The type of contract (Account or Organization)
     * @param implementations The implementation addresses to whitelist
     */
    function _addToWhitelist(ContractType contractType, address[] calldata implementations) internal {
        LibImplementationWhitelistStorage.Layout storage storageLayout = LibImplementationWhitelistStorage.layout();

        for (uint256 i = 0; i < implementations.length; ++i) {
            storageLayout.whitelisted[contractType][implementations[i]] = true;
            emit ImplementationWhitelisted(contractType, implementations[i]);
        }
    }

    /**
     * @dev Removes implementation addresses from the whitelist.
     * @param contractType The type of contract (Account or Organization)
     * @param implementations The implementation addresses to remove from whitelist
     */
    function _removeFromWhitelist(ContractType contractType, address[] calldata implementations) internal {
        LibImplementationWhitelistStorage.Layout storage storageLayout = LibImplementationWhitelistStorage.layout();

        for (uint256 i = 0; i < implementations.length; ++i) {
            storageLayout.whitelisted[contractType][implementations[i]] = false;
            emit ImplementationUnwhitelisted(contractType, implementations[i]);
        }
    }

    /**
     * @notice Authorize an upgrade
     * @dev This function is empty because the onlyOwner modifier ensures that only the owner can upgrade
     * @param newImplementation The new implementation address
     */
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {}
}
