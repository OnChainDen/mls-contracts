// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAccountSignature} from "interfaces/organization/IOrganizationAccountSignature.sol";
import {
    OrganizationAccountSignatureBaseSuiteBase
} from "test/organization/base/OrganizationAccountSignatureBase/OrganizationAccountSignatureBaseSuiteBase.sol";

/**
 * @dev Fuzz tests for `OrganizationAccountSignatureBase`.
 */
contract OrganizationAccountSignatureBaseFuzzTest is OrganizationAccountSignatureBaseSuiteBase {
    /**
     * @dev Verifies `OrganizationAccountSignatureBase.isValidSignatureForAccount` rejects callers that are not the
     *      target account.
     * @param account Account argument passed to the base entry point
     * @param caller Caller used for the negative authorization branch
     * @param hash Message hash forwarded to signature validation
     * @param signature Arbitrary signature bytes forwarded to the base entry point
     */
    function testFuzz_FOASB_SIG_104_isValidSignatureForAccount_senderMustEqualAccount(
        address account,
        address caller,
        bytes32 hash,
        bytes calldata signature
    ) public {
        // Setup: mark the fuzzed account as deployed so the sender gate is the first failing condition.
        vm.assume(account != address(0));
        vm.assume(caller != account);
        harness.setDeployedAccount(account, true);

        // Call: invoke `isValidSignatureForAccount` as a different caller, expecting the sender-only gate revert.
        vm.expectRevert(IOrganizationAccountSignature.SenderIsNotAccount.selector);
        vm.prank(caller);
        harness.isValidSignatureForAccount(account, hash, signature);

        // Verify: the deployed-account flag remains intact after the rejected call.
        assertTrue(harness.isDeployedAccount(account), "deployed-account flag should remain unchanged");
    }

    /**
     * @dev Verifies `OrganizationAccountSignatureBase.isValidSignatureForAccount` rejects undeployed accounts even
     *      when `msg.sender == account`.
     * @param account Account/caller used for the undeployed-account branch
     * @param hash Message hash forwarded to signature validation
     * @param signature Arbitrary signature bytes forwarded to the base entry point
     */
    function testFuzz_FOASB_SIG_104_isValidSignatureForAccount_accountMustBeDeployedByOrganization(
        address account,
        bytes32 hash,
        bytes calldata signature
    ) public {
        // Setup: pick a non-zero account and leave the deployed-account mapping unset for it.
        vm.assume(account != address(0));
        vm.assume(!harness.isDeployedAccount(account));

        // Call: invoke `isValidSignatureForAccount` as the account itself, expecting the undeployed-account revert.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountFactory.AccountNotDeployedByOrganization.selector, account)
        );
        vm.prank(account);
        harness.isValidSignatureForAccount(account, hash, signature);

        // Verify: the undeployed-account mapping stays false after the rejected call.
        assertFalse(harness.isDeployedAccount(account), "undeployed-account flag should remain false");
    }
}
