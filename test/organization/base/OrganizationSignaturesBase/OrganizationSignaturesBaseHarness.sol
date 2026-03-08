// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationSignaturesBase} from "organization/base/OrganizationSignaturesBase.sol";
import {LibOrganizationSignatures} from "organization/libraries/LibOrganizationSignatures.sol";
import {LibOrganizationSignaturesStorage} from "organization/libraries/storage/LibOrganizationSignaturesStorage.sol";

/**
 * @dev Base-contract-focused harness exposing nonce state controls for `OrganizationSignaturesBase`.
 */
contract OrganizationSignaturesBaseHarness is OrganizationSignaturesBase {
    /**
     * @dev Writes a raw used-nonce flag for test setup.
     * @param nonce The nonce to mutate.
     * @param isUsed The value to store.
     */
    function setUsedNonce(uint256 nonce, bool isUsed) external {
        LibOrganizationSignaturesStorage.layout().usedNonces[nonce] = isUsed;
    }

    /**
     * @dev Consumes a nonce through the underlying library to simulate another state-changing flow.
     * @param nonce The nonce to consume.
     */
    function consumeNonceViaLibrary(uint256 nonce) external {
        LibOrganizationSignatures.validateAndConsumeNonceOrRevert(nonce);
    }
}
