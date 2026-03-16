// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {MerkleUtils} from "libraries/MerkleUtils.sol";
import {BatchedTransaction} from "../../../src/safe-module/BatchedTransaction.sol";
import {SafeExecutorModule} from "../../../src/safe-module/SafeExecutorModule.sol";
import {SignatureTestHelpers} from "test/helpers/SignatureTestHelpers.sol";
import {
    MockERC20ForAccountTransaction,
    MockInteractionTarget,
    MockNativeReceiver
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseMocks.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {
    OrganizationImplementationHarness
} from "test/organization/shared/OrganizationUpgradeHarnesses.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {ContractType, GroupModification, InitializationParams, OperationType} from "types/CommonTypes.sol";
import {
    ApprovalConfig,
    ApproverType,
    ConstraintType,
    DestinationType,
    InitiatorConfig,
    ParamType,
    ParameterConstraint,
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

interface ISafeSetup {
    /// @dev Initializes the Safe proxy.
    function setup(
        address[] calldata owners,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;
}

interface ISafeModuleTx {
    /// @dev Returns the current Safe nonce.
    function nonce() external view returns (uint256);

    /// @dev Returns the transaction hash owners must sign.
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 nonce
    ) external view returns (bytes32);

    /// @dev Executes a Safe transaction after owner-signature validation.
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external returns (bool success);

    /// @dev Returns whether a module is currently enabled on the Safe.
    function isModuleEnabled(address module) external view returns (bool);
}

interface ISafeProxyFactory {
    /// @dev Deploys one Safe proxy initialized against the supplied singleton.
    function createProxyWithNonce(address singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
}

/**
 * @dev Real Safe-module end-to-end tests for Organization account-transaction flows.
 */
contract OrganizationAccountTransactionSafeModuleE2ETest is InitializationSuiteBase, SignatureTestHelpers {
    /// @dev Encapsulates the approval payload required to execute one account transaction through the module path.
    struct ModuleExecutionAuth {
        uint256 expirationTimestamp;
        bytes initiatorSignature;
        bytes reviewSignature;
    }

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant INITIATE_ACCOUNT_TRANSACTION_TYPEHASH = keccak256(
        "InitiateAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval,uint256 chainId)"
    );
    bytes32 internal constant REVIEW_ACCOUNT_TRANSACTION_TYPEHASH = keccak256(
        "ReviewAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval,uint256 chainId,bytes initiatorSignature)"
    );
    bytes32 internal constant FUNCTION_LEAF_TYPEHASH = keccak256("selector-constraints-leaf");
    bytes32 internal constant ORGANIZATION_NAME_HASH = keccak256("MLSWalletOrganization");
    bytes32 internal constant ORGANIZATION_VERSION_HASH = keccak256("1");

    uint256 internal constant ADMIN_PK_1 = 0xA11CE;
    uint256 internal constant INITIATOR_PK_1 = 0x91A0;
    uint256 internal constant REVIEWER_PK_1 = 0xA001;

    uint256 internal constant ETH_POLICY_ID = 19_801;
    uint256 internal constant ERC20_POLICY_ID = 19_802;
    uint256 internal constant INTERACTION_POLICY_ID = 19_803;

    string internal constant POLICY_IPFS_CID = "ipfs://19-integration-safe-module";
    string internal constant SAFE_L2_CREATION_CODE_PATH = "/test/fixtures/safe/SafeL2.creation.bin";
    string internal constant SAFE_PROXY_FACTORY_CREATION_CODE_PATH =
        "/test/fixtures/safe/SafeProxyFactory.creation.bin";

    address internal adminSigner;
    address internal initiatorSigner;
    address internal reviewerSigner;
    OrganizationImplementationHarness internal integrationImplementation;

    /**
     * @dev Seeds deterministic signer addresses and whitelists the concrete organization implementation.
     */
    function setUp() public override {
        super.setUp();

        adminSigner = vm.addr(ADMIN_PK_1);
        initiatorSigner = vm.addr(INITIATOR_PK_1);
        reviewerSigner = vm.addr(REVIEWER_PK_1);

        integrationImplementation = new OrganizationImplementationHarness();

        whitelist.setImplementationWhitelisted(ContractType.Organization, address(integrationImplementation), true);
        whitelist.setImplementationWhitelisted(ContractType.Account, address(accountImplementation), true);
    }

    /// @dev Verifies the full ETH-transfer execute path succeeds with a Safe-module guardian caller plus manual review
    /// signatures. [OAT-EAT-1]
    function test_OAT_EAT_1_executeAccountTransaction_safeModuleGuardianEthTransferFlow_succeeds() public {
        // Setup: deploy a real Safe guardian plus module, initialize the organization with that Safe as guardian, and
        // publish a manual-approval ETH-transfer policy.
        (address guardianSafe, SafeExecutorModule module) = _deployGuardianSafeModule(19_801);
        OrganizationImplementationHarness organization =
            _deployOrganizationHarness(bytes32(uint256(19_802)), _buildInitializationParams(guardianSafe));

        Policy memory policy = _buildManualApprovalPolicy(TransactionType.TokenTransfers);
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = address(0);
        ValidationProofs memory proofs = _setPoliciesViaModule(organization, module, ETH_POLICY_ID, policy, 19_803);

        address account = _deployAccountViaModule(organization, module, bytes32(uint256(19_804)), 19_805);
        MockNativeReceiver receiver = new MockNativeReceiver();
        uint256 transferValue = 0.4 ether;
        vm.deal(account, 1 ether);

        ModuleExecutionAuth memory auth = _buildModuleExecutionAuth(
            organization, account, address(receiver), transferValue, bytes(""), 19_806, ETH_POLICY_ID
        );

        // Call: execute the ETH transfer through `SafeExecutorModule.executeOnBehalf`, so the organization observes
        // the Safe as the guardian caller.
        _executeAccountTransactionViaModule({
            module: module,
            organization: organization,
            account: account,
            to: address(receiver),
            value: transferValue,
            data: bytes(""),
            salt: 19_806,
            expirationTimestamp: auth.expirationTimestamp,
            policyId: ETH_POLICY_ID,
            initiatorSignature: auth.initiatorSignature,
            reviewSignatures: auth.reviewSignature,
            proofs: proofs
        });

        // Verify: the receiver gets ETH, the predicted account remains organization-owned, and the Safe stays the
        // configured guardian throughout the flow.
        assertEq(receiver.totalReceived(), transferValue, "receiver should get the guarded ETH transfer");
        assertEq(organization.guardian(), guardianSafe, "guardian should remain the Safe module entrypoint owner");
        assertTrue(organization.isDeployedAccount(account), "deployed account should stay tracked by the organization");
    }

    /// @dev Verifies the full ERC-20 execute path succeeds with destination, token, and amount constraints enforced
    /// through a Safe-module guardian caller. [OAT-EAT-2]
    function test_OAT_EAT_2_executeAccountTransaction_safeModuleGuardianErc20TransferFlow_succeeds() public {
        // Setup: deploy a real Safe guardian plus module, initialize the organization with that Safe as guardian, and
        // publish a manual-approval ERC-20 policy constrained by recipient, token, and amount.
        (address guardianSafe, SafeExecutorModule module) = _deployGuardianSafeModule(19_821);
        OrganizationImplementationHarness organization =
            _deployOrganizationHarness(bytes32(uint256(19_822)), _buildInitializationParams(guardianSafe));

        MockERC20ForAccountTransaction token = new MockERC20ForAccountTransaction();
        address recipient = address(0xD4404);

        Policy memory policy = _buildManualApprovalPolicy(TransactionType.TokenTransfers);
        policy.config.destinationType = DestinationType.CustomList;
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = address(token);
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 251;
        (policy.roots.customDestinationsRoot, ) = _buildSingleAddressRootAndProof(recipient);

        ValidationProofs memory proofs = _setPoliciesViaModule(organization, module, ERC20_POLICY_ID, policy, 19_823);
        address account = _deployAccountViaModule(organization, module, bytes32(uint256(19_824)), 19_825);
        token.mint(account, 250);

        bytes memory data = abi.encodeWithSelector(token.transfer.selector, recipient, 250);
        ModuleExecutionAuth memory auth =
            _buildModuleExecutionAuth(organization, account, address(token), 0, data, 19_826, ERC20_POLICY_ID);

        // Call: execute the constrained ERC-20 transfer through the Safe-module guardian path.
        _executeAccountTransactionViaModule({
            module: module,
            organization: organization,
            account: account,
            to: address(token),
            value: 0,
            data: data,
            salt: 19_826,
            expirationTimestamp: auth.expirationTimestamp,
            policyId: ERC20_POLICY_ID,
            initiatorSignature: auth.initiatorSignature,
            reviewSignatures: auth.reviewSignature,
            proofs: proofs
        });

        // Verify: the configured recipient receives the exact constrained token amount and the Safe remains guardian.
        assertEq(token.balanceOf(recipient), 250, "recipient should get the constrained ERC-20 amount");
        assertEq(organization.guardian(), guardianSafe, "guardian should remain the Safe after ERC-20 execution");
    }

    /// @dev Verifies the full contract-interaction execute path succeeds with a whitelisted selector and exact
    /// parameter constraint enforced through a Safe-module guardian caller. [OAT-EAT-3]
    function test_OAT_EAT_3_executeAccountTransaction_safeModuleGuardianContractInteractionFlow_succeeds() public {
        // Setup: deploy a real Safe guardian plus module, initialize the organization with that Safe as guardian, and
        // publish a manual-approval contract-interaction policy constrained to `ping(uint256)` with `uint256(42)`.
        (address guardianSafe, SafeExecutorModule module) = _deployGuardianSafeModule(19_841);
        OrganizationImplementationHarness organization =
            _deployOrganizationHarness(bytes32(uint256(19_842)), _buildInitializationParams(guardianSafe));

        MockInteractionTarget target = new MockInteractionTarget();
        ParameterConstraint memory exactConstraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(42)),
            paramValueInListProof: new bytes32[](0)
        });
        bytes memory constraints = _encodeSingleConstraint(exactConstraint);

        Policy memory policy = _buildManualApprovalPolicy(TransactionType.ContractInteractions);
        policy.config.anyFunction = false;
        policy.roots.allowedFunctionsRoot = _computeFunctionLeaf(target.ping.selector, keccak256(constraints));

        ValidationProofs memory proofs =
            _setPoliciesViaModule(organization, module, INTERACTION_POLICY_ID, policy, 19_843);
        proofs.constraints = constraints;

        address account = _deployAccountViaModule(organization, module, bytes32(uint256(19_844)), 19_845);
        bytes memory data = abi.encodeWithSelector(target.ping.selector, uint256(42));
        ModuleExecutionAuth memory auth =
            _buildModuleExecutionAuth(organization, account, address(target), 0, data, 19_846, INTERACTION_POLICY_ID);

        // Call: execute the function-constrained contract interaction through the Safe-module guardian path.
        _executeAccountTransactionViaModule({
            module: module,
            organization: organization,
            account: account,
            to: address(target),
            value: 0,
            data: data,
            salt: 19_846,
            expirationTimestamp: auth.expirationTimestamp,
            policyId: INTERACTION_POLICY_ID,
            initiatorSignature: auth.initiatorSignature,
            reviewSignatures: auth.reviewSignature,
            proofs: proofs
        });

        // Verify: the target sees the account as caller, the exact parameter is applied, and the Safe remains
        // guardian-configured after execution.
        assertEq(target.calls(), 1, "target should be called once");
        assertEq(target.lastCaller(), account, "account should remain the downstream caller");
        assertEq(target.total(), 42, "exact constrained parameter should reach the target");
        assertEq(organization.guardian(), guardianSafe, "guardian should remain the Safe after interaction execution");
    }

    /**
     * @dev Deploys a Safe proxy, enables a `SafeExecutorModule`, and returns both addresses.
     * @param saltNonce Salt used for deterministic Safe proxy deployment.
     * @return safe Deployed Safe proxy address.
     * @return module Enabled Safe executor module authorized for `adminSigner`.
     */
    function _deployGuardianSafeModule(uint256 saltNonce)
        internal
        returns (address safe, SafeExecutorModule module)
    {
        address singleton = _deployCreationCodeFixture(SAFE_L2_CREATION_CODE_PATH);
        address proxyFactory = _deployCreationCodeFixture(SAFE_PROXY_FACTORY_CREATION_CODE_PATH);
        BatchedTransaction batchedTransaction = new BatchedTransaction();

        safe = _deploySafe(singleton, proxyFactory, saltNonce);
        module = new SafeExecutorModule(safe, adminSigner, address(batchedTransaction));
        _enableModuleOnSafe(safe, module);
    }

    /**
     * @dev Deploys constructor bytecode loaded from a fixture file under the repository root.
     * @param relativePath Fixture path relative to `vm.projectRoot()`.
     * @return deployed Address created from the supplied creation code.
     */
    function _deployCreationCodeFixture(string memory relativePath) internal returns (address deployed) {
        bytes memory creationCode = vm.readFileBinary(string.concat(vm.projectRoot(), relativePath));

        assembly {
            deployed := create(0, add(creationCode, 0x20), mload(creationCode))
        }

        require(deployed != address(0), "fixture deployment failed");
    }

    /**
     * @dev Builds initialization params that install the Safe as guardian and seed admin/initiator/reviewer members.
     * @param guardian Safe address that should own guardian-only organization entrypoints.
     * @return params Initialization payload used for factory deployment.
     */
    function _buildInitializationParams(address guardian) internal view returns (InitializationParams memory params) {
        params.members = buildArray(adminSigner, initiatorSigner, reviewerSigner);
        params.admins = buildArray(adminSigner);
        params.votingThreshold = 1;
        params.groups = new GroupModification[](0);
        params.guardian = guardian;
        params.accountImplementation = address(accountImplementation);
        params.adminOperationTimelockDurationSeconds = 2 days;
        params.transactionAndERC1271RecoveryAddress = address(0);
        params.txRecoveryTimelockDurationSeconds = 0;
        params.guardianRecoveryAddress = address(0);
        params.guardianRecoveryTimelockDurationSeconds = 0;
    }

    /**
     * @dev Deploys a real organization proxy through the shared factory and casts it to the harness surface.
     * @param salt CREATE2 salt used for organization deployment.
     * @param params Initialization payload forwarded through the factory deploy flow.
     * @return organization Deployed organization proxy.
     */
    function _deployOrganizationHarness(bytes32 salt, InitializationParams memory params)
        internal
        returns (OrganizationImplementationHarness organization)
    {
        vm.prank(AUTHORIZED_DEPLOYER);
        organization = OrganizationImplementationHarness(
            payable(factory.deployOrganization(salt, address(integrationImplementation), address(whitelist), params))
        );
    }

    /**
     * @dev Publishes a single-leaf policy root through the Safe-module guardian path.
     * @param organization Organization whose policy root will be updated.
     * @param module Enabled Safe executor module bound to the organization's guardian Safe.
     * @param policyId Policy identifier stored in the single-leaf root.
     * @param policy Policy payload stored in the single-leaf root.
     * @param salt Admin-auth salt used by `setPolicies`.
     * @return proofs Empty proof bundle matching the published single-leaf root.
     */
    function _setPoliciesViaModule(
        OrganizationImplementationHarness organization,
        SafeExecutorModule module,
        uint256 policyId,
        Policy memory policy,
        uint256 salt
    ) internal returns (ValidationProofs memory proofs) {
        bytes32 root = _computePolicyLeaf(policyId, policy);
        bytes memory operationData = abi.encode(root, keccak256(bytes(POLICY_IPFS_CID)));
        AdminAuthParams memory auth =
            _buildOperationAuth(organization, OperationType.ModifyPolicies, operationData, salt, true);

        vm.prank(adminSigner);
        module.executeOnBehalf(
            address(organization), abi.encodeCall(organization.setPolicies, (root, POLICY_IPFS_CID, auth))
        );

        proofs = _buildEmptyProofs(policy);
    }

    /**
     * @dev Deploys an organization account through the Safe-module guardian path and returns the predicted address.
     * @param organization Organization whose account factory will deploy the account.
     * @param module Enabled Safe executor module bound to the organization's guardian Safe.
     * @param create2Salt CREATE2 salt used by the organization account factory.
     * @param salt Admin-auth salt used by `deployAccount`.
     * @return account Predicted deployed account proxy address.
     */
    function _deployAccountViaModule(
        OrganizationImplementationHarness organization,
        SafeExecutorModule module,
        bytes32 create2Salt,
        uint256 salt
    ) internal returns (address account) {
        account = organization.computeAccountAddress(create2Salt);
        bytes memory operationData = abi.encode(create2Salt);
        AdminAuthParams memory auth =
            _buildOperationAuth(organization, OperationType.DeployAccount, operationData, salt, true);

        vm.prank(adminSigner);
        module.executeOnBehalf(address(organization), abi.encodeCall(organization.deployAccount, (create2Salt, auth)));
    }

    /**
     * @dev Executes `executeAccountTransaction` through the Safe-module guardian path.
     * @param module Enabled Safe executor module bound to the organization's guardian Safe.
     * @param organization Organization that will validate and execute the transaction.
     * @param account Source account proxy address.
     * @param to Destination address.
     * @param value Native-token value.
     * @param data Transaction calldata.
     * @param salt User-provided salt bound into the nonce and signatures.
     * @param expirationTimestamp Expiration timestamp bound into the signatures.
     * @param policyId Policy identifier referenced by the proofs.
     * @param initiatorSignature Initiator approval signature.
     * @param reviewSignatures Packed reviewer signatures.
     * @param proofs Policy proof bundle.
     */
    function _executeAccountTransactionViaModule(
        SafeExecutorModule module,
        OrganizationImplementationHarness organization,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes memory initiatorSignature,
        bytes memory reviewSignatures,
        ValidationProofs memory proofs
    ) internal {
        vm.prank(adminSigner);
        module.executeOnBehalf(
            address(organization),
            abi.encodeCall(
                organization.executeAccountTransaction,
                (
                    account,
                    to,
                    value,
                    data,
                    salt,
                    expirationTimestamp,
                    policyId,
                    initiatorSignature,
                    reviewSignatures,
                    proofs
                )
            )
        );
    }

    /**
     * @dev Builds the approval payload required for one module-routed account transaction.
     * @param organization Organization address bound into the EIP-712 hashes.
     * @param account Source account authorized by the signatures.
     * @param to Destination authorized by the signatures.
     * @param value Native-token value bound into the signatures.
     * @param data Calldata bound into the signatures.
     * @param salt Salt bound into the signatures and nonce.
     * @param policyId Policy identifier bound into the signatures.
     * @return auth Prepared initiator signature, review signature, and shared expiration timestamp.
     */
    function _buildModuleExecutionAuth(
        OrganizationImplementationHarness organization,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 policyId
    ) internal view returns (ModuleExecutionAuth memory auth) {
        uint256 expirationTimestamp = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signInitiatorTransaction({
            organization: address(organization),
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            isApproval: true
        });

        auth = ModuleExecutionAuth({
            expirationTimestamp: expirationTimestamp,
            initiatorSignature: initiatorSignature,
            reviewSignature: _signReviewTransaction({
                organization: address(organization),
                account: account,
                to: to,
                value: value,
                data: data,
                salt: salt,
                expirationTimestamp: expirationTimestamp,
                policyId: policyId,
                isApproval: true,
                initiatorSignature: initiatorSignature
            })
        });
    }

    /**
     * @dev Builds a baseline manual-approval policy for the requested transaction type.
     * @param transactionType Transaction type enforced by the policy.
     * @return policy Manual-approval policy seeded with deterministic initiator/reviewer fixtures.
     */
    function _buildManualApprovalPolicy(TransactionType transactionType) internal view returns (Policy memory policy) {
        policy = Policy({
            config: PolicyConfig({
                transactionType: transactionType,
                anySourceAccount: true,
                anyFunction: true,
                destinationType: DestinationType.Any,
                approval: ApprovalConfig({
                    policyType: PolicyType.RequireManualApproval,
                    approverType: ApproverType.Member,
                    approverMember: reviewerSigner,
                    approverGroupId: 0,
                    approvalThreshold: 1
                }),
                initiator: InitiatorConfig({
                    anyInitiator: false,
                    initiatorType: ApproverType.Member,
                    initiatorMember: initiatorSigner,
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
                })
            }),
            roots: PolicyRoots({
                sourceAccountsRoot: bytes32(0), customDestinationsRoot: bytes32(0), allowedFunctionsRoot: bytes32(0)
            })
        });
    }

    /**
     * @dev Deploys one Safe proxy configured with `adminSigner` as its only owner.
     * @param singleton Safe singleton implementation used by the proxy factory.
     * @param proxyFactory Safe proxy factory used for deployment.
     * @param saltNonce Salt used for deterministic Safe proxy deployment.
     * @return safe Deployed Safe proxy address.
     */
    function _deploySafe(address singleton, address proxyFactory, uint256 saltNonce) internal returns (address safe) {
        address[] memory owners = new address[](1);
        owners[0] = adminSigner;
        bytes memory initializer = abi.encodeWithSelector(
            ISafeSetup.setup.selector,
            owners,
            1,
            address(0),
            bytes(""),
            address(0),
            address(0),
            0,
            payable(address(0))
        );

        safe = ISafeProxyFactory(proxyFactory).createProxyWithNonce(singleton, initializer, saltNonce);
    }

    /**
     * @dev Enables the executor module on the Safe through a real owner-signed Safe transaction.
     * @param safe Safe proxy that should enable the module.
     * @param module Executor module to enable on the Safe.
     */
    function _enableModuleOnSafe(address safe, SafeExecutorModule module) internal {
        bytes memory enableModuleData = abi.encodeWithSignature("enableModule(address)", address(module));
        ISafeModuleTx safeProxy = ISafeModuleTx(safe);
        bytes32 txHash = safeProxy.getTransactionHash(
            safe,
            0,
            enableModuleData,
            0,
            0,
            0,
            0,
            address(0),
            address(0),
            safeProxy.nonce()
        );

        bool success = safeProxy.execTransaction(
            safe,
            0,
            enableModuleData,
            0,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            _signSafeHash(ADMIN_PK_1, txHash)
        );

        assertTrue(success, "safe should enable the executor module");
        assertTrue(safeProxy.isModuleEnabled(address(module)), "module should be enabled on the Safe");
    }

    /**
     * @dev Builds admin auth params for a concrete organization operation tuple.
     * @param organization Organization that computes the signed admin-operation hash.
     * @param operationType Organization operation protected by admin auth.
     * @param operationData ABI-encoded operation payload bound into the hash.
     * @param salt Nonce salt bound into the auth.
     * @param isApproval Whether the signatures authorize execution or rejection.
     * @return auth Packed admin auth params ready for the organization entrypoint.
     */
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
        bytes memory signatures = _buildSortedEOASignatures(operationHash, _singlePrivateKeyArray(ADMIN_PK_1));
        auth = AdminAuthParams({salt: salt, expirationTimestamp: expirationTimestamp, signatures: signatures});
    }

    /**
     * @dev Signs the initiator hash for an account-transaction approval or rejection request.
     * @param organization Organization address used as the EIP-712 verifying contract.
     * @param account Source account bound into the hash.
     * @param to Destination address bound into the hash.
     * @param value Native-token value bound into the hash.
     * @param data Calldata bound into the hash.
     * @param salt Salt bound into the hash.
     * @param expirationTimestamp Expiration timestamp bound into the hash.
     * @param policyId Policy identifier bound into the hash.
     * @param isApproval Whether to sign the approval or rejection variant.
     * @return signature Canonical initiator signature bytes.
     */
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

    /**
     * @dev Signs the reviewer hash for an account-transaction approval or rejection request.
     * @param organization Organization address used as the EIP-712 verifying contract.
     * @param account Source account bound into the hash.
     * @param to Destination address bound into the hash.
     * @param value Native-token value bound into the hash.
     * @param data Calldata bound into the hash.
     * @param salt Salt bound into the hash.
     * @param expirationTimestamp Expiration timestamp bound into the hash.
     * @param policyId Policy identifier bound into the hash.
     * @param isApproval Whether to sign the approval or rejection variant.
     * @param initiatorSignature Initiator signature bytes bound into the reviewer hash.
     * @return signature Canonical reviewer signature bytes.
     */
    function _signReviewTransaction(
        address organization,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bool isApproval,
        bytes memory initiatorSignature
    ) internal view returns (bytes memory signature) {
        signature = _signHash(
            REVIEWER_PK_1,
            _computeReviewTransactionHash(
                organization, account, to, value, data, salt, expirationTimestamp, policyId, isApproval, initiatorSignature
            )
        );
    }

    /**
     * @dev Computes the EIP-712 initiator hash used by `executeAccountTransaction`.
     * @param organization Organization address used as the verifying contract.
     * @param account Source account bound into the hash.
     * @param to Destination bound into the hash.
     * @param value Native-token value bound into the hash.
     * @param data Calldata bound into the hash.
     * @param salt Salt bound into the hash.
     * @param expirationTimestamp Expiration timestamp bound into the hash.
     * @param policyId Policy identifier bound into the hash.
     * @param isApproval Whether the approval or rejection variant should be hashed.
     * @return hash Typed-data hash signed by the initiator.
     */
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
                organization,
                account,
                to,
                value,
                keccak256(data),
                salt,
                expirationTimestamp,
                policyId,
                isApproval,
                block.chainid
            )
        );
        hash = _computeTypedDataHash(organization, structHash);
    }

    /**
     * @dev Computes the EIP-712 reviewer hash used by `executeAccountTransaction`.
     * @param organization Organization address used as the verifying contract.
     * @param account Source account bound into the hash.
     * @param to Destination bound into the hash.
     * @param value Native-token value bound into the hash.
     * @param data Calldata bound into the hash.
     * @param salt Salt bound into the hash.
     * @param expirationTimestamp Expiration timestamp bound into the hash.
     * @param policyId Policy identifier bound into the hash.
     * @param isApproval Whether the approval or rejection variant should be hashed.
     * @param initiatorSignature Initiator signature bytes bound into the reviewer hash.
     * @return hash Typed-data hash signed by the reviewer.
     */
    function _computeReviewTransactionHash(
        address organization,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bool isApproval,
        bytes memory initiatorSignature
    ) internal view returns (bytes32 hash) {
        bytes32 structHash = keccak256(
            abi.encode(
                REVIEW_ACCOUNT_TRANSACTION_TYPEHASH,
                organization,
                account,
                to,
                value,
                keccak256(data),
                salt,
                expirationTimestamp,
                policyId,
                isApproval,
                block.chainid,
                keccak256(initiatorSignature)
            )
        );
        hash = _computeTypedDataHash(organization, structHash);
    }

    /**
     * @dev Wraps a struct hash in the organization EIP-712 domain.
     * @param organization Organization address used as the verifying contract.
     * @param structHash Struct hash to domain-wrap.
     * @return hash Final typed-data hash.
     */
    function _computeTypedDataHash(address organization, bytes32 structHash) internal view returns (bytes32 hash) {
        hash = keccak256(abi.encodePacked("\x19\x01", _getDomainSeparator(organization), structHash));
    }

    /**
     * @dev Computes the MLSWallet organization EIP-712 domain separator for one organization.
     * @param organization Organization address used as the verifying contract.
     * @return domainSeparator Organization domain separator.
     */
    function _getDomainSeparator(address organization) internal view returns (bytes32 domainSeparator) {
        domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, ORGANIZATION_NAME_HASH, ORGANIZATION_VERSION_HASH, block.chainid, organization
            )
        );
    }

    /**
     * @dev Computes the double-hashed policy leaf used by organization policy roots.
     * @param policyId Policy identifier bound into the leaf.
     * @param policy Policy payload bound into the leaf.
     * @return leaf Double-hashed policy leaf.
     */
    function _computePolicyLeaf(uint256 policyId, Policy memory policy) internal pure returns (bytes32 leaf) {
        leaf = keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
    }

    /**
     * @dev Computes the single function leaf used by contract-interaction allowlists.
     * @param selector Function selector bound into the leaf.
     * @param constraintsHash Hash of the ABI-encoded parameter constraints.
     * @return leaf Double-hashed function leaf.
     */
    function _computeFunctionLeaf(bytes4 selector, bytes32 constraintsHash) internal pure returns (bytes32 leaf) {
        leaf = keccak256(bytes.concat(keccak256(abi.encode(selector, constraintsHash))));
    }

    /**
     * @dev Builds a single-leaf address root and its matching empty proof.
     * @param allowedAddress Sole address authorized by the root.
     * @return root Singleton address-tree root.
     * @return proof Empty singleton proof.
     */
    function _buildSingleAddressRootAndProof(address allowedAddress)
        internal
        pure
        returns (bytes32 root, bytes32[] memory proof)
    {
        proof = new bytes32[](0);
        root = MerkleUtils.computeAddressLeaf(allowedAddress);
    }

    /**
     * @dev Builds an empty-proof validation bundle for a single-leaf policy root.
     * @param policy Policy payload referenced by the proof bundle.
     * @return proofs Empty proof bundle for the supplied policy.
     */
    function _buildEmptyProofs(Policy memory policy) internal pure returns (ValidationProofs memory proofs) {
        bytes32[] memory empty = new bytes32[](0);
        proofs = ValidationProofs({
            policy: policy,
            policyProof: empty,
            sourceAccountProof: empty,
            destinationProof: empty,
            functionProof: empty,
            constraints: bytes("")
        });
    }

    /**
     * @dev Encodes a one-element `ParameterConstraint[]` payload.
     * @param constraint Sole constraint stored in the returned array.
     * @return encoded ABI-encoded single-element constraint array.
     */
    function _encodeSingleConstraint(ParameterConstraint memory constraint)
        internal
        pure
        returns (bytes memory encoded)
    {
        ParameterConstraint[] memory constraints = new ParameterConstraint[](1);
        constraints[0] = constraint;
        encoded = abi.encode(constraints);
    }

    /**
     * @dev Sorts one or more EOA signatures by signer address and concatenates them in canonical order.
     * @param operationHash Hash each signer should sign.
     * @param privateKeys Private keys that will sign `operationHash`.
     * @return signatures Canonically ordered concatenated signatures.
     */
    function _buildSortedEOASignatures(bytes32 operationHash, uint256[] memory privateKeys)
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

    /**
     * @dev Builds a one-element private-key array for single-admin auth helpers.
     * @param privateKey Sole private key stored in the returned array.
     * @return privateKeys One-element private-key array.
     */
    function _singlePrivateKeyArray(uint256 privateKey) internal pure returns (uint256[] memory privateKeys) {
        privateKeys = new uint256[](1);
        privateKeys[0] = privateKey;
    }

    /**
     * @dev Signs one Safe transaction hash in Safe's `{r}{s}{v}` owner-signature format.
     * @param privateKey Owner private key used for signing.
     * @param hash Safe transaction hash returned by `getTransactionHash`.
     * @return signature Safe-compatible owner signature.
     */
    function _signSafeHash(uint256 privateKey, bytes32 hash) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        if (uint256(s) > HALF_CURVE_ORDER) {
            s = bytes32(SECP256K1_CURVE_ORDER - uint256(s));
            v = v == 27 ? 28 : 27;
        }

        signature = abi.encodePacked(r, s, v);
    }
}
