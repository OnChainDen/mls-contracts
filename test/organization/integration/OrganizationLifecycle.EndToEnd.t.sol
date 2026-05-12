// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import {AccountImplementation} from "account/AccountImplementation.sol";
import {IAccount} from "interfaces/IAccount.sol";
import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {OrganizationProxy} from "organization/OrganizationProxy.sol";
import {MockERC1271ValidSigner} from "test/helpers/MockERC1271Signers.sol";
import {SignatureTestHelpers} from "test/helpers/SignatureTestHelpers.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {
    OrganizationImplementationHarness,
    OrganizationImplementationV2Harness
} from "test/organization/shared/OrganizationUpgradeHarnesses.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {ContractType, GroupModification, InitializationParams, OperationType} from "types/CommonTypes.sol";
import {
    ApprovalConfig,
    ApproverType,
    DestinationType,
    InitiatorConfig,
    Policy,
    PolicyConfig,
    PolicyRoots,
    PolicyType,
    RateLimitConfig,
    RateLimitScope,
    RateLimitType,
    TokenFilter,
    TransactionType,
    ValidationProofs
} from "types/PolicyTypes.sol";

interface IVersionedAccount {
    /// @dev Returns the current implementation version exposed by the account proxy.
    /// @return The version number served by the active account implementation.
    function version() external view returns (uint256);
}

/**
 * @dev Account implementation used to prove beacon upgrades while preserving account behavior.
 */
contract VersionedAccountImplementationV1 is AccountImplementation {
    /// @dev Returns the baseline account implementation version.
    /// @return The baseline version marker.
    function version() external pure returns (uint256) {
        return 1;
    }
}

/**
 * @dev Upgraded account implementation used to verify post-upgrade behavior.
 */
contract VersionedAccountImplementationV2 is AccountImplementation {
    /// @dev Returns the upgraded account implementation version.
    /// @return The upgraded version marker.
    function version() external pure returns (uint256) {
        return 2;
    }
}

/**
 * @dev Helper target that rejects native-token transfers to exercise rollback paths.
 */
contract RevertingNativeReceiver {
    error NativeReceiveRejected();

    /// @dev Rejects every native-token transfer sent to this contract.
    receive() external payable {
        revert NativeReceiveRejected();
    }
}

/**
 * @dev Section-15 end-to-end integration coverage for organization lifecycle, nonce visibility, access control,
 * upgrades, and recovery flows.
 */
contract OrganizationLifecycleEndToEndIntegrationTest is InitializationSuiteBase, SignatureTestHelpers {
    /// @dev Encapsulates the transaction fixture used by policy-usage execution tests.
    struct PolicyUsageScenario {
        TransactionType transactionType;
        address to;
        uint256 value;
        bytes data;
        address destinationForUsage;
        uint256 expectedUsage;
    }

    /// @dev Encapsulates the signatures and nonce shared by replay-order tests.
    struct ReplayTransactionContext {
        uint256 expirationTimestamp;
        bytes approvalSignature;
        bytes rejectionSignature;
        uint256 nonce;
    }

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant INITIATE_ACCOUNT_TRANSACTION_TYPEHASH = keccak256(
        "InitiateAccountTransaction(address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval)"
    );
    bytes32 internal constant ORGANIZATION_NAME_HASH = keccak256("MLSWalletOrganization");
    bytes32 internal constant ORGANIZATION_VERSION_HASH = keccak256("1");

    uint256 internal constant ADMIN_PK_1 = 0xA11CE;
    uint256 internal constant INITIATOR_PK_1 = 0x91A0;
    uint256 internal constant POLICY_ID = 15_001;
    uint256 internal constant ADMIN_OPERATION_TIMELOCK = 2 days;
    uint256 internal constant RECOVERY_TIMELOCK = 2 days;

    address internal constant NON_GUARDIAN = address(0xCAFE);
    address internal constant UPDATED_GUARDIAN = address(0xC104);
    address internal constant RECOVERY_PENDING_GUARDIAN = address(0xC105);
    address internal constant EXECUTION_RECIPIENT = address(0xD201);
    address internal constant REJECTION_RECIPIENT = address(0xD202);
    address internal constant SECOND_RECIPIENT = address(0xD203);
    address internal constant RECOVERY_RECIPIENT = address(0xD204);

    string internal constant POLICY_IPFS_CID = "ipfs://section-15-integration";

    address internal adminSigner;
    address internal initiatorSigner;

    OrganizationImplementationHarness internal lifecycleImplementation;
    OrganizationImplementationV2Harness internal upgradedOrganizationImplementation;
    VersionedAccountImplementationV1 internal versionedAccountImplementationV1;
    VersionedAccountImplementationV2 internal versionedAccountImplementationV2;

    /// @dev Deploys the upgrade fixtures and deterministic signer addresses used by the section-15 suite.
    function setUp() public override {
        super.setUp();

        adminSigner = vm.addr(ADMIN_PK_1);
        initiatorSigner = vm.addr(INITIATOR_PK_1);

        lifecycleImplementation = new OrganizationImplementationHarness();
        upgradedOrganizationImplementation = new OrganizationImplementationV2Harness();
        versionedAccountImplementationV1 = new VersionedAccountImplementationV1();
        versionedAccountImplementationV2 = new VersionedAccountImplementationV2();

        whitelist.setImplementationWhitelisted(ContractType.Organization, address(lifecycleImplementation), true);
        whitelist.setImplementationWhitelisted(
            ContractType.Organization, address(upgradedOrganizationImplementation), true
        );
        whitelist.setImplementationWhitelisted(ContractType.Account, address(versionedAccountImplementationV1), true);
        whitelist.setImplementationWhitelisted(ContractType.Account, address(versionedAccountImplementationV2), true);
    }

    /// @dev Verifies the full organization lifecycle keeps execution, rejection, nonce, and policy-usage state
    /// coherent from factory deploy through account activity.
    function test_fullLifecycle_executesAndRejectsWithExpectedNonceAndPolicyUsageOutcomes() public {
        // Setup: deploy an initialized organization, configure one rate-limited auto-approve policy, and deploy a
        // funded account through the real factory and guardian/admin entrypoints.
        OrganizationImplementationHarness organization = _deployOrganizationHarness(bytes32(uint256(15_101)));
        Policy memory policy = _buildAutoApprovePolicy(initiatorSigner);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 5;
        ValidationProofs memory proofs = _setPoliciesAndBuildProofs(organization, POLICY_ID, policy, 15_102);
        address account = _deployAccount(organization, bytes32(uint256(15_103)), 15_104);
        vm.deal(account, 1 ether);

        uint256 executeValue = 0.25 ether;
        uint256 executeNonce;
        uint256 rejectNonce;

        // Call: execute one approved account transaction, then reject a second signed variant that shares the same
        // policy set but a distinct transaction tuple.
        {
            bytes memory executeData = bytes("");
            uint256 executeSalt = 15_105;
            uint256 executeExpiration = block.timestamp + 1 days;
            bytes memory initiatorApprovalSignature = _signInitiatorTransaction({
                organization: address(organization),
                account: account,
                to: EXECUTION_RECIPIENT,
                value: executeValue,
                data: executeData,
                salt: executeSalt,
                expirationTimestamp: executeExpiration,
                policyId: POLICY_ID,
                isApproval: true
            });
            executeNonce = _computeAccountTransactionNonce({
                organization: organization,
                account: account,
                to: EXECUTION_RECIPIENT,
                value: executeValue,
                data: executeData,
                policyId: POLICY_ID,
                salt: executeSalt
            });

            vm.prank(GUARDIAN);
            organization.executeAccountTransaction({
                account: account,
                to: EXECUTION_RECIPIENT,
                value: executeValue,
                data: executeData,
                salt: executeSalt,
                expirationTimestamp: executeExpiration,
                policyId: POLICY_ID,
                initiatorSignature: initiatorApprovalSignature,
                reviewSignatures: bytes(""),
                proofs: proofs
            });
        }

        {
            bytes memory rejectData = bytes("");
            uint256 rejectValue = 0.1 ether;
            uint256 rejectSalt = 15_106;
            uint256 rejectExpiration = block.timestamp + 1 days;
            bytes memory rejectionInitiatorSignature = _signInitiatorTransaction({
                organization: address(organization),
                account: account,
                to: REJECTION_RECIPIENT,
                value: rejectValue,
                data: rejectData,
                salt: rejectSalt,
                expirationTimestamp: rejectExpiration,
                policyId: POLICY_ID,
                isApproval: true
            });
            bytes memory rejectionAuthorizationSignature = _signInitiatorTransaction({
                organization: address(organization),
                account: account,
                to: REJECTION_RECIPIENT,
                value: rejectValue,
                data: rejectData,
                salt: rejectSalt,
                expirationTimestamp: rejectExpiration,
                policyId: POLICY_ID,
                isApproval: false
            });
            rejectNonce = _computeAccountTransactionNonce({
                organization: organization,
                account: account,
                to: REJECTION_RECIPIENT,
                value: rejectValue,
                data: rejectData,
                policyId: POLICY_ID,
                salt: rejectSalt
            });

            vm.prank(GUARDIAN);
            organization.rejectAccountTransaction({
                account: account,
                to: REJECTION_RECIPIENT,
                value: rejectValue,
                data: rejectData,
                salt: rejectSalt,
                expirationTimestamp: rejectExpiration,
                policyId: POLICY_ID,
                initiatorSignature: rejectionInitiatorSignature,
                reviewSignatures: rejectionAuthorizationSignature,
                proofs: proofs
            });
        }

        // Verify: the organization stays initialized, the execution path transfers value and consumes its nonce, the
        // rejection path consumes only its nonce, and policy usage increases only for the executed transaction.
        assertTrue(organization.isInitialized(), "organization should remain initialized");
        assertEq(IVersionedAccount(account).version(), 1, "account should start on v1");
        assertEq(EXECUTION_RECIPIENT.balance, executeValue, "approved transaction should transfer value");
        assertEq(REJECTION_RECIPIENT.balance, 0, "rejected transaction should not transfer value");
        assertTrue(organization.isNonceUsed(executeNonce), "execute nonce should be consumed");
        assertTrue(organization.isNonceUsed(rejectNonce), "reject nonce should be consumed");
        assertEq(
            organization.getPolicyUsage(
                POLICY_ID, policy, account, EXECUTION_RECIPIENT, initiatorSigner, proofs.policyProof
            ),
            1,
            "only the execution path should consume policy usage"
        );
    }

    /// @dev Verifies multiple accounts in one organization consume independent source-scoped rate-limit budgets under
    /// one shared policy root.
    function test_multipleAccounts_executeIndependentlyUnderSharedSourceScopedRateLimit() public {
        // Setup: deploy one organization with a shared policy root whose time-window budget is scoped per source
        // account, then deploy and fund two accounts that use the same initiator and destination.
        OrganizationImplementationHarness organization = _deployOrganizationHarness(bytes32(uint256(15_201)));
        Policy memory policy = _buildAutoApprovePolicy(initiatorSigner);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        ValidationProofs memory proofs = _setPoliciesAndBuildProofs(organization, POLICY_ID, policy, 15_202);
        address accountA = _deployAccount(organization, bytes32(uint256(15_203)), 15_204);
        address accountB = _deployAccount(organization, bytes32(uint256(15_205)), 15_206);
        vm.deal(accountA, 1 ether);
        vm.deal(accountB, 1 ether);

        uint256 expiration = block.timestamp + 1 days;
        bytes memory data = bytes("");

        // Call: execute one transaction from each account under the same shared policy set, then retry a second
        // transaction from account A inside the same time window.
        vm.prank(GUARDIAN);
        organization.executeAccountTransaction({
            account: accountA,
            to: SECOND_RECIPIENT,
            value: 0.1 ether,
            data: data,
            salt: 15_207,
            expirationTimestamp: expiration,
            policyId: POLICY_ID,
            initiatorSignature: _signInitiatorTransaction({
                organization: address(organization),
                account: accountA,
                to: SECOND_RECIPIENT,
                value: 0.1 ether,
                data: data,
                salt: 15_207,
                expirationTimestamp: expiration,
                policyId: POLICY_ID,
                isApproval: true
            }),
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        vm.prank(GUARDIAN);
        organization.executeAccountTransaction({
            account: accountB,
            to: SECOND_RECIPIENT,
            value: 0.1 ether,
            data: data,
            salt: 15_208,
            expirationTimestamp: expiration,
            policyId: POLICY_ID,
            initiatorSignature: _signInitiatorTransaction({
                organization: address(organization),
                account: accountB,
                to: SECOND_RECIPIENT,
                value: 0.1 ether,
                data: data,
                salt: 15_208,
                expirationTimestamp: expiration,
                policyId: POLICY_ID,
                isApproval: true
            }),
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, POLICY_ID));
        vm.prank(GUARDIAN);
        organization.executeAccountTransaction({
            account: accountA,
            to: SECOND_RECIPIENT,
            value: 0.1 ether,
            data: data,
            salt: 15_209,
            expirationTimestamp: expiration,
            policyId: POLICY_ID,
            initiatorSignature: _signInitiatorTransaction({
                organization: address(organization),
                account: accountA,
                to: SECOND_RECIPIENT,
                value: 0.1 ether,
                data: data,
                salt: 15_209,
                expirationTimestamp: expiration,
                policyId: POLICY_ID,
                isApproval: true
            }),
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Verify: both accounts succeed once under the shared root, each account sees only its own usage, and the
        // second account A attempt fails without mutating account B's independent budget.
        assertEq(SECOND_RECIPIENT.balance, 0.2 ether, "first transaction from each account should succeed");
        assertEq(
            organization.getPolicyUsage(
                POLICY_ID, policy, accountA, SECOND_RECIPIENT, initiatorSigner, proofs.policyProof
            ),
            1,
            "account A should use only its own source-scoped budget"
        );
        assertEq(
            organization.getPolicyUsage(
                POLICY_ID, policy, accountB, SECOND_RECIPIENT, initiatorSigner, proofs.policyProof
            ),
            1,
            "account B should use only its own source-scoped budget"
        );
    }

    /// @dev Verifies unauthorized callers are rejected across the modifier-protected organization entrypoints named in
    /// the end-to-end access-control matrix.
    function test_accessControlMatrix_rejectsUnauthorizedCallersAcrossProtectedEntrypoints() public {
        // Setup: deploy one fresh proxy that has not been initialized yet to exercise `onlyDeployer`, then deploy one
        // initialized organization and stage pending guardian and recovery updates for the other modifier branches.
        OrganizationProxy uninitializedProxy =
            new OrganizationProxy(address(lifecycleImplementation), address(whitelist));
        InitializationParams memory params = _buildInitializationParams(address(versionedAccountImplementationV1));

        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(NON_GUARDIAN);
        IOrganizationInitialization(address(uninitializedProxy)).initialize(params);

        OrganizationImplementationHarness organization = _deployOrganizationHarness(bytes32(uint256(15_401)));

        AdminAuthParams memory initiateGuardianAuth = _buildOperationAuth(
            organization, OperationType.InitiateUpdateGuardian, abi.encode(UPDATED_GUARDIAN), 15_402, true
        );
        vm.prank(GUARDIAN);
        organization.initiateGuardianUpdate(UPDATED_GUARDIAN, initiateGuardianAuth);

        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK);
        // forgefmt: disable-next-item
        AdminAuthParams memory finalizeGuardianAuth = _buildOperationAuth(
            organization, OperationType.FinalizeUpdateGuardian,
            abi.encode(UPDATED_GUARDIAN, organization.guardianUpdateAttemptId()), 15_403, true
        );
        vm.prank(GUARDIAN);
        organization.finalizeGuardianUpdate(finalizeGuardianAuth);

        vm.prank(GUARDIAN_RECOVERY);
        organization.initiateRecoveryGuardianUpdate(RECOVERY_PENDING_GUARDIAN);
        vm.warp(organization.getGuardianRecoveryState().pendingGuardianTimestamp);
        vm.prank(GUARDIAN_RECOVERY);
        organization.finalizeRecoveryGuardianUpdate();

        // Call: hit each protected entrypoint from an unauthorized caller instead of the required guardian, deployer,
        // pending guardian, guardian-recovery address, recovery pending guardian, or tx-recovery address.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, NON_GUARDIAN, GUARDIAN)
        );
        vm.prank(NON_GUARDIAN);
        organization.setPolicies(
            bytes32(uint256(1)),
            "ipfs://unauthorized",
            AdminAuthParams({salt: 0, expirationTimestamp: 0, signatures: bytes("")})
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, NON_GUARDIAN, UPDATED_GUARDIAN
            )
        );
        vm.prank(NON_GUARDIAN);
        organization.acceptGuardian();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector,
                NON_GUARDIAN,
                GUARDIAN_RECOVERY
            )
        );
        vm.prank(NON_GUARDIAN);
        organization.initiateRecoveryGuardianUpdate(address(0xC106));

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector,
                NON_GUARDIAN,
                RECOVERY_PENDING_GUARDIAN
            )
        );
        vm.prank(NON_GUARDIAN);
        organization.acceptGuardianRecovery();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationTxRecovery.UnauthorizedTxRecoveryAddress.selector, NON_GUARDIAN, TX_RECOVERY
            )
        );
        vm.prank(NON_GUARDIAN);
        organization.initiateEnableTransactionAndERC1271Recovery();

        // Verify: every protected path rejects the wrong caller with the exact modifier-specific error instead of
        // leaking through to downstream logic.
        assertEq(organization.guardian(), GUARDIAN, "guardian should remain unchanged");
        assertEq(organization.pendingGuardian(), UPDATED_GUARDIAN, "pending guardian should remain staged");
        assertEq(
            organization.getGuardianRecoveryState().pendingGuardian,
            RECOVERY_PENDING_GUARDIAN,
            "recovery pending guardian should remain staged"
        );
    }

    /// @dev Verifies `computeNonce` and `isNonceUsed` stay aligned with successful rejection, successful execution,
    /// and reverted execution rollback across distinct operation types.
    function test_computeNonceAndIsNonceUsed_matchSuccessRejectAndRollbackAcrossOperationTypes() public {
        // Setup: deploy one organization, prepare a policy-update nonce for the admin rejection path, deploy a real
        // account for the success path, and prepare a reverting receiver for the rollback path.
        OrganizationImplementationHarness organization = _deployOrganizationHarness(bytes32(uint256(15_501)));

        Policy memory activePolicy = _buildAutoApprovePolicy(initiatorSigner);
        ValidationProofs memory activeProofs = _setPoliciesAndBuildProofs(organization, POLICY_ID, activePolicy, 15_503);

        bytes32 deploySalt = bytes32(uint256(15_504));
        uint256 deployAccountNonce =
            organization.computeNonce(OperationType.DeployAccount, abi.encode(deploySalt), 15_505);
        address account = _deployAccount(organization, deploySalt, 15_505);
        vm.deal(account, 1 ether);

        RevertingNativeReceiver revertingReceiver = new RevertingNativeReceiver();
        uint256 rejectedSetPoliciesNonce;
        uint256 failingExecutionNonce;

        // Call: consume the policy-update nonce via rejection, consume the deploy-account nonce via success, and then
        // force an account-transaction execution revert after its nonce has been computed.
        {
            Policy memory rejectedPolicy = _buildAutoApprovePolicy(initiatorSigner);
            bytes32 rejectedRoot = _computePolicyLeaf(POLICY_ID, rejectedPolicy);
            bytes memory rejectedSetPoliciesData = abi.encode(rejectedRoot, keccak256(bytes("ipfs://rejected-policy")));
            uint256 rejectedSetPoliciesSalt = 15_502;
            rejectedSetPoliciesNonce = organization.computeNonce(
                OperationType.ModifyPolicies, rejectedSetPoliciesData, rejectedSetPoliciesSalt
            );
            AdminAuthParams memory rejectedSetPoliciesAuth = _buildOperationAuth(
                organization, OperationType.ModifyPolicies, rejectedSetPoliciesData, rejectedSetPoliciesSalt, false
            );
            AdminAuthParams memory blockedSetPoliciesApproval = _buildOperationAuth(
                organization, OperationType.ModifyPolicies, rejectedSetPoliciesData, rejectedSetPoliciesSalt, true
            );

            vm.prank(GUARDIAN);
            organization.rejectAdminOperation(
                OperationType.ModifyPolicies, rejectedSetPoliciesData, rejectedSetPoliciesAuth
            );

            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, rejectedSetPoliciesNonce)
            );
            vm.prank(GUARDIAN);
            organization.setPolicies(rejectedRoot, "ipfs://rejected-policy", blockedSetPoliciesApproval);
        }

        {
            bytes memory failingData = bytes("");
            uint256 failingExecutionSalt = 15_506;
            uint256 failingExecutionExpiration = block.timestamp + 1 days;
            failingExecutionNonce = _computeAccountTransactionNonce({
                organization: organization,
                account: account,
                to: address(revertingReceiver),
                value: 0.1 ether,
                data: failingData,
                policyId: POLICY_ID,
                salt: failingExecutionSalt
            });
            bytes memory failingExecutionSignature = _signInitiatorTransaction({
                organization: address(organization),
                account: account,
                to: address(revertingReceiver),
                value: 0.1 ether,
                data: failingData,
                salt: failingExecutionSalt,
                expirationTimestamp: failingExecutionExpiration,
                policyId: POLICY_ID,
                isApproval: true
            });

            vm.expectRevert(IAccount.TransactionExecutionFailed.selector);
            vm.prank(GUARDIAN);
            organization.executeAccountTransaction({
                account: account,
                to: address(revertingReceiver),
                value: 0.1 ether,
                data: failingData,
                salt: failingExecutionSalt,
                expirationTimestamp: failingExecutionExpiration,
                policyId: POLICY_ID,
                initiatorSignature: failingExecutionSignature,
                reviewSignatures: bytes(""),
                proofs: activeProofs
            });
        }

        // Verify: the public nonce views report rejected admin operations as consumed, successful deploy-account
        // operations as consumed, and reverted account transactions as rolled back to unused.
        assertTrue(
            organization.isNonceUsed(rejectedSetPoliciesNonce), "rejected policy-update nonce should be consumed"
        );
        assertTrue(organization.isNonceUsed(deployAccountNonce), "successful deploy-account nonce should be consumed");
        assertFalse(
            organization.isNonceUsed(failingExecutionNonce),
            "reverted account-transaction nonce should roll back to unused"
        );
    }

    /// @dev Verifies guardian rotation and policy-governed account execution remain coherent after both the
    /// organization implementation and account implementation are upgraded.
    function test_guardianUpdateAndTransactionExecution_remainCoherentAcrossOrganizationAndAccountUpgrades() public {
        // Setup: deploy an organization/account pair on v1 implementations, publish one policy root, and fund the
        // account before running the upgrade and guardian-rotation sequence.
        OrganizationImplementationHarness organization = _deployOrganizationHarness(bytes32(uint256(15_601)));
        Policy memory policy = _buildAutoApprovePolicy(initiatorSigner);
        ValidationProofs memory proofs = _setPoliciesAndBuildProofs(organization, POLICY_ID, policy, 15_602);
        address account = _deployAccount(organization, bytes32(uint256(15_603)), 15_604);
        vm.deal(account, 1 ether);

        // Call: upgrade the organization implementation, stage and accept a new guardian, upgrade the shared account
        // implementation from that new guardian, and execute a policy-authorized transaction after both upgrades.
        _upgradeOrganization(organization, 15_605);
        _completeGuardianUpdate(organization, UPDATED_GUARDIAN, 15_606, 15_607);

        {
            AdminAuthParams memory upgradedAccountAuth = _buildOperationAuth(
                organization,
                OperationType.UpgradeAccount,
                abi.encode(address(versionedAccountImplementationV2)),
                15_608,
                true
            );
            vm.prank(UPDATED_GUARDIAN);
            organization.setAccountImplementation(address(versionedAccountImplementationV2), upgradedAccountAuth);
        }

        {
            bytes memory data = bytes("");
            uint256 expiration = block.timestamp + 1 days;
            vm.prank(UPDATED_GUARDIAN);
            organization.executeAccountTransaction({
                account: account,
                to: EXECUTION_RECIPIENT,
                value: 0.2 ether,
                data: data,
                salt: 15_609,
                expirationTimestamp: expiration,
                policyId: POLICY_ID,
                initiatorSignature: _signInitiatorTransaction({
                    organization: address(organization),
                    account: account,
                    to: EXECUTION_RECIPIENT,
                    value: 0.2 ether,
                    data: data,
                    salt: 15_609,
                    expirationTimestamp: expiration,
                    policyId: POLICY_ID,
                    isApproval: true
                }),
                reviewSignatures: bytes(""),
                proofs: proofs
            });
        }

        // Verify: the proxy now resolves to the upgraded organization logic, the guardian has rotated, the account
        // proxy resolves to the upgraded account logic, and transaction execution still works through the upgraded
        // stack.
        assertEq(
            OrganizationImplementationV2Harness(payable(address(organization))).version(),
            2,
            "organization should resolve to upgraded logic"
        );
        assertEq(organization.guardian(), UPDATED_GUARDIAN, "guardian should rotate successfully after upgrade");
        assertEq(IVersionedAccount(account).version(), 2, "account should resolve to upgraded logic");
        assertEq(EXECUTION_RECIPIENT.balance, 0.2 ether, "post-upgrade transaction should still execute");
    }

    /// @dev Verifies guardian-recovery and tx-recovery flows remain coherent after upgrading both the organization
    /// implementation and the shared account implementation.
    function test_recoveryFlows_remainCoherentAcrossOrganizationAndAccountUpgrades() public {
        // Setup: deploy one organization/account pair on v1 implementations, then fund the account for the recovery
        // execution path that will run after both upgrades complete.
        OrganizationImplementationHarness organization = _deployOrganizationHarness(bytes32(uint256(15_610)));
        address account = _deployAccount(organization, bytes32(uint256(15_611)), 15_612);
        vm.deal(account, 1 ether);

        // Call: upgrade the organization, upgrade the shared account implementation, complete a guardian-recovery
        // rotation, enable tx recovery through its timelock, and execute a recovery transaction on the upgraded
        // account.
        _upgradeOrganization(organization, 15_613);

        AdminAuthParams memory upgradedAccountAuth = _buildOperationAuth(
            organization,
            OperationType.UpgradeAccount,
            abi.encode(address(versionedAccountImplementationV2)),
            15_614,
            true
        );
        vm.prank(GUARDIAN);
        organization.setAccountImplementation(address(versionedAccountImplementationV2), upgradedAccountAuth);

        vm.prank(GUARDIAN_RECOVERY);
        organization.initiateRecoveryGuardianUpdate(RECOVERY_PENDING_GUARDIAN);
        vm.warp(organization.getGuardianRecoveryState().pendingGuardianTimestamp);
        vm.prank(GUARDIAN_RECOVERY);
        organization.finalizeRecoveryGuardianUpdate();
        vm.prank(RECOVERY_PENDING_GUARDIAN);
        organization.acceptGuardianRecovery();

        vm.prank(TX_RECOVERY);
        organization.initiateEnableTransactionAndERC1271Recovery();
        vm.warp(organization.getTxRecoveryState().pendingEnableTimestamp);
        vm.prank(TX_RECOVERY);
        organization.finalizeEnableTransactionAndERC1271Recovery();

        vm.prank(TX_RECOVERY);
        organization.executeRecoveryAccountTransaction(account, RECOVERY_RECIPIENT, 0.3 ether, bytes(""));

        // Verify: recovery paths keep working through the upgraded organization/account stack, guardian recovery
        // updates the live guardian, and tx recovery can still execute against the upgraded account implementation.
        assertEq(
            OrganizationImplementationV2Harness(payable(address(organization))).version(),
            2,
            "organization should remain on upgraded logic"
        );
        assertEq(organization.guardian(), RECOVERY_PENDING_GUARDIAN, "guardian recovery should update guardian");
        assertEq(IVersionedAccount(account).version(), 2, "account should resolve to upgraded logic");
        assertEq(RECOVERY_RECIPIENT.balance, 0.3 ether, "tx recovery should still execute on upgraded account");
    }

    /// @dev Verifies the real tx-recovery disable flow immediately blocks both recovery account transactions and
    /// recovery ERC-1271 signatures.
    function test_disableRecoveryImmediatelyBlocksTransactionsAndERC1271Signatures() public {
        // Setup: deploy one organization with a contract-based recovery signer, deploy and fund one account, then
        // enable tx/ERC-1271 recovery through the real timelocked flow.
        MockERC1271ValidSigner recoverySigner = new MockERC1271ValidSigner();
        InitializationParams memory params = _buildInitializationParams(address(versionedAccountImplementationV1));
        params.transactionAndERC1271RecoveryAddress = address(recoverySigner);

        OrganizationImplementationHarness organization =
            _deployOrganizationHarnessWithParams(bytes32(uint256(15_620)), params);
        address account = _deployAccount(organization, bytes32(uint256(15_621)), 15_622);
        vm.deal(account, 1 ether);

        vm.prank(address(recoverySigner));
        organization.initiateEnableTransactionAndERC1271Recovery();
        vm.warp(organization.getTxRecoveryState().pendingEnableTimestamp);
        vm.prank(address(recoverySigner));
        organization.finalizeEnableTransactionAndERC1271Recovery();

        bytes32 recoveryHash = keccak256("orec-trf-7-recovery");
        uint256 recoveryExpiration = block.timestamp + 1 days;
        bytes memory contractSig = abi.encodePacked(uint8(0), address(recoverySigner), uint16(2), hex"CAFE");
        bytes memory recoverySignature = abi.encodePacked(uint8(0x00), abi.encode(recoveryExpiration, contractSig));

        // Call: confirm recovery execution and ERC-1271 validation both work while recovery is enabled, then disable
        // recovery through the real entrypoint and retry both behaviors immediately.
        vm.prank(address(recoverySigner));
        organization.executeRecoveryAccountTransaction(account, RECOVERY_RECIPIENT, 0.2 ether, bytes(""));

        bytes4 enabledSignatureResult = IAccount(payable(account)).isValidSignature(recoveryHash, recoverySignature);

        vm.prank(address(recoverySigner));
        organization.disableTransactionAndERC1271Recovery();

        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotEnabled.selector);
        vm.prank(address(recoverySigner));
        organization.executeRecoveryAccountTransaction(account, RECOVERY_RECIPIENT, 0.1 ether, bytes(""));

        bytes4 disabledSignatureResult = IAccount(payable(account)).isValidSignature(recoveryHash, recoverySignature);

        // Verify: the same recovery authority succeeds before disable, then both the execution path and ERC-1271
        // signature path fail immediately after disable with no grace period.
        assertEq(RECOVERY_RECIPIENT.balance, 0.2 ether, "only the pre-disable recovery transaction should execute");
        assertEq(
            enabledSignatureResult,
            IERC1271.isValidSignature.selector,
            "enabled recovery should accept the contract-signature payload"
        );
        assertEq(
            disabledSignatureResult, bytes4(0xffffffff), "disabled recovery should immediately reject the same payload"
        );
    }

    /// @dev Verifies `getPolicyUsage` matches the usage written by the real account-transaction execution path.
    /// @param organizationSalt CREATE2 salt used for organization deployment.
    /// @param accountSalt CREATE2 salt used for account deployment.
    /// @param amountRaw Fuzzed amount seed used for token-transfer usage.
    /// @param useTokenTransfer Whether to exercise the token-transfer or contract-interaction execution path.
    function testFuzz_getPolicyUsage_matchesExecutionPathUsage(
        bytes32 organizationSalt,
        bytes32 accountSalt,
        uint96 amountRaw,
        bool useTokenTransfer
    ) public {
        // Setup: deploy a real organization/account pair and install one rate-limited auto-approve policy.
        OrganizationImplementationHarness organization = _deployOrganizationHarness(organizationSalt);
        address account = _deployAccount(
            organization, accountSalt, uint256(keccak256(abi.encodePacked("fcf-rate-163-deploy", accountSalt)))
        );
        vm.deal(account, 1 ether);

        Policy memory policy = _buildAutoApprovePolicy(initiatorSigner);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = type(uint128).max;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        PolicyUsageScenario memory scenario =
            _buildPolicyUsageScenario(organizationSalt, accountSalt, amountRaw, useTokenTransfer);
        policy.config.transactionType = scenario.transactionType;

        ValidationProofs memory proofs = _setPoliciesAndBuildProofs(organization, POLICY_ID, policy, 16_301);
        ValidationProofs memory executionProofs = _buildEmptyProofs(policy);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTransaction({
            organization: address(organization),
            account: account,
            to: scenario.to,
            value: scenario.value,
            data: scenario.data,
            salt: 16_302,
            expirationTimestamp: expiration,
            policyId: POLICY_ID,
            isApproval: true
        });

        // Call: execute one real account transaction and then read usage back through `getPolicyUsage`.
        vm.prank(GUARDIAN);
        organization.executeAccountTransaction({
            account: account,
            to: scenario.to,
            value: scenario.value,
            data: scenario.data,
            salt: 16_302,
            expirationTimestamp: expiration,
            policyId: POLICY_ID,
            initiatorSignature: initiatorSignature,
            reviewSignatures: bytes(""),
            proofs: executionProofs
        });

        uint256 observedUsage = organization.getPolicyUsage(
            POLICY_ID, policy, account, scenario.destinationForUsage, initiatorSigner, proofs.policyProof
        );

        // Verify: the public usage getter matches the amount/count written by the execution path.
        assertEq(observedUsage, scenario.expectedUsage, "policy usage getter should match execution-path accounting");
    }

    /// @dev Verifies execute/reject nonce consumption is unaffected by interleaved recovery executions.
    /// @param organizationSalt CREATE2 salt used for organization deployment.
    /// @param accountSalt CREATE2 salt used for account deployment.
    /// @param txSaltRaw Raw salt used to derive the shared execute/reject nonce.
    /// @param rejectFirst Whether the rejection path should consume the nonce before the execute replay attempt.
    /// @param recoveryBeforeReplay Whether to place the recovery execution before or after the nonce-consuming path.
    function testFuzz_executeRejectAndRecoveryOrderingNeverReopensConsumedNonce(
        bytes32 organizationSalt,
        bytes32 accountSalt,
        uint256 txSaltRaw,
        bool rejectFirst,
        bool recoveryBeforeReplay
    ) public {
        // Setup: deploy a real organization/account pair, install one auto-approve policy, and enable tx recovery.
        OrganizationImplementationHarness organization = _deployOrganizationHarness(organizationSalt);
        address account = _deployAccount(
            organization, accountSalt, uint256(keccak256(abi.encodePacked("fcf-replay-165-deploy", accountSalt)))
        );
        vm.deal(account, 1 ether);

        Policy memory policy = _buildAutoApprovePolicy(initiatorSigner);
        ValidationProofs memory proofs = _setPoliciesAndBuildProofs(organization, POLICY_ID, policy, 16_501);

        vm.prank(TX_RECOVERY);
        organization.initiateEnableTransactionAndERC1271Recovery();
        vm.warp(organization.getTxRecoveryState().pendingEnableTimestamp);
        vm.prank(TX_RECOVERY);
        organization.finalizeEnableTransactionAndERC1271Recovery();

        uint256 txSalt = bound(txSaltRaw, 1, type(uint96).max);
        ReplayTransactionContext memory txContext = _buildReplayTransactionContext(organization, account, txSalt);

        if (recoveryBeforeReplay) {
            vm.prank(TX_RECOVERY);
            organization.executeRecoveryAccountTransaction(account, EXECUTION_RECIPIENT, 0.2 ether, bytes(""));
        }

        // Call: consume the shared nonce through one path, optionally run recovery, then replay the opposite path.
        if (rejectFirst) {
            vm.prank(GUARDIAN);
            organization.rejectAccountTransaction({
                account: account,
                to: EXECUTION_RECIPIENT,
                value: 0.2 ether,
                data: bytes(""),
                salt: txSalt,
                expirationTimestamp: txContext.expirationTimestamp,
                policyId: POLICY_ID,
                initiatorSignature: txContext.approvalSignature,
                reviewSignatures: txContext.rejectionSignature,
                proofs: proofs
            });
        } else {
            vm.prank(GUARDIAN);
            organization.executeAccountTransaction({
                account: account,
                to: EXECUTION_RECIPIENT,
                value: 0.2 ether,
                data: bytes(""),
                salt: txSalt,
                expirationTimestamp: txContext.expirationTimestamp,
                policyId: POLICY_ID,
                initiatorSignature: txContext.approvalSignature,
                reviewSignatures: bytes(""),
                proofs: proofs
            });
        }

        if (!recoveryBeforeReplay) {
            vm.prank(TX_RECOVERY);
            organization.executeRecoveryAccountTransaction(account, EXECUTION_RECIPIENT, 0.2 ether, bytes(""));
        }

        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, txContext.nonce));
        if (rejectFirst) {
            vm.prank(GUARDIAN);
            organization.executeAccountTransaction({
                account: account,
                to: EXECUTION_RECIPIENT,
                value: 0.2 ether,
                data: bytes(""),
                salt: txSalt,
                expirationTimestamp: txContext.expirationTimestamp,
                policyId: POLICY_ID,
                initiatorSignature: txContext.approvalSignature,
                reviewSignatures: bytes(""),
                proofs: proofs
            });
        } else {
            vm.prank(GUARDIAN);
            organization.rejectAccountTransaction({
                account: account,
                to: EXECUTION_RECIPIENT,
                value: 0.2 ether,
                data: bytes(""),
                salt: txSalt,
                expirationTimestamp: txContext.expirationTimestamp,
                policyId: POLICY_ID,
                initiatorSignature: txContext.approvalSignature,
                reviewSignatures: txContext.rejectionSignature,
                proofs: proofs
            });
        }

        // Verify: recovery ordering never clears the consumed nonce or re-enables replay.
        assertTrue(organization.getUsedNonce(txContext.nonce), "consumed account-transaction nonce must stay used");
        uint256 expectedExecutionRecipientBalance = rejectFirst ? 0.2 ether : 0.4 ether;
        assertEq(
            EXECUTION_RECIPIENT.balance,
            expectedExecutionRecipientBalance,
            "recovery ordering should preserve the expected execute/recovery transfer outcomes"
        );
    }

    /// @dev Verifies organization and account CREATE2 precomputes match their runtime deployments for fuzzed salts.
    /// @param organizationSalt CREATE2 salt used for organization deployment.
    /// @param accountSalt CREATE2 salt used for account deployment.
    function testFuzz_factoryAndAccountPrecomputesMatchRuntime(bytes32 organizationSalt, bytes32 accountSalt) public {
        // Setup: precompute both deployment addresses before executing the real factory and account-factory paths.
        address expectedOrganization =
            factory.computeOrganizationAddress(organizationSalt, address(lifecycleImplementation), address(whitelist));
        OrganizationImplementationHarness organization = _deployOrganizationHarness(organizationSalt);
        address expectedAccount = organization.computeAccountAddress(accountSalt);

        // Call: deploy the organization first, then deploy one account through the real guardian/admin flow.
        address deployedAccount = _deployAccount(
            organization, accountSalt, uint256(keccak256(abi.encodePacked("fcf-deploy-166-account", accountSalt)))
        );

        // Verify: both precomputed CREATE2 addresses match the runtime deployments exactly.
        assertEq(address(organization), expectedOrganization, "organization deployment should match factory precompute");
        assertEq(deployedAccount, expectedAccount, "account deployment should match organization precompute");
    }

    /// @dev Verifies guardian-update and deferred recovery-init timestamps all derive from the same org-wide admin
    /// timelock.
    /// @param organizationSalt CREATE2 salt used for organization deployment.
    /// @param adminTimelockRaw Raw admin-operation timelock seed bounded into the valid range.
    /// @param newGuardian Pending guardian used for the normal guardian-update flow.
    /// @param guardianRecoveryAddress Recovery address proposed through deferred guardian-recovery initialization.
    /// @param txRecoveryAddress Recovery address proposed through deferred tx-recovery initialization.
    function testFuzz_allPendingFinalizeTimestampsUseOrgWideAdminTimelock(
        bytes32 organizationSalt,
        uint256 adminTimelockRaw,
        address newGuardian,
        address guardianRecoveryAddress,
        address txRecoveryAddress
    ) public {
        vm.assume(newGuardian != address(0) && newGuardian != GUARDIAN);
        vm.assume(guardianRecoveryAddress != address(0));
        vm.assume(txRecoveryAddress != address(0));

        uint256 adminTimelock = bound(
            adminTimelockRaw, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );

        // Setup: deploy an organization whose deferred recovery-init paths are available and whose admin timelock is
        // fuzzed within the valid range.
        InitializationParams memory params = _buildInitializationParams(address(versionedAccountImplementationV1));
        params.adminOperationTimelockDurationSeconds = adminTimelock;
        params.guardianRecoveryAddress = address(0);
        params.guardianRecoveryTimelockDurationSeconds = 0;
        params.transactionAndERC1271RecoveryAddress = address(0);
        params.txRecoveryTimelockDurationSeconds = 0;

        OrganizationImplementationHarness organization = _deployOrganizationHarnessWithParams(organizationSalt, params);
        uint256 expectedPendingTimestamp = block.timestamp + adminTimelock;

        AdminAuthParams memory guardianAuth = _buildOperationAuth(
            organization, OperationType.InitiateUpdateGuardian, abi.encode(newGuardian), 16_701, true
        );
        AdminAuthParams memory guardianRecoveryAuth = _buildOperationAuth(
            organization,
            OperationType.InitiateInitializeGuardianRecovery,
            abi.encode(guardianRecoveryAddress, RECOVERY_TIMELOCK),
            16_702,
            true
        );
        AdminAuthParams memory txRecoveryAuth = _buildOperationAuth(
            organization,
            OperationType.InitiateInitializeTransactionRecovery,
            abi.encode(txRecoveryAddress, RECOVERY_TIMELOCK),
            16_703,
            true
        );

        // Call: initiate the three admin-timelocked flows that should all derive their finalize timestamp the same way.
        vm.prank(GUARDIAN);
        organization.initiateGuardianUpdate(newGuardian, guardianAuth);

        vm.prank(GUARDIAN);
        organization.initiateInitializeGuardianRecovery(
            guardianRecoveryAddress, RECOVERY_TIMELOCK, guardianRecoveryAuth
        );

        vm.prank(GUARDIAN);
        organization.initiateInitializeTransactionAndERC1271Recovery(
            txRecoveryAddress, RECOVERY_TIMELOCK, txRecoveryAuth
        );

        // Verify: every pending finalize timestamp equals `block.timestamp + adminOperationTimelockDurationSeconds`.
        assertEq(
            organization.adminOperationTimelockDurationSeconds(),
            adminTimelock,
            "organization should expose the fuzzed admin-operation timelock"
        );
        assertEq(
            organization.pendingGuardianUpdateTimestamp(),
            expectedPendingTimestamp,
            "guardian update should use the org-wide admin timelock"
        );
        assertEq(
            organization.getGuardianRecoveryState().pendingInit.pendingTimestamp,
            expectedPendingTimestamp,
            "guardian-recovery deferred init should use the org-wide admin timelock"
        );
        assertEq(
            organization.getTxRecoveryState().pendingInit.pendingTimestamp,
            expectedPendingTimestamp,
            "tx-recovery deferred init should use the org-wide admin timelock"
        );
    }

    /// @dev Builds valid initialization parameters whose admin signer matches the deterministic admin test key.
    /// @param accountImplementationAddress Account implementation configured during organization initialization.
    /// @return params The initialization parameters used for factory deployment in this suite.
    function _buildInitializationParams(address accountImplementationAddress)
        internal
        view
        returns (InitializationParams memory params)
    {
        params.members = buildArray(adminSigner, initiatorSigner);
        params.admins = buildArray(adminSigner);
        params.votingThreshold = 1;
        params.groups = new GroupModification[](0);
        params.guardian = GUARDIAN;
        params.accountImplementation = accountImplementationAddress;
        params.adminOperationTimelockDurationSeconds = ADMIN_OPERATION_TIMELOCK;
        params.transactionAndERC1271RecoveryAddress = TX_RECOVERY;
        params.txRecoveryTimelockDurationSeconds = RECOVERY_TIMELOCK;
        params.guardianRecoveryAddress = GUARDIAN_RECOVERY;
        params.guardianRecoveryTimelockDurationSeconds = RECOVERY_TIMELOCK;
    }

    /// @dev Deploys a real organization proxy through the factory and returns the proxy cast to the shared harness
    /// surface.
    /// @param salt CREATE2 salt used for organization deployment.
    /// @return organization The deployed organization proxy.
    function _deployOrganizationHarness(bytes32 salt)
        internal
        returns (OrganizationImplementationHarness organization)
    {
        organization = _deployOrganizationHarnessWithParams(
            salt, _buildInitializationParams(address(versionedAccountImplementationV1))
        );
    }

    /// @dev Deploys a real organization proxy through the factory using custom initialization parameters.
    /// @param salt CREATE2 salt used for organization deployment.
    /// @param params Initialization parameters forwarded into the factory deployment path.
    /// @return organization The deployed organization proxy.
    function _deployOrganizationHarnessWithParams(bytes32 salt, InitializationParams memory params)
        internal
        returns (OrganizationImplementationHarness organization)
    {
        vm.prank(AUTHORIZED_DEPLOYER);
        organization = OrganizationImplementationHarness(
            payable(factory.deployOrganization(salt, address(lifecycleImplementation), address(whitelist), params))
        );
    }

    /// @dev Publishes a single-leaf policy root and returns the matching empty-proof bundle.
    /// @param organization Organization whose policy root will be updated.
    /// @param policyId Policy identifier bound into the merkle leaf.
    /// @param policy Full policy payload stored in the leaf.
    /// @param salt Admin-auth salt for the `setPolicies` call.
    /// @return proofs Validation proofs matching the published single-leaf root.
    function _setPoliciesAndBuildProofs(
        OrganizationImplementationHarness organization,
        uint256 policyId,
        Policy memory policy,
        uint256 salt
    ) internal returns (ValidationProofs memory proofs) {
        bytes32 root = _computePolicyLeaf(policyId, policy);
        bytes memory operationData = abi.encode(root, keccak256(bytes(POLICY_IPFS_CID)));
        AdminAuthParams memory auth =
            _buildOperationAuth(organization, OperationType.ModifyPolicies, operationData, salt, true);

        vm.prank(GUARDIAN);
        organization.setPolicies(root, POLICY_IPFS_CID, auth);

        proofs = _buildEmptyProofs(policy);
    }

    /// @dev Deploys an account through the organization's guardian/admin-protected account-factory flow.
    /// @param organization Organization that will deploy the account.
    /// @param create2Salt CREATE2 salt used for the account proxy deployment.
    /// @param salt Admin-auth salt used for nonce derivation.
    /// @return account The deployed account proxy address.
    function _deployAccount(OrganizationImplementationHarness organization, bytes32 create2Salt, uint256 salt)
        internal
        returns (address account)
    {
        bytes memory operationData = abi.encode(create2Salt);
        AdminAuthParams memory auth =
            _buildOperationAuth(organization, OperationType.DeployAccount, operationData, salt, true);

        vm.prank(GUARDIAN);
        account = organization.deployAccount(create2Salt, auth);
    }

    /// @dev Upgrades the organization proxy to the pre-whitelisted v2 implementation.
    /// @param organization Organization proxy being upgraded.
    /// @param salt Admin-auth salt used for the upgrade nonce.
    function _upgradeOrganization(OrganizationImplementationHarness organization, uint256 salt) internal {
        bytes memory data = bytes("");
        bytes memory operationData = abi.encode(address(upgradedOrganizationImplementation), keccak256(data));
        AdminAuthParams memory auth =
            _buildOperationAuth(organization, OperationType.Upgrade, operationData, salt, true);

        vm.prank(GUARDIAN);
        organization.upgradeToAndCallWithAuthorization(address(upgradedOrganizationImplementation), data, auth);
    }

    /// @dev Completes the full normal guardian-update flow against the current organization proxy.
    /// @param organization Organization whose guardian will be rotated.
    /// @param newGuardian Pending guardian that will accept the role.
    /// @param initiateSalt Admin-auth salt for the initiate step.
    /// @param finalizeSalt Admin-auth salt for the finalize step.
    function _completeGuardianUpdate(
        OrganizationImplementationHarness organization,
        address newGuardian,
        uint256 initiateSalt,
        uint256 finalizeSalt
    ) internal {
        AdminAuthParams memory initiateAuth = _buildOperationAuth(
            organization, OperationType.InitiateUpdateGuardian, abi.encode(newGuardian), initiateSalt, true
        );
        vm.prank(GUARDIAN);
        organization.initiateGuardianUpdate(newGuardian, initiateAuth);

        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK);
        // forgefmt: disable-next-item
        AdminAuthParams memory finalizeAuth = _buildOperationAuth(
            organization, OperationType.FinalizeUpdateGuardian,
            abi.encode(newGuardian, organization.guardianUpdateAttemptId()), finalizeSalt, true
        );
        vm.prank(GUARDIAN);
        organization.finalizeGuardianUpdate(finalizeAuth);

        vm.prank(newGuardian);
        organization.acceptGuardian();
    }

    /// @dev Builds admin authorization for a specific operation tuple using the real organization's operation-hash
    /// helper.
    /// @param organization Organization proxy that computes the signed operation hash.
    /// @param operationType Operation domain being authorized.
    /// @param operationData ABI-encoded operation payload bound into the signature.
    /// @param salt Nonce salt included in the authorization.
    /// @param isApproval Whether the signatures authorize execution or rejection.
    /// @return auth Admin authorization payload ready for the target entrypoint.
    function _buildOperationAuth(
        OrganizationImplementationHarness organization,
        OperationType operationType,
        bytes memory operationData,
        uint256 salt,
        bool isApproval
    ) internal view returns (AdminAuthParams memory auth) {
        uint256 expirationTimestamp = block.timestamp + 30 days;
        bytes32 operationHash =
            organization.getAdminOperationHash(operationType, operationData, salt, expirationTimestamp, isApproval);
        bytes memory signatures = _buildSortedEoaSignatures(operationHash, _singlePrivateKeyArray(ADMIN_PK_1));
        auth = AdminAuthParams({salt: salt, expirationTimestamp: expirationTimestamp, signatures: signatures});
    }

    /// @dev Signs one initiator approval or rejection hash for a real organization/account transaction tuple.
    /// @param organization Organization address bound into the EIP-712 hash.
    /// @param account Source account authorized by the signature.
    /// @param to Destination address authorized by the signature.
    /// @param value Native-token value bound into the signature.
    /// @param data Calldata bound into the signature.
    /// @param salt User salt bound into the signature.
    /// @param expirationTimestamp Expiration timestamp bound into the signature.
    /// @param policyId Policy identifier bound into the signature.
    /// @param isApproval Whether to sign the approval or rejection variant.
    /// @return signature Canonical EOA signature bytes for the computed initiator hash.
    function _signInitiatorTransaction(
        address organization,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bool isApproval
    ) internal view returns (bytes memory signature) {
        signature = _signHash(
            INITIATOR_PK_1,
            _computeInitiatorTransactionHash(
                organization, account, to, value, data, salt, expirationTimestamp, policyId, isApproval
            )
        );
    }

    /// @dev Computes the public account-transaction nonce for a specific execution tuple.
    /// @param organization Organization that owns the nonce space.
    /// @param account Source account bound into the nonce.
    /// @param to Destination bound into the nonce.
    /// @param value Value bound into the nonce.
    /// @param data Calldata whose hash is bound into the nonce.
    /// @param policyId Policy identifier bound into the nonce.
    /// @param salt User salt bound into the nonce.
    /// @return nonce The nonce returned by the organization's public `computeNonce` view.
    function _computeAccountTransactionNonce(
        OrganizationImplementationHarness organization,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 policyId,
        uint256 salt
    ) internal view returns (uint256 nonce) {
        nonce = organization.computeNonce(
            OperationType.AccountTransaction, abi.encode(account, to, value, keccak256(data), policyId), salt
        );
    }

    /// @dev Builds the transaction fixture used by the policy-usage fuzz test.
    /// @param organizationSalt CREATE2 salt used for deterministic address derivation.
    /// @param accountSalt CREATE2 salt used for deterministic address derivation.
    /// @param amountRaw Fuzzed amount seed used to build calldata and expected usage.
    /// @param useTokenTransfer Whether to build a token-transfer or contract-interaction scenario.
    /// @return scenario The prepared transaction fixture and expected usage result.
    function _buildPolicyUsageScenario(
        bytes32 organizationSalt,
        bytes32 accountSalt,
        uint96 amountRaw,
        bool useTokenTransfer
    ) internal pure returns (PolicyUsageScenario memory scenario) {
        if (useTokenTransfer) {
            address token = address(
                uint160(uint256(keccak256(abi.encodePacked("fcf-rate-163-token", organizationSalt, accountSalt))))
            );
            address recipient = address(
                uint160(uint256(keccak256(abi.encodePacked("fcf-rate-163-recipient", organizationSalt, accountSalt))))
            );

            scenario = PolicyUsageScenario({
                transactionType: TransactionType.TokenTransfers,
                to: token,
                value: 0,
                data: abi.encodeWithSelector(
                    bytes4(0xa9059cbb), recipient, uint256(bound(uint256(amountRaw), 1, 1_000_000))
                ),
                destinationForUsage: recipient,
                expectedUsage: uint256(bound(uint256(amountRaw), 1, 1_000_000))
            });
            return scenario;
        }

        scenario = PolicyUsageScenario({
            transactionType: TransactionType.ContractInteractions,
            to: EXECUTION_RECIPIENT,
            value: 0,
            data: abi.encodeWithSelector(bytes4(0x51515151), uint256(amountRaw)),
            destinationForUsage: EXECUTION_RECIPIENT,
            expectedUsage: 1
        });
    }

    /// @dev Builds the shared signatures and nonce used by the replay-order fuzz test.
    /// @param organization The organization whose account-transaction domain is being exercised.
    /// @param account The account whose transaction tuple is being signed.
    /// @param txSalt The salt bound into the approval, rejection, and nonce tuple.
    /// @return txContext The prepared approval signature, rejection signature, expiration, and nonce.
    function _buildReplayTransactionContext(
        OrganizationImplementationHarness organization,
        address account,
        uint256 txSalt
    ) internal view returns (ReplayTransactionContext memory txContext) {
        bytes memory data = bytes("");
        uint256 expirationTimestamp = block.timestamp + 1 days;

        txContext = ReplayTransactionContext({
            expirationTimestamp: expirationTimestamp,
            approvalSignature: _signInitiatorTransaction({
                organization: address(organization),
                account: account,
                to: EXECUTION_RECIPIENT,
                value: 0.2 ether,
                data: data,
                salt: txSalt,
                expirationTimestamp: expirationTimestamp,
                policyId: POLICY_ID,
                isApproval: true
            }),
            rejectionSignature: _signInitiatorTransaction({
                organization: address(organization),
                account: account,
                to: EXECUTION_RECIPIENT,
                value: 0.2 ether,
                data: data,
                salt: txSalt,
                expirationTimestamp: expirationTimestamp,
                policyId: POLICY_ID,
                isApproval: false
            }),
            nonce: _computeAccountTransactionNonce({
                organization: organization,
                account: account,
                to: EXECUTION_RECIPIENT,
                value: 0.2 ether,
                data: data,
                policyId: POLICY_ID,
                salt: txSalt
            })
        });
    }

    /// @dev Builds the baseline auto-approve policy used by this suite's real end-to-end account-transaction flows.
    /// @param initiator Authorized member that may initiate transactions under the policy.
    /// @return policy The baseline policy object.
    function _buildAutoApprovePolicy(address initiator) internal pure returns (Policy memory policy) {
        policy = Policy({
            config: PolicyConfig({
                transactionType: TransactionType.Any,
                anySourceAccount: true,
                anyFunction: true,
                destinationType: DestinationType.Any,
                approval: ApprovalConfig({
                    policyType: PolicyType.AutoApprove,
                    approverType: ApproverType.Member,
                    approverMember: initiator,
                    approverGroupId: 0,
                    approvalThreshold: 1
                }),
                initiator: InitiatorConfig({
                    anyInitiator: false,
                    initiatorType: ApproverType.Member,
                    initiatorMember: initiator,
                    initiatorGroupId: 0
                }),
                token: TokenFilter({
                    anyToken: true, tokenAddress: address(0), hasAmountThreshold: false, amountThreshold: 0
                }),
                rateLimit: RateLimitConfig({
                    limitType: RateLimitType.None,
                    timeIntervalHours: 0,
                    timeIntervalLimit: 0,
                    anchorTimestamp: 0,
                    initiatorScope: RateLimitScope.AcrossAll,
                    sourceScope: RateLimitScope.AcrossAll,
                    destinationScope: RateLimitScope.AcrossAll
                }),
                valueThresholdForContractCalls: type(uint256).max
            }),
            roots: PolicyRoots({
                sourceAccountsRoot: bytes32(0), customDestinationsRoot: bytes32(0), allowedFunctionsRoot: bytes32(0)
            })
        });
    }

    /// @dev Returns the policy leaf used by the single-leaf policy-root tests in this suite.
    /// @param policyId Policy identifier bound into the leaf.
    /// @param policy Policy payload bound into the leaf.
    /// @return leaf The double-hashed policy leaf.
    function _computePolicyLeaf(uint256 policyId, Policy memory policy) internal pure returns (bytes32 leaf) {
        leaf = keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
    }

    /// @dev Builds an empty-proof bundle for a single-leaf policy root.
    /// @param policy Policy payload referenced by the proofs object.
    /// @return proofs Validation proofs with empty merkle branches.
    function _buildEmptyProofs(Policy memory policy) internal pure returns (ValidationProofs memory proofs) {
        bytes32[] memory emptyProof = new bytes32[](0);
        proofs = ValidationProofs({
            policy: policy,
            policyProof: emptyProof,
            sourceAccountProof: emptyProof,
            destinationProof: emptyProof,
            functionProof: emptyProof,
            constraints: bytes(""),
            constraintOneOfProofs: bytes("")
        });
    }

    /// @dev Computes the EIP-712 initiator hash used by real account-transaction signatures.
    /// @param organization Organization address used as the verifying contract.
    /// @param account Source account bound into the hash.
    /// @param to Destination bound into the hash.
    /// @param value Value bound into the hash.
    /// @param data Calldata bound into the hash.
    /// @param salt Salt bound into the hash.
    /// @param expirationTimestamp Expiration timestamp bound into the hash.
    /// @param policyId Policy identifier bound into the hash.
    /// @param isApproval Whether the approval or rejection variant should be hashed.
    /// @return hash The final typed-data hash signed by the initiator.
    function _computeInitiatorTransactionHash(
        address organization,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bool isApproval
    ) internal view returns (bytes32 hash) {
        bytes32 structHash = keccak256(
            abi.encode(
                INITIATE_ACCOUNT_TRANSACTION_TYPEHASH,
                account,
                to,
                value,
                keccak256(data),
                salt,
                expirationTimestamp,
                policyId,
                isApproval
            )
        );
        hash = _computeTypedDataHash(organization, structHash);
    }

    /// @dev Wraps a struct hash in the organization EIP-712 domain used by account-transaction signatures.
    /// @param organization Verifying contract address used in the domain separator.
    /// @param structHash The already-encoded EIP-712 struct hash.
    /// @return hash The final typed-data hash.
    function _computeTypedDataHash(address organization, bytes32 structHash) internal view returns (bytes32 hash) {
        hash = keccak256(abi.encodePacked("\x19\x01", _getDomainSeparator(organization), structHash));
    }

    /// @dev Computes the MLSWallet organization domain separator for the supplied verifying contract.
    /// @param organization Verifying contract address used by the domain.
    /// @return domainSeparator The organization EIP-712 domain separator.
    function _getDomainSeparator(address organization) internal view returns (bytes32 domainSeparator) {
        domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, ORGANIZATION_NAME_HASH, ORGANIZATION_VERSION_HASH, block.chainid, organization
            )
        );
    }

    /// @dev Sorts one or more admin EOA signatures into canonical signer order and concatenates them.
    /// @param operationHash Hash signed by each admin.
    /// @param privateKeys Admin private keys used to sign `operationHash`.
    /// @return signatures Concatenated canonical signatures.
    function _buildSortedEoaSignatures(bytes32 operationHash, uint256[] memory privateKeys)
        internal
        view
        returns (bytes memory signatures)
    {
        address[] memory signers = new address[](privateKeys.length);
        bytes[] memory builtSignatures = new bytes[](privateKeys.length);

        for (uint256 i = 0; i < privateKeys.length; ++i) {
            signers[i] = vm.addr(privateKeys[i]);
            builtSignatures[i] = _signHash(privateKeys[i], operationHash);
        }

        for (uint256 i = 0; i < signers.length; ++i) {
            for (uint256 j = i + 1; j < signers.length; ++j) {
                if (uint160(signers[j]) < uint160(signers[i])) {
                    (signers[i], signers[j]) = (signers[j], signers[i]);
                    (builtSignatures[i], builtSignatures[j]) = (builtSignatures[j], builtSignatures[i]);
                }
            }
        }

        signatures = _concatSignatures(builtSignatures);
    }

    /// @dev Verifies a weekly rate limit anchored to Monday midnight Eastern Time resets exactly on the
    ///      anchor-aligned boundary and not a second before.
    ///      Scenario: "Allow up to 2 transactions per week, refreshing every Monday at midnight ET."
    function test_anchorTimestamp_weeklyLimitResetsAtMondayMidnightET() public {
        // Monday March 4, 2024 00:00 ET = 05:00 UTC = 1_709_524_800
        uint256 anchor = 1_709_524_800;
        uint256 oneWeek = 604_800; // 168 hours * 3600

        // Step 1: Deploy Organization and Account, fund the Account.
        OrganizationImplementationHarness organization = _deployOrganizationHarness(bytes32(uint256(16_001)));
        Policy memory policy = _buildAutoApprovePolicy(initiatorSigner);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 168;
        policy.config.rateLimit.timeIntervalLimit = 2;
        policy.config.rateLimit.anchorTimestamp = anchor;

        // Step 2: Set the policy root.
        ValidationProofs memory proofs = _setPoliciesAndBuildProofs(organization, POLICY_ID, policy, 16_002);
        address account = _deployAccount(organization, bytes32(uint256(16_003)), 16_004);
        vm.deal(account, 10 ether);

        uint256 expiration = anchor + 30 days;
        bytes memory data = bytes("");

        // Step 3: Warp to Monday March 4 00:00 ET (start of window 0).
        vm.warp(anchor);

        // Step 4: Transaction 1 -- succeeds (usage = 1).
        vm.prank(GUARDIAN);
        organization.executeAccountTransaction({
            account: account,
            to: SECOND_RECIPIENT,
            value: 0.1 ether,
            data: data,
            salt: 16_005,
            expirationTimestamp: expiration,
            policyId: POLICY_ID,
            initiatorSignature: _signInitiatorTransaction({
                organization: address(organization),
                account: account,
                to: SECOND_RECIPIENT,
                value: 0.1 ether,
                data: data,
                salt: 16_005,
                expirationTimestamp: expiration,
                policyId: POLICY_ID,
                isApproval: true
            }),
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Step 5: Warp to Thursday March 7 00:00 ET (mid-week, still window 0).
        vm.warp(anchor + 3 * 86_400);

        // Step 6: Transaction 2 -- succeeds (usage = 2, limit reached).
        vm.prank(GUARDIAN);
        organization.executeAccountTransaction({
            account: account,
            to: SECOND_RECIPIENT,
            value: 0.1 ether,
            data: data,
            salt: 16_006,
            expirationTimestamp: expiration,
            policyId: POLICY_ID,
            initiatorSignature: _signInitiatorTransaction({
                organization: address(organization),
                account: account,
                to: SECOND_RECIPIENT,
                value: 0.1 ether,
                data: data,
                salt: 16_006,
                expirationTimestamp: expiration,
                policyId: POLICY_ID,
                isApproval: true
            }),
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Step 7: Transaction 3 -- should revert (limit exhausted within this week).
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, POLICY_ID));
        vm.prank(GUARDIAN);
        organization.executeAccountTransaction({
            account: account,
            to: SECOND_RECIPIENT,
            value: 0.1 ether,
            data: data,
            salt: 16_007,
            expirationTimestamp: expiration,
            policyId: POLICY_ID,
            initiatorSignature: _signInitiatorTransaction({
                organization: address(organization),
                account: account,
                to: SECOND_RECIPIENT,
                value: 0.1 ether,
                data: data,
                salt: 16_007,
                expirationTimestamp: expiration,
                policyId: POLICY_ID,
                isApproval: true
            }),
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Step 8: Warp to Sunday March 10 23:59:59 ET (one second before Monday midnight ET).
        //         The weekly window has NOT reset yet.
        vm.warp(anchor + oneWeek - 1);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, POLICY_ID));
        vm.prank(GUARDIAN);
        organization.executeAccountTransaction({
            account: account,
            to: SECOND_RECIPIENT,
            value: 0.1 ether,
            data: data,
            salt: 16_008,
            expirationTimestamp: expiration,
            policyId: POLICY_ID,
            initiatorSignature: _signInitiatorTransaction({
                organization: address(organization),
                account: account,
                to: SECOND_RECIPIENT,
                value: 0.1 ether,
                data: data,
                salt: 16_008,
                expirationTimestamp: expiration,
                policyId: POLICY_ID,
                isApproval: true
            }),
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Step 9: Warp to Monday March 11 00:00 ET (anchor-aligned boundary, start of window 1).
        vm.warp(anchor + oneWeek);

        // Step 10: Transaction 4 -- succeeds (new week, usage resets to 1).
        vm.prank(GUARDIAN);
        organization.executeAccountTransaction({
            account: account,
            to: SECOND_RECIPIENT,
            value: 0.1 ether,
            data: data,
            salt: 16_009,
            expirationTimestamp: expiration,
            policyId: POLICY_ID,
            initiatorSignature: _signInitiatorTransaction({
                organization: address(organization),
                account: account,
                to: SECOND_RECIPIENT,
                value: 0.1 ether,
                data: data,
                salt: 16_009,
                expirationTimestamp: expiration,
                policyId: POLICY_ID,
                isApproval: true
            }),
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Step 11: Transaction 5 -- succeeds (usage = 2, limit reached again).
        vm.prank(GUARDIAN);
        organization.executeAccountTransaction({
            account: account,
            to: SECOND_RECIPIENT,
            value: 0.1 ether,
            data: data,
            salt: 16_010,
            expirationTimestamp: expiration,
            policyId: POLICY_ID,
            initiatorSignature: _signInitiatorTransaction({
                organization: address(organization),
                account: account,
                to: SECOND_RECIPIENT,
                value: 0.1 ether,
                data: data,
                salt: 16_010,
                expirationTimestamp: expiration,
                policyId: POLICY_ID,
                isApproval: true
            }),
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Step 12: Transaction 6 -- should revert (limit exhausted again in the new week).
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, POLICY_ID));
        vm.prank(GUARDIAN);
        organization.executeAccountTransaction({
            account: account,
            to: SECOND_RECIPIENT,
            value: 0.1 ether,
            data: data,
            salt: 16_011,
            expirationTimestamp: expiration,
            policyId: POLICY_ID,
            initiatorSignature: _signInitiatorTransaction({
                organization: address(organization),
                account: account,
                to: SECOND_RECIPIENT,
                value: 0.1 ether,
                data: data,
                salt: 16_011,
                expirationTimestamp: expiration,
                policyId: POLICY_ID,
                isApproval: true
            }),
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        // Step 13: Verify usage for both windows.
        assertEq(
            organization.getPolicyUsage(
                POLICY_ID, policy, account, SECOND_RECIPIENT, initiatorSigner, proofs.policyProof
            ),
            2,
            "window 1 usage should be 2"
        );
        assertEq(SECOND_RECIPIENT.balance, 0.4 ether, "4 successful transactions of 0.1 ether each");
    }

    /// @dev Builds a one-element private-key array for single-admin auth helpers.
    /// @param privateKey The key to place at index zero.
    /// @return privateKeys One-element private-key array.
    function _singlePrivateKeyArray(uint256 privateKey) internal pure returns (uint256[] memory privateKeys) {
        privateKeys = new uint256[](1);
        privateKeys[0] = privateKey;
    }
}
