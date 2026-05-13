// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationInitialization} from "organization/libraries/LibOrganizationInitialization.sol";
import {InitializationParams} from "types/CommonTypes.sol";

/**
 * @title OrganizationInitializationBase
 * @dev Abstract contract implementing IOrganizationInitialization.
 *      Handles organization initialization logic.
 * @author Den Technologies Inc
 */
abstract contract OrganizationInitializationBase is Initializable, OrganizationModifiers, IOrganizationInitialization {
    /// @inheritdoc IOrganizationInitialization
    function initialize(InitializationParams calldata params) external override initializer onlyDeployer {
        LibOrganizationInitialization.initialize(params);
    }

    /// @inheritdoc IOrganizationInitialization
    function getDeployerAddress() external view override returns (address) {
        return LibOrganizationInitialization.getDeployerAddress();
    }

    /// @inheritdoc IOrganizationInitialization
    function isInitialized() external view override returns (bool) {
        return _getInitializedVersion() != 0;
    }
}
