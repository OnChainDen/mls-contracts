// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    OrganizationAccountFactoryBaseSuiteBase
} from "test/organization/base/OrganizationAccountFactoryBase/OrganizationAccountFactoryBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {ContractType, OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `OrganizationAccountFactoryBase.setAccountImplementation` behavior.
 */
contract OrganizationAccountFactoryBaseSetAccountImplementationTest is OrganizationAccountFactoryBaseSuiteBase {
    /// @dev Verifies non-guardian callers are rejected by the `onlyGuardian` modifier.
    function test_OAFB_SAI_1_setAccountImplementation_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup: configure a valid one-admin baseline and prepare empty auth payload.
        _setSingleAdminThresholdOne();
        AdminAuthParams memory auth;

        // Verify: non-guardian caller must be rejected before auth validation runs.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        // Call: invoke `setAccountImplementation` from a non-guardian address.
        harness.setAccountImplementation(accountImplementationV1, auth);
    }

    /// @dev Verifies insufficient admin signatures revert through admin-auth validation.
    function test_OAFB_SAI_2_setAccountImplementation_insufficientSignatures_revertsViaAdminAuthValidation() public {
        // Setup: require two signatures but provide one.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});
        _setAccountImplementationWhitelisted(accountImplementationV1, true);

        (AdminAuthParams memory auth, bytes memory operationData) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6102,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: authorization should fail when signer threshold is not met.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        // Call: execute `setAccountImplementation` with insufficient signatures.
        harness.setAccountImplementation(accountImplementationV1, auth);

        uint256 nonce = _computeSetAccountImplementationNonce(operationData, 6102);
        assertFalse(harness.getUsedNonce(nonce), "failed auth should not consume nonce");
    }

    /// @dev Verifies non-whitelisted implementations revert via whitelist validation.
    function test_OAFB_SAI_3_setAccountImplementation_nonWhitelistedImplementation_reverts() public {
        address nonWhitelistedImplementation = address(0x6110000000000000000000000000000000000010);

        // Setup: configure one-admin auth and leave implementation un-whitelisted.
        _setSingleAdminThresholdOne();

        (AdminAuthParams memory auth, bytes memory operationData) = _buildSetAccountImplementationAuth({
            newImplementation: nonWhitelistedImplementation,
            salt: 6110,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: whitelist validation should reject unapproved implementation addresses.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, nonWhitelistedImplementation
            )
        );
        vm.prank(GUARDIAN);
        // Call: execute `setAccountImplementation` with an un-whitelisted implementation.
        harness.setAccountImplementation(nonWhitelistedImplementation, auth);

        uint256 nonce = _computeSetAccountImplementationNonce(operationData, 6110);
        assertFalse(harness.getUsedNonce(nonce), "whitelist failure should rollback nonce consumption");
    }

    /// @dev Verifies desired behavior that whitelist addresses without runtime code are rejected.
    function test_OAFB_SAI_4_setAccountImplementation_whitelistAddressWithoutRuntimeCode_reverts() public {
        // Setup: configure one-admin auth and point upgrade whitelist to an EOA/no-code address.
        _setSingleAdminThresholdOne();
        harness.setUpgradeState(address(0xABCD), address(0));

        (AdminAuthParams memory auth, bytes memory operationData) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6180,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: execute `setAccountImplementation` with no-code whitelist target.
        (bool success, bytes memory revertData) =
            address(harness).call(abi.encodeCall(harness.setAccountImplementation, (accountImplementationV1, auth)));

        // Verify: no-code whitelist addresses should be rejected at the call site.
        assertFalse(success, "no-code whitelist address should cause revert");
        // Verify: revert originates from calling the non-contract whitelist, not from whitelist business logic.
        // Foundry's revert data encoding varies across execution modes (empty in normal mode, diagnostic
        // string in trace mode), so we only assert on the selector when revert data is present.
        if (revertData.length >= 4) {
            bytes4 revertSelector;
            assembly {
                revertSelector := mload(add(revertData, 0x20))
            }
            assertTrue(
                revertSelector != IImplementationWhitelist.ImplementationNotWhitelisted.selector,
                "should revert before reaching whitelist validation"
            );
        }

        uint256 nonce = _computeSetAccountImplementationNonce(operationData, 6180);
        assertFalse(harness.getUsedNonce(nonce), "failed whitelist call should not consume nonce");
    }

    /// @dev Verifies whitelisted implementations update account-implementation storage.
    function test_OAFB_SAI_5_setAccountImplementation_whitelistedImplementation_updatesStorage() public {
        // Setup: configure one-admin auth and whitelist target implementation.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(accountImplementationV1, true);

        (AdminAuthParams memory auth,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6111,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: execute `setAccountImplementation` with whitelisted implementation.
        harness.setAccountImplementation(accountImplementationV1, auth);

        // Verify: account implementation storage should be updated.
        assertEq(harness.getAccountImplementationStorage(), accountImplementationV1, "account implementation mismatch");
    }

    /// @dev Verifies successful updates emit `AccountImplementationUpdated(newImplementation)`.
    function test_OAFB_SAI_6_setAccountImplementation_success_emitsAccountImplementationUpdated() public {
        // Setup: configure one-admin auth and whitelist target implementation.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(accountImplementationV1, true);

        (AdminAuthParams memory auth,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6112,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: expect account-implementation-updated event with the exact implementation address.
        vm.expectEmit(true, true, true, true, address(harness));
        emit IOrganizationAccountFactory.AccountImplementationUpdated(accountImplementationV1);

        vm.prank(GUARDIAN);
        // Call: execute successful `setAccountImplementation`.
        harness.setAccountImplementation(accountImplementationV1, auth);
    }

    /// @dev Verifies admin auth for implementation updates uses `OperationType.UpgradeAccount`.
    function test_OAFB_SAI_7_setAccountImplementation_operationTypeIsUpgradeAccount_inAdminAuthValidation() public {
        // Setup: configure one-admin auth and whitelist target implementation.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(accountImplementationV1, true);

        bytes memory operationData = _encodeOperationDataForSetAccountImplementation(accountImplementationV1);

        AdminAuthParams memory wrongTypeAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.DeployAccount,
            operationData: operationData,
            isApproval: true,
            salt: 6113,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: signatures over a different operation type must fail.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        // Call: invoke upgrade-account path with deploy-account signatures.
        harness.setAccountImplementation(accountImplementationV1, wrongTypeAuth);

        (AdminAuthParams memory correctAuth,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6113,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: retry with signatures over `OperationType.UpgradeAccount`.
        harness.setAccountImplementation(accountImplementationV1, correctAuth);

        // Verify: correct operation type authorizes successful update.
        assertEq(
            harness.getAccountImplementationStorage(),
            accountImplementationV1,
            "correct operation type should authorize update"
        );
    }

    /// @dev Verifies operation data for implementation updates encodes only `newImplementation`.
    function test_OAFB_SAI_8_setAccountImplementation_operationData_encodesNewImplementation() public pure {
        address newImplementation = 0x111122223333444455556666777788889999aAaa;

        // Setup: fixed golden vector for deterministic operation-data encoding checks.
        bytes memory expectedOperationData = hex"000000000000000000000000111122223333444455556666777788889999aaaa";

        // Call: encode operation data exactly as base contract does.
        bytes memory operationData = abi.encode(newImplementation);

        // Verify: bytes match the pinned `abi.encode(address)` golden vector.
        assertEq(operationData, expectedOperationData, "operationData should equal abi.encode(newImplementation)");
    }

    /// @dev Verifies whitelist validation uses `ContractType.Account` (not `ContractType.Organization`).
    function test_OAFB_SAI_9_setAccountImplementation_validatesAgainstWhitelistWithContractTypeAccount() public {
        // Setup: whitelist target under Organization type only and configure one-admin auth.
        _setSingleAdminThresholdOne();
        whitelist.setImplementationWhitelisted(ContractType.Organization, accountImplementationV1, true);

        (AdminAuthParams memory auth,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6115,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: target should still fail because account-type whitelist entry is required.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, accountImplementationV1
            )
        );
        vm.prank(GUARDIAN);
        // Call: attempt update when only Organization-type whitelist is set.
        harness.setAccountImplementation(accountImplementationV1, auth);

        // Setup: add the required Account-type whitelist entry.
        _setAccountImplementationWhitelisted(accountImplementationV1, true);

        vm.prank(GUARDIAN);
        // Call: retry with same signed request after account-type whitelisting.
        harness.setAccountImplementation(accountImplementationV1, auth);

        // Verify: update succeeds once Account-type whitelist entry exists.
        assertEq(
            harness.getAccountImplementationStorage(), accountImplementationV1, "account-type whitelist should pass"
        );
    }

    /// @dev Verifies replaying the same nonce after success reverts with `NonceAlreadyUsed`.
    function test_OAFB_SAI_10_setAccountImplementation_replaySameNonce_revertsAfterSuccessfulExecution() public {
        // Setup: configure one-admin auth and whitelist target implementation.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(accountImplementationV1, true);

        (AdminAuthParams memory auth, bytes memory operationData) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6116,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.setAccountImplementation(accountImplementationV1, auth);

        uint256 nonce = _computeSetAccountImplementationNonce(operationData, 6116);
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed on successful implementation update");

        // Verify: replay with identical signed payload must revert.
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        // Call: replay `setAccountImplementation` with same auth params.
        harness.setAccountImplementation(accountImplementationV1, auth);
    }

    /// @dev Verifies failed whitelist validation does not consume nonce and same signed request can later succeed.
    function test_OAFB_SAI_11_setAccountImplementation_failedWhitelistValidation_doesNotConsumeNonceAndCanRetry()
        public
    {
        // Setup: configure one-admin auth and leave implementation un-whitelisted for first attempt.
        _setSingleAdminThresholdOne();

        (AdminAuthParams memory auth, bytes memory operationData) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV2,
            salt: 6164,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, accountImplementationV2
            )
        );
        vm.prank(GUARDIAN);
        // Call: first attempt before whitelist entry exists.
        harness.setAccountImplementation(accountImplementationV2, auth);

        uint256 nonce = _computeSetAccountImplementationNonce(operationData, 6164);
        assertFalse(harness.getUsedNonce(nonce), "failed whitelist validation should not consume nonce");

        // Setup: add whitelist entry for retry with identical signed request.
        _setAccountImplementationWhitelisted(accountImplementationV2, true);

        vm.prank(GUARDIAN);
        // Call: retry with same auth params after whitelisting.
        harness.setAccountImplementation(accountImplementationV2, auth);

        // Verify: retry succeeds and now consumes nonce.
        assertEq(
            harness.getAccountImplementationStorage(), accountImplementationV2, "retry should update implementation"
        );
        assertTrue(harness.getUsedNonce(nonce), "successful retry should consume nonce");
    }

    /// @dev Verifies desired behavior that no-code implementation addresses are rejected even if whitelisted.
    function test_OAFB_SAI_12_setAccountImplementation_noCodeImplementationEvenIfWhitelisted_reverts() public {
        address noCodeImplementation = address(0xCA11);

        // Setup: whitelist an EOA/no-code target and configure one-admin auth.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(noCodeImplementation, true);

        (AdminAuthParams memory auth, bytes memory operationData) = _buildSetAccountImplementationAuth({
            newImplementation: noCodeImplementation,
            salt: 6165,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: no-code implementations should be rejected even when whitelisted.
        vm.expectRevert(
            abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, noCodeImplementation)
        );
        vm.prank(GUARDIAN);
        // Call: execute implementation update with a no-code target.
        harness.setAccountImplementation(noCodeImplementation, auth);

        uint256 nonce = _computeSetAccountImplementationNonce(operationData, 6165);
        assertFalse(harness.getUsedNonce(nonce), "failed no-code implementation update should not consume nonce");
    }

    /// @dev Verifies expired admin auth reverts and does not consume nonce.
    function test_OAFB_SAI_13_setAccountImplementation_expiredAdminAuth_revertsAndDoesNotConsumeNonce() public {
        // Setup: configure one-admin baseline and whitelist target implementation.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(accountImplementationV1, true);

        (AdminAuthParams memory expiredAuth, bytes memory operationData) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6166,
            expiration: block.timestamp - 1,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: expired auth payload must be rejected.
        vm.expectPartialRevert(IOrganizationAdmin.AdminOperationExpired.selector);
        vm.prank(GUARDIAN);
        // Call: execute implementation update with expired auth.
        harness.setAccountImplementation(accountImplementationV1, expiredAuth);

        uint256 nonce = _computeSetAccountImplementationNonce(operationData, 6166);
        assertFalse(harness.getUsedNonce(nonce), "expired auth should not consume nonce");
    }

    /// @dev Verifies signatures for a different implementation cannot authorize current update call.
    function test_OAFB_SAI_14_setAccountImplementation_signaturesForDifferentImplementation_reverts() public {
        // Setup: whitelist both implementations and sign auth for V1 only.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(accountImplementationV1, true);
        _setAccountImplementationWhitelisted(accountImplementationV2, true);

        (AdminAuthParams memory authForV1, bytes memory opDataForV1) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6168,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: operation-data mismatch invalidates auth for V2 update call.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        // Call: attempt update to V2 with signatures bound to V1.
        harness.setAccountImplementation(accountImplementationV2, authForV1);

        uint256 nonceForV2 = _computeSetAccountImplementationNonce(abi.encode(accountImplementationV2), 6168);
        assertFalse(harness.getUsedNonce(nonceForV2), "failed mismatched auth should not consume V2 nonce");

        uint256 nonceForV1 = _computeSetAccountImplementationNonce(opDataForV1, 6168);
        assertFalse(harness.getUsedNonce(nonceForV1), "failed mismatched auth should not consume V1 nonce");
    }

    /// @dev Verifies no-code-target revert path preserves current implementation pointer and nonce state.
    function test_OAFB_SAI_15_setAccountImplementation_noCodeTargetPath_doesNotConsumeNonceOrMutatePointer() public {
        address noCodeImplementation = address(0xCA11);

        // Setup: seed an active implementation and whitelist the no-code target.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(accountImplementationV1, true);
        _setAccountImplementationWhitelisted(noCodeImplementation, true);

        (AdminAuthParams memory seedAuth,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6169,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(accountImplementationV1, seedAuth);

        (AdminAuthParams memory failingAuth, bytes memory operationData) = _buildSetAccountImplementationAuth({
            newImplementation: noCodeImplementation,
            salt: 6170,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: no-code update path reverts and leaves state unchanged.
        vm.expectRevert(
            abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, noCodeImplementation)
        );
        vm.prank(GUARDIAN);
        // Call: attempt no-code implementation update.
        harness.setAccountImplementation(noCodeImplementation, failingAuth);

        uint256 nonce = _computeSetAccountImplementationNonce(operationData, 6170);
        assertFalse(harness.getUsedNonce(nonce), "no-code revert should not consume nonce");
        assertEq(
            harness.getAccountImplementationStorage(),
            accountImplementationV1,
            "active implementation pointer should remain unchanged"
        );
    }
}
