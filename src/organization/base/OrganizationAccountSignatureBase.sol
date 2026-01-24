// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAccountSignature} from "interfaces/organization/IOrganizationAccountSignature.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAccountFactory} from "organization/libraries/LibOrganizationAccountFactory.sol";
import {LibOrganizationAccountSignature} from "organization/libraries/LibOrganizationAccountSignature.sol";

/**
 * @title OrganizationAccountSignatureBase
 * @dev Abstract contract implementing IOrganizationAccountSignature.
 *      Handles ERC-1271 signature validation for accounts.
 * @author Den Technologies Inc
 */
abstract contract OrganizationAccountSignatureBase is OrganizationModifiers, IOrganizationAccountSignature {
    /// @inheritdoc IOrganizationAccountSignature
    function isValidSignatureForAccount(address account, bytes32 hash, bytes calldata signature)
        external
        view
        override
        returns (bytes4 magicValue)
    {
        // Verify the caller is the account
        if (msg.sender != account) {
            revert IOrganizationAccountFactory.AccountNotDeployedByOrganization(account);
        }

        // Verify the account is deployed by this organization
        LibOrganizationAccountFactory.validateIsAccountDeployedByOrgOrRevert(account);

        return LibOrganizationAccountSignature.isValidSignature(account, hash, signature);
    }
}
