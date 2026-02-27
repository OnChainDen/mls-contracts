// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {OperationType} from "types/CommonTypes.sol";
import {
    OrganizationAccountFactoryBaseSuiteBase
} from "test/organization/base/OrganizationAccountFactoryBase/OrganizationAccountFactoryBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";

/**
 * @dev Unit tests for `OrganizationAccountFactoryBase.deployAccount` behavior.
 */
contract OrganizationAccountFactoryBaseDeployAccountTest is OrganizationAccountFactoryBaseSuiteBase {
    /// @dev Verifies non-guardian callers are rejected by the `onlyGuardian` modifier.
    function test_deployAccount_nonGuardianCaller_revertsOnlyGuardian() public {
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
    function test_deployAccount_insufficientAdminSignatures_revertsViaAdminAuthValidation() public {
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
    function test_deployAccount_replaySameNonce_revertsAfterSuccessfulExecution() public {
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

    /// @dev Verifies guardian + valid auth delegates to library deployment path and marks the account deployed.
    function test_deployAccount_guardianWithValidAuth_delegatesToLibraryAndMarksDeployed() public {
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
    function test_deployAccount_returnsCorrectDeterministicAddress() public {
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
    function test_deployAccount_operationTypeIsDeployAccount_inAdminAuthValidation() public {
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
        vm.expectRevert();
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
    function test_deployAccount_operationDataGoldenVector_matchesExpectedBytesAndHash() public pure {
        bytes32 create2Salt = bytes32(uint256(0xA11CE5));

        // Setup: fixed golden vector for deterministic operation-data encoding checks.
        bytes memory expectedOperationData =
            hex"0000000000000000000000000000000000000000000000000000000000a11ce5";
        bytes32 expectedOperationDataHash = 0x7c37bb08c7d93e782bdb69a12cdcb65172563367bd956b623cf7487543c1982c;

        // Call: encode operation data exactly as base contract does.
        bytes memory operationData = abi.encode(create2Salt);

        // Verify: bytes and hash match the pinned golden vector.
        assertEq(operationData, expectedOperationData, "operationData should equal abi.encode(create2Salt)");
        assertEq(keccak256(operationData), expectedOperationDataHash, "operationData hash mismatch for golden vector");
    }

    /// @dev Verifies expired auth params revert with `AdminOperationExpired`.
    function test_deployAccount_expiredAuthParams_revertsAdminOperationExpired() public {
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
    function test_deployAccount_create2SaltTamperingAfterSigning_invalidatesAuthAndReverts() public {
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
        vm.expectRevert();
        vm.prank(GUARDIAN);
        // Call: execute `deployAccount` with tampered `create2Salt`.
        harness.deployAccount(tamperedCreate2Salt, auth);

        bytes memory tamperedOperationData = _encodeOperationDataForDeployAccount(tamperedCreate2Salt);
        uint256 tamperedNonce = _computeDeployAccountNonce(tamperedOperationData, 5183);
        assertFalse(harness.getUsedNonce(tamperedNonce), "failed tampered auth should not consume nonce");
    }

    /// @dev Verifies failed auth does not consume nonce and corrected signatures succeed on retry.
    function test_deployAccount_failedAuth_doesNotConsumeNonceAndCanRetryWithCorrectedSignatures() public {
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
}
