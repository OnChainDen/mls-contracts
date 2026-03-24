// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {ContractType} from "types/CommonTypes.sol";

/**
 * @dev Lightweight whitelist mock used by account-factory tests.
 */
contract ImplementationWhitelistMock is IImplementationWhitelist {
    mapping(ContractType => mapping(address => bool)) internal whitelisted;
    bool internal initialized;

    /**
     * @dev Sets whitelist status for `(contractType, implementation)`.
     */
    function setImplementationWhitelisted(ContractType contractType, address implementation, bool isWhitelisted)
        external
    {
        whitelisted[contractType][implementation] = isWhitelisted;
    }

    /**
     * @inheritdoc IImplementationWhitelist
     */
    function initialize(
        address,
        address[] calldata organizationImplementations,
        address[] calldata accountImplementations
    ) external override {
        initialized = true;

        for (uint256 i = 0; i < organizationImplementations.length; ++i) {
            whitelisted[ContractType.Organization][organizationImplementations[i]] = true;
        }

        for (uint256 i = 0; i < accountImplementations.length; ++i) {
            whitelisted[ContractType.Account][accountImplementations[i]] = true;
        }
    }

    /**
     * @inheritdoc IImplementationWhitelist
     */
    function whitelistImplementations(
        ContractType contractType,
        address[] calldata toWhitelist,
        address[] calldata toUnwhitelist
    ) external override {
        for (uint256 i = 0; i < toWhitelist.length; ++i) {
            whitelisted[contractType][toWhitelist[i]] = true;
        }

        for (uint256 i = 0; i < toUnwhitelist.length; ++i) {
            whitelisted[contractType][toUnwhitelist[i]] = false;
        }
    }

    /**
     * @inheritdoc IImplementationWhitelist
     */
    function isInitialized() external view override returns (bool) {
        return initialized;
    }

    /**
     * @inheritdoc IImplementationWhitelist
     */
    function isImplementationWhitelisted(ContractType contractType, address implementation)
        external
        view
        override
        returns (bool)
    {
        return whitelisted[contractType][implementation];
    }

    /**
     * @inheritdoc IImplementationWhitelist
     */
    function validateIsImplementationWhitelistedOrRevert(ContractType contractType, address implementation)
        external
        view
        override
    {
        if (!whitelisted[contractType][implementation]) {
            revert ImplementationNotWhitelisted(implementation);
        }
    }
}

/**
 * @dev Minimal whitelist stub that always reverts during validation.
 */
contract RevertingImplementationWhitelistMock {
    /**
     * @dev Reverts unconditionally so tests can assert fail-closed behavior when the whitelist call itself fails.
     * @param contractType Contract type argument accepted for signature compatibility.
     * @param implementation Implementation argument accepted for signature compatibility.
     */
    function validateIsImplementationWhitelistedOrRevert(ContractType contractType, address implementation)
        external
        pure
    {
        contractType;
        implementation;
        revert("VALIDATION_REVERT");
    }
}
