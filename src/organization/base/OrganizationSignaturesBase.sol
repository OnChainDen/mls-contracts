// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {LibOrganizationSignatures} from "organization/libraries/LibOrganizationSignatures.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @title OrganizationSignaturesBase
 * @dev Abstract contract implementing IOrganizationSignatures.
 *      Handles nonce checking and computation.
 *      Note: This contract does not need OrganizationModifiers as all functions are view.
 * @author Den Technologies Inc
 */
abstract contract OrganizationSignaturesBase is IOrganizationSignatures {
    /// @inheritdoc IOrganizationSignatures
    function isNonceUsed(uint256 nonce) external view override returns (bool) {
        return LibOrganizationSignatures.isNonceUsed(nonce);
    }

    /// @inheritdoc IOrganizationSignatures
    function computeNonce(OperationType operationType, bytes calldata operationData, uint256 salt)
        external
        view
        override
        returns (uint256)
    {
        return LibOrganizationSignatures.computeNonce(operationType, operationData, salt);
    }
}
