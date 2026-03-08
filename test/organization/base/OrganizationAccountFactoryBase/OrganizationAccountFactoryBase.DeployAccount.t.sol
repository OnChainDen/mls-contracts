// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    OrganizationAccountFactoryBaseHarness
} from "test/organization/base/OrganizationAccountFactoryBase/OrganizationAccountFactoryBaseHarness.sol";
import {
    OrganizationAccountFactoryBaseSuiteBase
} from "test/organization/base/OrganizationAccountFactoryBase/OrganizationAccountFactoryBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

interface IOAFBVersionedAccount {
    function version() external view returns (uint256);
}

contract OAFBAccountImplementationVersion1 {
    function version() external pure returns (uint256) {
        return 1;
    }
}

contract OAFBAccountImplementationVersion2 {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract OAFBAccountImplementationVersion3 {
    function version() external pure returns (uint256) {
        return 3;
    }
}

/**
 * @dev Unit tests for `OrganizationAccountFactoryBase.deployAccount` behavior.
 */
contract OrganizationAccountFactoryBaseDeployAccountTest is OrganizationAccountFactoryBaseSuiteBase {
    /// @dev Verifies non-guardian callers are rejected by the `onlyGuardian` modifier.
    function test_OAFB_DA_1_deployAccount_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup: configure a valid one-admin baseline and prepare empty auth payload.
        _setSingleAdminThresholdOne();
        AdminAuthParams memory auth;

        // Verify: non-guardian caller must be rejected before auth validation runs.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        // Call: invoke `deployAccount` from a non-guardian address.
        harness.deployAccount(bytes32(uint256(1)), auth);
    }

    /// @dev Verifies insufficient admin signatures revert through admin-auth validation.
    function test_OAFB_DA_2_deployAccount_insufficientAdminSignatures_revertsViaAdminAuthValidation() public {
        bytes32 create2Salt = bytes32(uint256(4102));

        // Setup: require two signatures but provide one.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        (AdminAuthParams memory auth, bytes memory operationData) = _buildDeployAccountAuth({
            create2Salt: create2Salt,
            salt: 5102,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: authorization should fail when valid signer count is below threshold.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        // Call: execute `deployAccount` with insufficient signatures.
        harness.deployAccount(create2Salt, auth);

        uint256 nonce = _computeDeployAccountNonce(operationData, 5102);
        assertFalse(harness.getUsedNonce(nonce), "failed auth should not consume nonce");
    }

    /// @dev Verifies replaying the same nonce after success reverts with `NonceAlreadyUsed`.
    function test_OAFB_DA_3_NMAFB_AEP_1_deployAccount_replaySameNonce_revertsAfterSuccessfulExecution() public {
        bytes32 create2Salt = bytes32(uint256(4103));

        // Setup: configure one-admin auth and a valid implementation for beacon deployment.
        _setSingleAdminThresholdOne();
        harness.setAccountImplementationStorage(accountImplementationV1);

        (AdminAuthParams memory auth, bytes memory operationData) = _buildDeployAccountAuth({
            create2Salt: create2Salt,
            salt: 5103,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.deployAccount(create2Salt, auth);

        uint256 nonce = _computeDeployAccountNonce(operationData, 5103);
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed on successful deployment");

        // Verify: replay with identical nonce tuple must revert.
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        // Call: replay `deployAccount` with the same signed payload.
        harness.deployAccount(create2Salt, auth);
    }

    /// @dev Verifies `OrganizationAccountFactoryBase.deployAccount` isolates admin-auth salts and allows one
    /// successful deployment per fresh organization for identical `create2Salt` values.
    function test_NMAFB_AEP_2__NMAFB_AEP_3_deployAccount_sameCreate2Salt_usesIndependentNoncesAndSucceedsAcrossFreshOrganizations()
        public
    {
        bytes32 create2Salt = bytes32(uint256(41031));
        uint256 firstAdminSalt = 51031;
        uint256 secondAdminSalt = 51032;
        uint256 expiration = block.timestamp + 1 hours;

        // Setup: configure a valid implementation for the current organization and prepare a second fresh
        // organization with the same runtime-code implementation and one-admin threshold-one auth state.
        _setSingleAdminThresholdOne();
        harness.setAccountImplementationStorage(accountImplementationV1);

        OrganizationAccountFactoryBaseHarness secondHarness = new OrganizationAccountFactoryBaseHarness();
        secondHarness.setGuardian(GUARDIAN);
        secondHarness.setMemberStatus(admin1, true);
        secondHarness.setAdminStatus(admin1, true);
        secondHarness.setAdminCount(1);
        secondHarness.setVotingThreshold(1);
        secondHarness.setAccountImplementationStorage(accountImplementationV1);

        (AdminAuthParams memory firstAuth, bytes memory operationData) = _buildDeployAccountAuth({
            create2Salt: create2Salt,
            salt: firstAdminSalt,
            expiration: expiration,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        bytes32 secondOperationHash = secondHarness.getAdminOperationHash({
            operationType: OperationType.DeployAccount,
            operationData: operationData,
            salt: secondAdminSalt,
            expirationTimestamp: expiration,
            isApproval: true
        });
        AdminAuthParams memory secondAuth = AdminAuthParams({
            salt: secondAdminSalt,
            expirationTimestamp: expiration,
            signatures: _buildSortedEOASignatures(secondOperationHash, buildUint256Array(ADMIN_PK_1))
        });

        uint256 firstOrgNonce = _computeDeployAccountNonce(operationData, firstAdminSalt);
        uint256 secondSaltNonce = _computeDeployAccountNonce(operationData, secondAdminSalt);
        uint256 secondOrgNonce = secondHarness.computeNonce(OperationType.DeployAccount, operationData, secondAdminSalt);

        // Call: compare same-org nonces across different admin-auth salts, then deploy once per fresh organization
        // using the same `create2Salt` and matching signed payload bytes.
        assertTrue(firstOrgNonce != secondSaltNonce, "different admin-auth salts should produce different nonces");

        vm.prank(GUARDIAN);
        address firstAccount = harness.deployAccount(create2Salt, firstAuth);

        vm.prank(GUARDIAN);
        address secondAccount = secondHarness.deployAccount(create2Salt, secondAuth);

        // Verify: each organization consumes only its own nonce, and both deployments succeed despite identical
        // `create2Salt` inputs because the organizations are distinct deployers.
        assertTrue(harness.getUsedNonce(firstOrgNonce), "first organization should consume its deploy nonce");
        assertTrue(secondHarness.getUsedNonce(secondOrgNonce), "second organization should consume its deploy nonce");
        assertGt(firstAccount.code.length, 0, "first organization deployment should produce runtime code");
        assertGt(secondAccount.code.length, 0, "second organization deployment should produce runtime code");
        assertTrue(firstAccount != secondAccount, "fresh organizations should not collide on deployed account address");
    }

    /// @dev Verifies guardian + valid auth delegates to library deployment path and marks the account deployed.
    function test_OAFB_DA_7_deployAccount_guardianWithValidAuth_delegatesToLibraryAndMarksDeployed() public {
        bytes32 create2Salt = bytes32(uint256(4104));

        // Setup: configure one-admin auth and set a valid beacon implementation.
        _setSingleAdminThresholdOne();
        harness.setAccountImplementationStorage(accountImplementationV1);

        (AdminAuthParams memory auth,) = _buildDeployAccountAuth({
            create2Salt: create2Salt,
            salt: 5104,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        address expectedAccount = harness.computeAccountAddress(create2Salt);

        // Verify: account-deployed event from library path should be emitted by the organization.
        vm.expectEmit(true, true, true, true, address(harness));
        emit IOrganizationAccountFactory.AccountDeployed(expectedAccount, address(harness), create2Salt);

        vm.prank(GUARDIAN);
        // Call: execute `deployAccount` through base contract.
        address deployedAccount = harness.deployAccount(create2Salt, auth);

        // Verify: base call returns deployed address and deployed-account mapping is set.
        assertEq(deployedAccount, expectedAccount, "base call should return deterministic deployed address");
        assertTrue(harness.isDeployedAccount(deployedAccount), "deployed account should be tracked by organization");
    }

    /// @dev Verifies `deployAccount` returns the exact deterministic address for the given salt.
    function test_OAFB_DA_8_deployAccount_returnsCorrectDeterministicAddress() public {
        bytes32 create2Salt = bytes32(uint256(4105));

        // Setup: configure one-admin auth and set a valid beacon implementation.
        _setSingleAdminThresholdOne();
        harness.setAccountImplementationStorage(accountImplementationV1);

        (AdminAuthParams memory auth,) = _buildDeployAccountAuth({
            create2Salt: create2Salt,
            salt: 5105,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        address expectedAccount = harness.computeAccountAddress(create2Salt);

        vm.prank(GUARDIAN);
        // Call: execute account deployment.
        address deployedAccount = harness.deployAccount(create2Salt, auth);

        // Verify: returned address equals precomputed CREATE2 destination and has runtime code.
        assertEq(deployedAccount, expectedAccount, "returned account address mismatch");
        assertGt(deployedAccount.code.length, 0, "deployed account should have runtime code");
    }

    /// @dev Verifies admin auth for deploy-account uses `OperationType.DeployAccount`.
    function test_OAFB_DA_9_deployAccount_operationTypeIsDeployAccount_inAdminAuthValidation() public {
        bytes32 create2Salt = bytes32(uint256(4106));

        // Setup: configure one-admin auth and set a valid beacon implementation.
        _setSingleAdminThresholdOne();
        harness.setAccountImplementationStorage(accountImplementationV1);

        bytes memory operationData = _encodeOperationDataForDeployAccount(create2Salt);

        AdminAuthParams memory wrongTypeAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.UpgradeAccount,
            operationData: operationData,
            isApproval: true,
            salt: 5106,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: signatures over a different operation type must fail.
        // The contract hardcodes `OperationType.DeployAccount` when computing the EIP-712 hash,
        // so ECDSA recovery with a hash signed over `UpgradeAccount` yields an unrecognized address,
        // which is correctly rejected as a non-admin signer.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        // Call: invoke deploy path with mismatched operation-type signatures.
        harness.deployAccount(create2Salt, wrongTypeAuth);

        (AdminAuthParams memory correctAuth,) = _buildDeployAccountAuth({
            create2Salt: create2Salt,
            salt: 5106,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: retry with signatures over `OperationType.DeployAccount`.
        address deployedAccount = harness.deployAccount(create2Salt, correctAuth);

        // Verify: correct operation type authorizes successful deployment.
        assertEq(deployedAccount, harness.computeAccountAddress(create2Salt), "correct operation type should succeed");
    }

    /// @dev Verifies golden operation-data bytes are exactly `abi.encode(create2Salt)` for a fixed salt.
    function test_OAFB_DA_10_deployAccount_operationDataGoldenVector_matchesExpectedBytesAndHash() public pure {
        bytes32 create2Salt = bytes32(uint256(0xA11CE5));

        // Setup: fixed golden vector for deterministic operation-data encoding checks.
        bytes memory expectedOperationData = hex"0000000000000000000000000000000000000000000000000000000000a11ce5";
        bytes32 expectedOperationDataHash = 0x7c37bb08c7d93e782bdb69a12cdcb65172563367bd956b623cf7487543c1982c;

        // Call: encode operation data exactly as base contract does.
        bytes memory operationData = abi.encode(create2Salt);

        // Verify: bytes and hash match the pinned golden vector.
        assertEq(operationData, expectedOperationData, "operationData should equal abi.encode(create2Salt)");
        assertEq(keccak256(operationData), expectedOperationDataHash, "operationData hash mismatch for golden vector");
    }

    /// @dev Verifies expired auth params revert with `AdminOperationExpired`.
    function test_OAFB_DA_4_deployAccount_expiredAuthParams_revertsAdminOperationExpired() public {
        bytes32 create2Salt = bytes32(uint256(4182));

        // Setup: configure one-admin auth and sign with an already-expired timestamp.
        _setSingleAdminThresholdOne();

        uint256 expiration = block.timestamp - 1;
        (AdminAuthParams memory auth,) = _buildDeployAccountAuth({
            create2Salt: create2Salt,
            salt: 5182,
            expiration: expiration,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: expired admin operation should revert before nonce/signature checks.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.AdminOperationExpired.selector, expiration, block.timestamp)
        );
        vm.prank(GUARDIAN);
        // Call: execute `deployAccount` with expired auth params.
        harness.deployAccount(create2Salt, auth);
    }

    /// @dev Verifies tampering `create2Salt` after signing invalidates auth and reverts.
    function test_OAFB_DA_5_deployAccount_create2SaltTamperingAfterSigning_invalidatesAuthAndReverts() public {
        bytes32 signedCreate2Salt = bytes32(uint256(4183));
        bytes32 tamperedCreate2Salt = bytes32(uint256(4184));

        // Setup: configure one-admin auth and sign payload for a different CREATE2 salt.
        _setSingleAdminThresholdOne();
        (AdminAuthParams memory auth,) = _buildDeployAccountAuth({
            create2Salt: signedCreate2Salt,
            salt: 5183,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: tampered deploy payload must fail authorization.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        // Call: execute `deployAccount` with tampered `create2Salt`.
        harness.deployAccount(tamperedCreate2Salt, auth);

        bytes memory tamperedOperationData = _encodeOperationDataForDeployAccount(tamperedCreate2Salt);
        uint256 tamperedNonce = _computeDeployAccountNonce(tamperedOperationData, 5183);
        assertFalse(harness.getUsedNonce(tamperedNonce), "failed tampered auth should not consume nonce");
    }

    /// @dev Verifies failed auth does not consume nonce and corrected signatures succeed on retry.
    function test_OAFB_DA_6_deployAccount_failedAuth_doesNotConsumeNonceAndCanRetryWithCorrectedSignatures() public {
        bytes32 create2Salt = bytes32(uint256(4184));

        // Setup: require two signatures but provide one for the first attempt.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});
        harness.setAccountImplementationStorage(accountImplementationV1);

        (AdminAuthParams memory badAuth, bytes memory operationData) = _buildDeployAccountAuth({
            create2Salt: create2Salt,
            salt: 5184,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: first attempt with insufficient signatures.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.deployAccount(create2Salt, badAuth);

        uint256 nonce = _computeDeployAccountNonce(operationData, 5184);
        assertFalse(harness.getUsedNonce(nonce), "failed auth should not consume nonce");

        (AdminAuthParams memory goodAuth,) = _buildDeployAccountAuth({
            create2Salt: create2Salt,
            salt: 5184,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        vm.prank(GUARDIAN);
        // Call: retry with corrected signatures and identical payload tuple.
        address deployedAccount = harness.deployAccount(create2Salt, goodAuth);

        // Verify: corrected retry succeeds and consumes nonce.
        assertEq(deployedAccount, harness.computeAccountAddress(create2Salt), "corrected retry should deploy account");
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed after successful retry");
    }

    /// @dev Verifies `OrganizationAccountFactoryBase.deployAccount` rolls back the second admin-auth nonce when a
    /// duplicate `create2Salt` hits the downstream CREATE2 collision path.
    function test_NMAFB_AEP_7_deployAccount_duplicateCreate2Salt_rollsBackSecondNonce() public {
        bytes32 create2Salt = bytes32(uint256(4185));

        // Setup: configure a valid implementation, deploy once to occupy the CREATE2 slot, and prepare a second
        // signed deployment with the same `create2Salt` but a different admin-auth salt.
        _setSingleAdminThresholdOne();
        harness.setAccountImplementationStorage(accountImplementationV1);

        (AdminAuthParams memory firstAuth, bytes memory operationData) = _buildDeployAccountAuth({
            create2Salt: create2Salt,
            salt: 5185,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory secondAuth,) = _buildDeployAccountAuth({
            create2Salt: create2Salt,
            salt: 5186,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.deployAccount(create2Salt, firstAuth);

        uint256 firstNonce = _computeDeployAccountNonce(operationData, 5185);
        uint256 secondNonce = _computeDeployAccountNonce(operationData, 5186);

        // Call: attempt a second deployment that reaches the downstream CREATE2 collision branch.
        vm.expectRevert();
        vm.prank(GUARDIAN);
        harness.deployAccount(create2Salt, secondAuth);

        // Verify: the original deployment nonce stays consumed, while the reverted duplicate deployment rolls back
        // the later nonce because the downstream CREATE2 call failed.
        assertTrue(harness.getUsedNonce(firstNonce), "initial successful deployment should keep its nonce consumed");
        assertFalse(harness.getUsedNonce(secondNonce), "CREATE2 collision should roll back the second nonce");
    }

    /// @dev Verifies previously deployed accounts execute new implementation code immediately after upgrade.
    function test_OAFB_SAI_12_setAccountImplementation_previouslyDeployedAccountsImmediatelyUseNewImplementation()
        public
    {
        // Setup: configure versioned implementations, set V1, and deploy two accounts.
        _setSingleAdminThresholdOne();
        address implV1 = address(new OAFBAccountImplementationVersion1());
        address implV2 = address(new OAFBAccountImplementationVersion2());
        _setAccountImplementationWhitelisted(implV1, true);
        _setAccountImplementationWhitelisted(implV2, true);

        (AdminAuthParams memory setV1Auth,) = _buildSetAccountImplementationAuth({
            newImplementation: implV1,
            salt: 5201,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(implV1, setV1Auth);

        bytes32 saltA = bytes32(uint256(4201));
        bytes32 saltB = bytes32(uint256(4202));
        (AdminAuthParams memory deployAuthA,) = _buildDeployAccountAuth({
            create2Salt: saltA,
            salt: 5202,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory deployAuthB,) = _buildDeployAccountAuth({
            create2Salt: saltB,
            salt: 5203,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        address accountA = harness.deployAccount(saltA, deployAuthA);
        vm.prank(GUARDIAN);
        address accountB = harness.deployAccount(saltB, deployAuthB);
        assertEq(IOAFBVersionedAccount(accountA).version(), 1, "account A should start on v1");
        assertEq(IOAFBVersionedAccount(accountB).version(), 1, "account B should start on v1");

        (AdminAuthParams memory setV2Auth,) = _buildSetAccountImplementationAuth({
            newImplementation: implV2,
            salt: 5204,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: update account implementation pointer to V2.
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(implV2, setV2Auth);

        // Verify: previously deployed accounts now execute V2 code.
        assertEq(IOAFBVersionedAccount(accountA).version(), 2, "account A should switch to v2");
        assertEq(IOAFBVersionedAccount(accountB).version(), 2, "account B should switch to v2");
    }

    /// @dev Verifies accounts deployed after implementation upgrade use the latest implementation.
    function test_OAFB_SAI_13_setAccountImplementation_newlyDeployedAccountsAfterUpgradeUseNewImplementation() public {
        // Setup: set V1, then upgrade to V2 before deploying.
        _setSingleAdminThresholdOne();
        address implV1 = address(new OAFBAccountImplementationVersion1());
        address implV2 = address(new OAFBAccountImplementationVersion2());
        _setAccountImplementationWhitelisted(implV1, true);
        _setAccountImplementationWhitelisted(implV2, true);

        (AdminAuthParams memory setV1Auth,) = _buildSetAccountImplementationAuth({
            newImplementation: implV1,
            salt: 5205,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(implV1, setV1Auth);

        (AdminAuthParams memory setV2Auth,) = _buildSetAccountImplementationAuth({
            newImplementation: implV2,
            salt: 5206,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(implV2, setV2Auth);

        bytes32 create2Salt = bytes32(uint256(4203));
        (AdminAuthParams memory deployAuth,) = _buildDeployAccountAuth({
            create2Salt: create2Salt,
            salt: 5207,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: deploy account after pointer update to V2.
        vm.prank(GUARDIAN);
        address account = harness.deployAccount(create2Salt, deployAuth);

        // Verify: new account resolves latest V2 implementation.
        assertEq(IOAFBVersionedAccount(account).version(), 2, "new account should use v2");
    }

    /// @dev Verifies sequential implementation upgrades preserve expected behavior across V1 -> V2 -> V3.
    function test_OAFB_SAI_14_setAccountImplementation_sequentialUpgradesPreserveBehaviorAcrossVersions() public {
        // Setup: whitelist three versions, set V1, and deploy account.
        _setSingleAdminThresholdOne();
        address implV1 = address(new OAFBAccountImplementationVersion1());
        address implV2 = address(new OAFBAccountImplementationVersion2());
        address implV3 = address(new OAFBAccountImplementationVersion3());
        _setAccountImplementationWhitelisted(implV1, true);
        _setAccountImplementationWhitelisted(implV2, true);
        _setAccountImplementationWhitelisted(implV3, true);

        (AdminAuthParams memory setV1Auth,) = _buildSetAccountImplementationAuth({
            newImplementation: implV1,
            salt: 5208,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(implV1, setV1Auth);

        bytes32 create2Salt = bytes32(uint256(4204));
        (AdminAuthParams memory deployAuth,) = _buildDeployAccountAuth({
            create2Salt: create2Salt,
            salt: 5209,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        address account = harness.deployAccount(create2Salt, deployAuth);
        assertEq(IOAFBVersionedAccount(account).version(), 1, "account should start on v1");

        (AdminAuthParams memory setV2Auth,) = _buildSetAccountImplementationAuth({
            newImplementation: implV2,
            salt: 5210,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        // Call: upgrade pointer to V2.
        harness.setAccountImplementation(implV2, setV2Auth);
        assertEq(IOAFBVersionedAccount(account).version(), 2, "account should resolve v2");

        (AdminAuthParams memory setV3Auth,) = _buildSetAccountImplementationAuth({
            newImplementation: implV3,
            salt: 5211,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        // Call: upgrade pointer to V3.
        harness.setAccountImplementation(implV3, setV3Auth);

        // Verify: account resolves V3 after final upgrade.
        assertEq(IOAFBVersionedAccount(account).version(), 3, "account should resolve v3");
    }

    /// @dev Verifies all accounts under one organization share a single implementation pointer.
    function test_OAFB_SAI_15_setAccountImplementation_allAccountsShareSingleImplementationPointer() public {
        // Setup: deploy two accounts under V1 and then move pointer to V2.
        _setSingleAdminThresholdOne();
        address implV1 = address(new OAFBAccountImplementationVersion1());
        address implV2 = address(new OAFBAccountImplementationVersion2());
        _setAccountImplementationWhitelisted(implV1, true);
        _setAccountImplementationWhitelisted(implV2, true);

        (AdminAuthParams memory setV1Auth,) = _buildSetAccountImplementationAuth({
            newImplementation: implV1,
            salt: 5212,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(implV1, setV1Auth);

        bytes32 saltA = bytes32(uint256(4205));
        bytes32 saltB = bytes32(uint256(4206));
        (AdminAuthParams memory deployAuthA,) = _buildDeployAccountAuth({
            create2Salt: saltA,
            salt: 5213,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory deployAuthB,) = _buildDeployAccountAuth({
            create2Salt: saltB,
            salt: 5214,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        address accountA = harness.deployAccount(saltA, deployAuthA);
        vm.prank(GUARDIAN);
        address accountB = harness.deployAccount(saltB, deployAuthB);

        (AdminAuthParams memory setV2Auth,) = _buildSetAccountImplementationAuth({
            newImplementation: implV2,
            salt: 5215,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: execute one global implementation update.
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(implV2, setV2Auth);

        // Verify: both accounts now resolve the same updated implementation.
        assertEq(IOAFBVersionedAccount(accountA).version(), 2, "account A should share global pointer");
        assertEq(IOAFBVersionedAccount(accountB).version(), 2, "account B should share global pointer");
    }
}
