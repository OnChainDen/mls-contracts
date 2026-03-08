// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {ImplementationWhitelistProxy} from "implementation-whitelist/ImplementationWhitelistProxy.sol";
import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganizationFactory} from "interfaces/IOrganizationFactory.sol";
import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    ImplementationWhitelistHarness,
    ImplementationWhitelistV2Harness
} from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistHarnesses.sol";
import {
    OrganizationAccountFactoryBaseSuiteBase
} from "test/organization/base/OrganizationAccountFactoryBase/OrganizationAccountFactoryBaseSuiteBase.sol";
import {RevertingImplementationWhitelistMock} from "test/organization/shared/OrganizationAccountFactoryMocks.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {ContractType, OperationType} from "types/CommonTypes.sol";

interface IWhitelistProxyUpgradeEntrypoints {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

/**
 * @dev Unit tests for `OrganizationAccountFactoryBase.setAccountImplementation` behavior.
 */
contract OrganizationAccountFactoryBaseSetAccountImplementationTest is OrganizationAccountFactoryBaseSuiteBase {
    /// @dev Verifies OAFB-SAI-2: non-guardian callers are rejected by the `onlyGuardian` modifier.
    function test_OAFB_SAI_2_setAccountImplementation_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup: configure a valid one-admin baseline and prepare empty auth payload.
        _setSingleAdminThresholdOne();
        AdminAuthParams memory auth;

        // Verify: non-guardian caller must be rejected before auth validation runs.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        // Call: invoke `setAccountImplementation` from a non-guardian address.
        harness.setAccountImplementation(accountImplementationV1, auth);
    }

    /// @dev Verifies OAFB-SAI-4: insufficient admin signatures revert through admin-auth validation.
    function test_OAFB_SAI_4_setAccountImplementation_insufficientSignatures_revertsViaAdminAuthValidation() public {
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

    /// @dev Verifies OAFB-SAI-9: non-whitelisted implementations revert via whitelist validation.
    function test_OAFB_SAI_9_setAccountImplementation_nonWhitelistedImplementation_reverts() public {
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

    /// @dev Verifies desired behavior that whitelist addresses without runtime code are rejected. [OAFB-SAI-8]
    function test_OAFB_SAI_4__OAFB_SAI_8_OAFB_SAI_17_setAccountImplementation_whitelistAddressWithoutRuntimeCode_reverts()
        public
    {
        // Setup: configure one-admin auth and point upgrade whitelist to an EOA/no-code address.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(accountImplementationV1, true);
        _setAccountImplementationWhitelisted(accountImplementationV2, true);

        (AdminAuthParams memory seedAuth,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV2,
            salt: 6179,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(accountImplementationV2, seedAuth);

        harness.setUpgradeState(address(0), address(0));
        (AdminAuthParams memory zeroWhitelistAuth, bytes memory zeroWhitelistOperationData) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6180,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: execute `setAccountImplementation` against a zero-address whitelist.
        vm.prank(GUARDIAN);
        (bool zeroSuccess, bytes memory zeroRevertData) = address(harness)
            .call(abi.encodeCall(harness.setAccountImplementation, (accountImplementationV1, zeroWhitelistAuth)));

        // Verify: zero-address whitelist fails before mutating storage or reaching whitelist business logic.
        assertFalse(zeroSuccess, "zero-address whitelist should cause revert");
        assertEq(
            harness.getAccountImplementationStorage(),
            accountImplementationV2,
            "zero-address whitelist revert should preserve the active implementation pointer"
        );
        if (zeroRevertData.length >= 4) {
            bytes4 zeroRevertSelector;
            assembly {
                zeroRevertSelector := mload(add(zeroRevertData, 0x20))
            }
            assertTrue(
                zeroRevertSelector != IImplementationWhitelist.ImplementationNotWhitelisted.selector,
                "zero-address whitelist should revert before whitelist business logic"
            );
        }
        assertFalse(
            harness.getUsedNonce(_computeSetAccountImplementationNonce(zeroWhitelistOperationData, 6180)),
            "zero-address whitelist revert should not consume nonce"
        );

        // Setup: switch to a non-zero whitelist address that still has no runtime code.
        harness.setUpgradeState(address(0xABCD), address(0));
        (AdminAuthParams memory noCodeWhitelistAuth, bytes memory noCodeWhitelistOperationData) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6181,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: execute `setAccountImplementation` with a no-code whitelist target.
        vm.prank(GUARDIAN);
        (bool noCodeSuccess, bytes memory noCodeRevertData) = address(harness)
            .call(abi.encodeCall(harness.setAccountImplementation, (accountImplementationV1, noCodeWhitelistAuth)));

        // Verify: no-code whitelist also fails before mutating storage or reaching whitelist business logic.
        assertFalse(noCodeSuccess, "no-code whitelist address should cause revert");
        assertEq(
            harness.getAccountImplementationStorage(),
            accountImplementationV2,
            "no-code whitelist revert should preserve the active implementation pointer"
        );
        if (noCodeRevertData.length >= 4) {
            bytes4 noCodeRevertSelector;
            assembly {
                noCodeRevertSelector := mload(add(noCodeRevertData, 0x20))
            }
            assertTrue(
                noCodeRevertSelector != IImplementationWhitelist.ImplementationNotWhitelisted.selector,
                "no-code whitelist should revert before whitelist business logic"
            );
        }
        assertFalse(
            harness.getUsedNonce(_computeSetAccountImplementationNonce(noCodeWhitelistOperationData, 6181)),
            "no-code whitelist revert should not consume nonce"
        );
    }

    /// @dev Verifies OAFB-SAI-1: whitelisted implementations update account-implementation storage.
    function test_OAFB_SAI_1_setAccountImplementation_whitelistedImplementation_updatesStorage() public {
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

    /// @dev Verifies OAFB-SAI-11: successful updates emit `AccountImplementationUpdated(newImplementation)`.
    function test_OAFB_SAI_11_setAccountImplementation_success_emitsAccountImplementationUpdated() public {
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

    /// @dev Verifies OAFB-SAI-8: admin auth for implementation updates uses `OperationType.UpgradeAccount`.
    function test_OAFB_SAI_8_setAccountImplementation_operationTypeIsUpgradeAccount_inAdminAuthValidation() public {
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

    /// @dev Additional coverage (no direct 14-UPGRADES row ID): operation data encodes only `newImplementation`.
    function test_setAccountImplementation_operationData_encodesNewImplementation() public pure {
        address newImplementation = 0x111122223333444455556666777788889999aAaa;

        // Setup: fixed golden vector for deterministic operation-data encoding checks.
        bytes memory expectedOperationData = hex"000000000000000000000000111122223333444455556666777788889999aaaa";

        // Call: encode operation data exactly as base contract does.
        bytes memory operationData = abi.encode(newImplementation);

        // Verify: bytes match the pinned `abi.encode(address)` golden vector.
        assertEq(operationData, expectedOperationData, "operationData should equal abi.encode(newImplementation)");
    }

    /// @dev Verifies whitelist validation uses `ContractType.Account` (not `ContractType.Organization`). [OAFB-SAI-4]
    function test_OAFB_SAI_9__OAFB_SAI_4_setAccountImplementation_validatesAgainstWhitelistWithContractTypeAccount()
        public
    {
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

    /// @dev Verifies OAFB-SAI-5: replaying the same nonce after success reverts with `NonceAlreadyUsed`.
    function test_OAFB_SAI_5_NMAFB_AEP_4_setAccountImplementation_replaySameNonce_revertsAfterSuccessfulExecution()
        public
    {
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
    function test_OAFB_SAI_19__OAFB_SAI_7__NMAFB_AEP_6_setAccountImplementation_failedWhitelistValidation_doesNotConsumeNonceAndCanRetry()
        public
    {
        // Setup: seed an active implementation, then leave the retry target un-whitelisted for the first attempt.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(accountImplementationV1, true);

        (AdminAuthParams memory seedAuth,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6163,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(accountImplementationV1, seedAuth);

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
        assertEq(
            harness.getAccountImplementationStorage(),
            accountImplementationV1,
            "failed whitelist validation should keep the active implementation pointer unchanged"
        );

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
    /// [OAFB-SAI-9]
    function test_OAFB_SAI_12__OAFB_SAI_9_setAccountImplementation_noCodeImplementationEvenIfWhitelisted_reverts()
        public
    {
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

    /// @dev Verifies OAFB-SAI-3: expired admin auth reverts and does not consume nonce.
    function test_OAFB_SAI_3_setAccountImplementation_expiredAdminAuth_revertsAndDoesNotConsumeNonce() public {
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

    /// @dev Verifies signatures for a different implementation cannot authorize current update call. [OAFB-SAI-2]
    function test_OAFB_SAI_14__OAFB_SAI_2_setAccountImplementation_signaturesForDifferentImplementation_reverts()
        public
    {
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

    /// @dev Verifies OAFB-SAI-19: no-code-target revert path preserves current implementation pointer and nonce state.
    function test_OAFB_SAI_19_setAccountImplementation_noCodeTargetPath_doesNotConsumeNonceOrMutatePointer() public {
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

    /// @dev [DESIRED] Verifies `setAccountImplementation` explicitly rejects `newImplementation == address(0)` before
    ///      reaching whitelist or code-length checks.
    function test_OAFB_SAI_16__OAFB_SAI_10_setAccountImplementation_zeroImplementation_revertsExplicitly() public {
        // Setup: whitelist address(0) under Account type so whitelist check would pass, and configure one-admin auth.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(address(0), true);

        (AdminAuthParams memory auth,) = _buildSetAccountImplementationAuth({
            newImplementation: address(0),
            salt: 6171,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: attempt to set zero-address implementation with valid auth.
        vm.expectRevert(IOrganizationFactory.ZeroAddress.selector);
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(address(0), auth);

        // Verify: zero-address implementation should be explicitly rejected before whitelist/code-length checks.
    }

    /// @dev Verifies reverting whitelist contracts fail closed and preserve nonce/state for account implementation
    /// updates. [OAFB-SAI-7]
    function test_OAFB_SAI_17__OAFB_SAI_7_setAccountImplementation_revertingWhitelistContract_revertsAndPreservesState()
        public
    {
        // Setup: seed an active account implementation pointer, swap in a whitelist that always reverts, and prepare
        // an otherwise-valid implementation update payload.
        _setSingleAdminThresholdOne();
        harness.setAccountImplementationStorage(accountImplementationV1);
        RevertingImplementationWhitelistMock revertingWhitelist = new RevertingImplementationWhitelistMock();
        harness.setUpgradeState(address(revertingWhitelist), address(0));

        (AdminAuthParams memory auth, bytes memory operationData) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV2,
            salt: 6172,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: execute `setAccountImplementation` while the whitelist contract itself reverts.
        vm.expectRevert(bytes("VALIDATION_REVERT"));
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(accountImplementationV2, auth);

        // Verify: the whitelist-call failure leaves the active implementation pointer unchanged and does not consume
        // the signed nonce.
        assertEq(
            harness.getAccountImplementationStorage(),
            accountImplementationV1,
            "reverting whitelist should preserve the active implementation pointer"
        );
        assertFalse(
            harness.getUsedNonce(_computeSetAccountImplementationNonce(operationData, 6172)),
            "reverting whitelist should not consume nonce"
        );
    }

    /// @dev Verifies upgrading the real whitelist proxy preserves account implementation enforcement behavior.
    ///      [IWC-INT-5]
    function test_OAFB_SAI_18__IWC_INT_5_setAccountImplementation_upgradedWhitelistPreservesEnforcement() public {
        // Setup: route account implementation checks through a real whitelist proxy that already approves V1, then
        // prepare a whitelist upgrade target plus success/failure auth payloads.
        address whitelistOwner = address(0xD551);
        ImplementationWhitelistHarness realWhitelist = _deployRealWhitelistProxy(
            whitelistOwner, new address[](0), _singleAddress(address(accountImplementationV1))
        );
        ImplementationWhitelistV2Harness whitelistV2 = new ImplementationWhitelistV2Harness();
        harness.setUpgradeState(address(realWhitelist), address(0));
        _setSingleAdminThresholdOne();

        (AdminAuthParams memory allowedAuth,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6173,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory rejectedAuth,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV2,
            salt: 6174,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: upgrade the whitelist proxy itself, then execute account implementation updates against that upgraded
        // whitelist endpoint.
        vm.prank(whitelistOwner);
        IWhitelistProxyUpgradeEntrypoints(address(realWhitelist)).upgradeToAndCall(address(whitelistV2), bytes(""));

        vm.prank(GUARDIAN);
        harness.setAccountImplementation(accountImplementationV1, allowedAuth);

        // Verify: the preserved Account-type whitelist entry still authorizes V1, while the upgraded whitelist
        // continues to reject unapproved account implementations.
        assertEq(
            harness.getAccountImplementationStorage(),
            accountImplementationV1,
            "upgraded whitelist should preserve V1 approval"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, accountImplementationV2
            )
        );
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(accountImplementationV2, rejectedAuth);
    }

    /// @dev Verifies transferring whitelist ownership immediately changes who can unlock account implementation
    /// updates. [IWC-INT-6]
    function test_OAFB_SAI_19__IWC_INT_6_setAccountImplementation_whitelistOwnershipTransfer_changesMutationRights()
        public
    {
        // Setup: route account implementation checks through a real whitelist proxy that starts without V1 approved,
        // then prepare a reusable account implementation update payload.
        address whitelistOwner = address(0xD552);
        address newWhitelistOwner = address(0xD553);
        ImplementationWhitelistHarness realWhitelist =
            _deployRealWhitelistProxy(whitelistOwner, new address[](0), new address[](0));
        harness.setUpgradeState(address(realWhitelist), address(0));
        _setSingleAdminThresholdOne();

        (AdminAuthParams memory auth,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 6175,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: fail once while V1 is unapproved, transfer whitelist ownership, and then attempt whitelist mutations
        // from the old and new owners.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, accountImplementationV1
            )
        );
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(accountImplementationV1, auth);

        vm.prank(whitelistOwner);
        realWhitelist.transferOwnership(newWhitelistOwner);
        vm.prank(newWhitelistOwner);
        realWhitelist.acceptOwnership();

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, whitelistOwner));
        vm.prank(whitelistOwner);
        realWhitelist.whitelistImplementations(
            ContractType.Account, _singleAddress(address(accountImplementationV1)), new address[](0)
        );

        vm.prank(newWhitelistOwner);
        realWhitelist.whitelistImplementations(
            ContractType.Account, _singleAddress(address(accountImplementationV1)), new address[](0)
        );

        // Verify: only the new whitelist owner can unlock account implementation updates, and the original signed
        // request still succeeds because the failed pre-transfer attempt did not consume its nonce.
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(accountImplementationV1, auth);
        assertEq(
            harness.getAccountImplementationStorage(),
            accountImplementationV1,
            "new whitelist owner should unlock account implementation updates"
        );
    }

    /// @dev Deploys a real implementation-whitelist proxy configured with deterministic seed arrays.
    /// @param initialOwner Address that becomes whitelist owner during proxy initialization.
    /// @param organizationImplementations Initial Organization-type whitelist seeds.
    /// @param accountImplementations Initial Account-type whitelist seeds.
    /// @return proxyInstance Proxy-backed whitelist harness used by account implementation tests.
    function _deployRealWhitelistProxy(
        address initialOwner,
        address[] memory organizationImplementations,
        address[] memory accountImplementations
    ) internal returns (ImplementationWhitelistHarness proxyInstance) {
        ImplementationWhitelistHarness whitelistImplementation = new ImplementationWhitelistHarness();
        bytes memory initData = abi.encodeWithSelector(
            whitelistImplementation.initialize.selector,
            initialOwner,
            organizationImplementations,
            accountImplementations
        );
        proxyInstance = ImplementationWhitelistHarness(
            payable(address(new ImplementationWhitelistProxy(address(whitelistImplementation), initData)))
        );
    }

    /// @dev Wraps an address in a single-entry array for whitelist helper calls.
    /// @param value Address to place at index zero.
    /// @return values One-element address array containing `value`.
    function _singleAddress(address value) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = value;
    }
}
