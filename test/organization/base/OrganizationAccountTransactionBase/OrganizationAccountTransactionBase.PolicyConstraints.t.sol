// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {OrganizationGroupsBase} from "organization/base/OrganizationGroupsBase.sol";
import {OrganizationMembersBase} from "organization/base/OrganizationMembersBase.sol";
import {
    OrganizationAccountTransactionBaseHarness
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseHarness.sol";
import {
    MockAccountForOrganizationTransaction,
    MockERC20ForAccountTransaction,
    MockInteractionTarget,
    MockNativeReceiver
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseMocks.sol";
import {
    OrganizationAccountTransactionTestBase
} from "test/organization/shared/OrganizationAccountTransactionTestBase.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";
import {
    ApproverType,
    ConstraintType,
    DestinationType,
    ParamType,
    ParameterConstraint,
    Policy,
    PolicyType,
    RateLimitScope,
    RateLimitType,
    TransactionType,
    ValidationProofs
} from "types/PolicyTypes.sol";

/**
 * @dev Test-local composite harness that combines account-transaction validation wrappers with the real group/member
 *      mutation entrypoints used to create stale membership state.
 */
contract OrganizationAccountTransactionPolicyConstraintsHarness is
    OrganizationAccountTransactionBaseHarness,
    OrganizationMembersBase,
    OrganizationGroupsBase
{}

/**
 * @dev Direct execute/reject-path policy constraint tests for `OrganizationAccountTransactionBase`.
 */
contract OrganizationAccountTransactionBasePolicyConstraintsTest is OrganizationAccountTransactionTestBase {
    uint256 internal constant NON_MEMBER_PK = 0xD15EA5E;

    /// @dev Concrete harness used by this suite.
    OrganizationAccountTransactionBaseHarness internal harness;

    /**
     * @dev Deploys the composite harness so this suite can use real mutation entrypoints and account-transaction
     *      execution against the same storage.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new OrganizationAccountTransactionPolicyConstraintsHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Verifies `executeAccountTransaction` rejects disallowed source accounts and allows any-source policies
     *      across different deployed accounts. [OPB-SAF-1, OPB-SAF-2]
     */
    function test_OPB_SAF_1__OPB_SAF_2__POL_INV_3_executeAccountTransaction_sourceAccountPolicies_requireProofOrAllowAnySource()
        public
    {
        // Setup: deploy two organization accounts plus one interaction target, then bind a specific-source policy to
        // only the first account.
        MockAccountForOrganizationTransaction accountA = _deployMockAccount();
        MockAccountForOrganizationTransaction accountB = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory data = abi.encodeWithSelector(target.ping.selector, uint256(11));

        Policy memory specificSourcePolicy =
            _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        specificSourcePolicy.config.anySourceAccount = false;
        bytes32[] memory sourceProof;
        (specificSourcePolicy.roots.sourceAccountsRoot, sourceProof) =
            _buildSingleAddressRootAndProof(address(accountA));

        ValidationProofs memory specificSourceProofs = _setSinglePolicyRootAndBuildProofs(9001, specificSourcePolicy);
        specificSourceProofs.sourceAccountProof = sourceProof;

        (bytes memory allowedSig, uint256 allowedExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountA), address(target), 0, data, 1, 9001);

        // Call: execute the specific-source policy from the proofed account.
        _executeAsGuardian(
            address(accountA),
            address(target),
            0,
            data,
            1,
            allowedExpiration,
            9001,
            allowedSig,
            bytes(""),
            specificSourceProofs
        );

        // Verify: the allowed source account reaches the downstream target exactly once.
        assertEq(target.calls(), 1, "proofed source account should execute successfully");
        assertEq(target.lastCaller(), address(accountA), "successful call should originate from the proofed account");

        (bytes memory deniedSig, uint256 deniedExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountB), address(target), 0, data, 2, 9001);

        // Call: execute the same policy from a different deployed account, expecting the source-account gate to fail.
        _expectPolicyDoesNotApply(9001);
        _executeAsGuardian(
            address(accountB),
            address(target),
            0,
            data,
            2,
            deniedExpiration,
            9001,
            deniedSig,
            bytes(""),
            specificSourceProofs
        );

        Policy memory anySourcePolicy =
            _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        anySourcePolicy.config.anySourceAccount = true;
        ValidationProofs memory anySourceProofs = _setSinglePolicyRootAndBuildProofs(9002, anySourcePolicy);

        (bytes memory anySourceSigA, uint256 anySourceExpirationA) =
            _signExecution(INITIATOR_PK_1, address(accountA), address(target), 0, data, 3, 9002);
        (bytes memory anySourceSigB, uint256 anySourceExpirationB) =
            _signExecution(INITIATOR_PK_1, address(accountB), address(target), 0, data, 4, 9002);

        // Call: re-run through an any-source policy from both accounts.
        _executeAsGuardian(
            address(accountA),
            address(target),
            0,
            data,
            3,
            anySourceExpirationA,
            9002,
            anySourceSigA,
            bytes(""),
            anySourceProofs
        );
        _executeAsGuardian(
            address(accountB),
            address(target),
            0,
            data,
            4,
            anySourceExpirationB,
            9002,
            anySourceSigB,
            bytes(""),
            anySourceProofs
        );

        // Verify: the any-source policy authorizes both deployed accounts under the same policy root.
        assertEq(target.calls(), 3, "both accounts should execute under any-source policy");
        assertEq(target.lastCaller(), address(accountB), "second any-source execution should come from account B");
    }

    /**
     * @dev Verifies native-transfer destination custom lists check the `to` address, native-token filters reject
     *      policies that do not allow ETH, and amount thresholds apply as an inclusive `<=` boundary. [OPB-DV-1,
     *      OPB-TAT-1, OPB-TAT-3]
     */
    function test_OPB_DV_1__OPB_TAT_1__OPB_TAT_3_executeAccountTransaction_nativeTransferPolicies_checkDestinationTokenAndThreshold()
        public
    {
        // Setup: fund one deployed account and build a native-transfer policy that only allows ETH to one receiver.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockNativeReceiver allowedReceiver = new MockNativeReceiver();
        MockNativeReceiver deniedReceiver = new MockNativeReceiver();
        uint256 transferValue = 0.4 ether;
        vm.deal(address(account), 1 ether);

        Policy memory allowedPolicy = _buildApprovalPolicy(TransactionType.TokenTransfers, PolicyType.AutoApprove);
        allowedPolicy.config.destinationType = DestinationType.CustomList;
        allowedPolicy.config.token.anyToken = false;
        allowedPolicy.config.token.tokenAddress = address(0);
        allowedPolicy.config.token.hasAmountThreshold = true;
        allowedPolicy.config.token.amountThreshold = 0.5 ether;
        bytes32[] memory allowedDestinationProof;
        (allowedPolicy.roots.customDestinationsRoot, allowedDestinationProof) =
            _buildSingleAddressRootAndProof(address(allowedReceiver));

        ValidationProofs memory allowedProofs = _setSinglePolicyRootAndBuildProofs(9010, allowedPolicy);
        allowedProofs.destinationProof = allowedDestinationProof;
        (bytes memory allowedSig, uint256 allowedExpiration) = _signExecution(
            INITIATOR_PK_1, address(account), address(allowedReceiver), transferValue, bytes(""), 10, 9010
        );

        // Call: execute the native ETH transfer to the proofed receiver.
        _executeAsGuardian(
            address(account),
            address(allowedReceiver),
            transferValue,
            bytes(""),
            10,
            allowedExpiration,
            9010,
            allowedSig,
            bytes(""),
            allowedProofs
        );

        // Verify: the whitelisted native receiver gets the forwarded ETH.
        assertEq(allowedReceiver.totalReceived(), transferValue, "allowed receiver should get native transfer");

        (bytes memory thresholdSig, uint256 thresholdExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(allowedReceiver), 0.5 ether, bytes(""), 13, 9010);

        // Call: retry at the exact configured threshold, expecting the inclusive `<= threshold` rule to allow it.
        _executeAsGuardian(
            address(account),
            address(allowedReceiver),
            0.5 ether,
            bytes(""),
            13,
            thresholdExpiration,
            9010,
            thresholdSig,
            bytes(""),
            allowedProofs
        );

        // Verify: the exact-threshold native transfer is also allowed.
        assertEq(allowedReceiver.totalReceived(), transferValue + 0.5 ether, "threshold amount should be allowed");

        Policy memory deniedDestinationPolicy =
            _buildApprovalPolicy(TransactionType.TokenTransfers, PolicyType.AutoApprove);
        deniedDestinationPolicy.config.destinationType = DestinationType.CustomList;
        deniedDestinationPolicy.config.token.anyToken = false;
        deniedDestinationPolicy.config.token.tokenAddress = address(0);
        bytes32[] memory deniedDestinationProof;
        (deniedDestinationPolicy.roots.customDestinationsRoot, deniedDestinationProof) =
            _buildSingleAddressRootAndProof(address(deniedReceiver));

        ValidationProofs memory deniedDestinationProofs =
            _setSinglePolicyRootAndBuildProofs(9011, deniedDestinationPolicy);
        deniedDestinationProofs.destinationProof = deniedDestinationProof;
        (bytes memory deniedDestinationSig, uint256 deniedDestinationExpiration) = _signExecution(
            INITIATOR_PK_1, address(account), address(allowedReceiver), transferValue, bytes(""), 11, 9011
        );

        // Call: retry against an unlisted native receiver, expecting the destination gate to fail before execution.
        _expectPolicyDoesNotApply(9011);
        _executeAsGuardian(
            address(account),
            address(allowedReceiver),
            transferValue,
            bytes(""),
            11,
            deniedDestinationExpiration,
            9011,
            deniedDestinationSig,
            bytes(""),
            deniedDestinationProofs
        );

        Policy memory deniedTokenPolicy = allowedPolicy;
        deniedTokenPolicy.config.token.tokenAddress = address(0xC0FFEE);
        ValidationProofs memory deniedTokenProofs = _setSinglePolicyRootAndBuildProofs(9012, deniedTokenPolicy);
        deniedTokenProofs.destinationProof = allowedDestinationProof;
        (bytes memory deniedTokenSig, uint256 deniedTokenExpiration) = _signExecution(
            INITIATOR_PK_1, address(account), address(allowedReceiver), transferValue, bytes(""), 12, 9012
        );

        // Call: retry with a policy that disallows the native token, expecting the token filter to fail closed.
        _expectPolicyDoesNotApply(9012);
        _executeAsGuardian(
            address(account),
            address(allowedReceiver),
            transferValue,
            bytes(""),
            12,
            deniedTokenExpiration,
            9012,
            deniedTokenSig,
            bytes(""),
            deniedTokenProofs
        );

        // Verify: only the two allowed branches transfer ETH; the failed branches add nothing further.
        assertEq(
            allowedReceiver.totalReceived(),
            transferValue + 0.5 ether,
            "failed native-policy branches must not add ETH beyond successful transfers"
        );
        assertEq(deniedReceiver.totalReceived(), 0, "unlisted receiver should remain unfunded");
    }

    /**
     * @dev Verifies ERC-20 transfers use the recipient argument for destination checks and bind the allowed token
     *      contract. [OPB-DV-2, OPB-TAT-2]
     */
    function test_OPB_DV_2__OPB_TAT_2__TXRL_INV_11_executeAccountTransaction_erc20TransferPolicies_checkRecipientAndToken()
        public
    {
        // Setup: deploy one account plus two token contracts, then fund the account with both token balances.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockERC20ForAccountTransaction allowedToken = new MockERC20ForAccountTransaction();
        MockERC20ForAccountTransaction otherToken = new MockERC20ForAccountTransaction();
        allowedToken.mint(address(account), 500);
        otherToken.mint(address(account), 500);

        Policy memory allowedPolicy = _buildApprovalPolicy(TransactionType.TokenTransfers, PolicyType.AutoApprove);
        allowedPolicy.config.destinationType = DestinationType.CustomList;
        allowedPolicy.config.token.anyToken = false;
        allowedPolicy.config.token.tokenAddress = address(allowedToken);
        bytes32[] memory recipientProof;
        (allowedPolicy.roots.customDestinationsRoot, recipientProof) = _buildSingleAddressRootAndProof(RECIPIENT);

        ValidationProofs memory allowedProofs = _setSinglePolicyRootAndBuildProofs(9020, allowedPolicy);
        allowedProofs.destinationProof = recipientProof;
        bytes memory hundredTokenTransfer = _encodeErc20Transfer(RECIPIENT, 100);
        (bytes memory allowedSig, uint256 allowedExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(allowedToken), 0, hundredTokenTransfer, 20, 9020);

        // Call: execute an allowed ERC-20 transfer that stays below the configured threshold.
        _executeAsGuardian(
            address(account),
            address(allowedToken),
            0,
            hundredTokenTransfer,
            20,
            allowedExpiration,
            9020,
            allowedSig,
            bytes(""),
            allowedProofs
        );

        // Verify: the recipient receives tokens from the whitelisted token contract.
        assertEq(allowedToken.balanceOf(RECIPIENT), 100, "allowed ERC-20 transfer should succeed");

        Policy memory recipientOnlyPolicy = _buildApprovalPolicy(TransactionType.TokenTransfers, PolicyType.AutoApprove);
        recipientOnlyPolicy.config.destinationType = DestinationType.CustomList;
        recipientOnlyPolicy.config.token.anyToken = false;
        recipientOnlyPolicy.config.token.tokenAddress = address(allowedToken);
        bytes32[] memory tokenAddressProof;
        (recipientOnlyPolicy.roots.customDestinationsRoot, tokenAddressProof) =
            _buildSingleAddressRootAndProof(address(allowedToken));

        ValidationProofs memory recipientOnlyProofs = _setSinglePolicyRootAndBuildProofs(9021, recipientOnlyPolicy);
        recipientOnlyProofs.destinationProof = tokenAddressProof;
        bytes memory recipientCheckData = _encodeErc20Transfer(RECIPIENT, 10);
        (bytes memory recipientOnlySig, uint256 recipientOnlyExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(allowedToken), 0, recipientCheckData, 21, 9021);

        // Call: present a proof for the token contract instead of the transfer recipient, expecting destination
        // validation to reject it.
        _expectPolicyDoesNotApply(9021);
        _executeAsGuardian(
            address(account),
            address(allowedToken),
            0,
            recipientCheckData,
            21,
            recipientOnlyExpiration,
            9021,
            recipientOnlySig,
            bytes(""),
            recipientOnlyProofs
        );

        ValidationProofs memory wrongTokenProofs = _setSinglePolicyRootAndBuildProofs(9022, allowedPolicy);
        wrongTokenProofs.destinationProof = recipientProof;
        (bytes memory wrongTokenSig, uint256 wrongTokenExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(otherToken), 0, recipientCheckData, 22, 9022);

        // Call: retry against a different token contract, expecting the token filter to reject it.
        _expectPolicyDoesNotApply(9022);
        _executeAsGuardian(
            address(account),
            address(otherToken),
            0,
            recipientCheckData,
            22,
            wrongTokenExpiration,
            9022,
            wrongTokenSig,
            bytes(""),
            wrongTokenProofs
        );

        // Verify: only the allowed-token transfer lands on the recipient.
        assertEq(allowedToken.balanceOf(RECIPIENT), 100, "only allowed-token recipient transfers should succeed");
        assertEq(otherToken.balanceOf(RECIPIENT), 0, "wrong-token branch must not transfer tokens");
    }

    /**
     * @dev Verifies `DestinationType.Any` allows a native transfer to any destination without requiring a destination
     * proof. [OPB-DV-4]
     */
    function test_OPB_DV_4_executeAccountTransaction_destinationTypeAny_allowsUnlistedDestinationWithoutProof() public {
        // Setup: fund one deployed account and build a native-transfer policy that leaves destination checks fully
        // open.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockNativeReceiver receiver = new MockNativeReceiver();
        uint256 transferValue = 0.35 ether;
        vm.deal(address(account), 1 ether);

        Policy memory policy = _buildApprovalPolicy(TransactionType.TokenTransfers, PolicyType.AutoApprove);
        policy.config.destinationType = DestinationType.Any;
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = address(0);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(9023, policy);
        (bytes memory signature, uint256 expirationTimestamp) =
            _signExecution(INITIATOR_PK_1, address(account), address(receiver), transferValue, bytes(""), 23, 9023);

        // Call: execute the ETH transfer without supplying any destination proof.
        _executeAsGuardian(
            address(account),
            address(receiver),
            transferValue,
            bytes(""),
            23,
            expirationTimestamp,
            9023,
            signature,
            bytes(""),
            proofs
        );

        // Verify: the unconstrained destination branch succeeds and transfers ETH to the arbitrary receiver.
        assertEq(receiver.totalReceived(), transferValue, "destinationType any should not require a destination proof");
    }

    /**
     * @dev Verifies disabling the token-amount threshold allows any transfer amount that otherwise matches the
     * policy. [OPB-TAT-4]
     */
    function test_OPB_TAT_4_executeAccountTransaction_amountThresholdDisabled_allowsAnyAmount() public {
        // Setup: fund one deployed account and build a native-transfer policy with threshold enforcement disabled.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockNativeReceiver receiver = new MockNativeReceiver();
        uint256 transferValue = 0.9 ether;
        vm.deal(address(account), 1 ether);

        Policy memory policy = _buildApprovalPolicy(TransactionType.TokenTransfers, PolicyType.AutoApprove);
        policy.config.destinationType = DestinationType.Any;
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = address(0);
        policy.config.token.hasAmountThreshold = false;
        policy.config.token.amountThreshold = 1;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(9024, policy);
        (bytes memory signature, uint256 expirationTimestamp) =
            _signExecution(INITIATOR_PK_1, address(account), address(receiver), transferValue, bytes(""), 24, 9024);

        // Call: execute a large native transfer that would exceed the stored threshold if threshold checks were
        // enabled.
        _executeAsGuardian(
            address(account),
            address(receiver),
            transferValue,
            bytes(""),
            24,
            expirationTimestamp,
            9024,
            signature,
            bytes(""),
            proofs
        );

        // Verify: disabling the threshold lets the transfer succeed for the full requested amount.
        assertEq(receiver.totalReceived(), transferValue, "disabled amount threshold should allow any transfer value");
    }

    /**
     * @dev Verifies function allowlists bind selector plus constraint hash, reject calldata shorter than 4 bytes,
     *      and enforce exact static-parameter matches. [OPB-FAPC-1, OPB-FAPC-3, OPB-FAPC-4]
     */
    function test_OPB_FAPC_1__OPB_FAPC_3__OPB_FAPC_4__POL_INV_10_executeAccountTransaction_staticFunctionPolicies_failClosed()
        public
    {
        // Setup: deploy one account plus one interaction target, then allow only `ping(uint256)` with an exact
        // `uint256(7)` constraint.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();

        ParameterConstraint memory exactSeven = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(7)),
            paramValueInListProof: new bytes32[](0)
        });
        bytes memory sevenConstraints = _encodeSingleConstraint(exactSeven);

        Policy memory policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        policy.config.anyFunction = false;
        bytes32[] memory functionProof;
        (policy.roots.allowedFunctionsRoot, functionProof) =
            _buildSingleFunctionRootAndProof(target.ping.selector, sevenConstraints);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(9040, policy);
        proofs.functionProof = functionProof;
        proofs.constraints = sevenConstraints;

        bytes memory allowedData = abi.encodeWithSelector(target.ping.selector, uint256(7));
        (bytes memory allowedSig, uint256 allowedExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, allowedData, 40, 9040);

        // Call: execute the allowed selector with the exact allowed static argument.
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            allowedData,
            40,
            allowedExpiration,
            9040,
            allowedSig,
            bytes(""),
            proofs
        );

        // Verify: the allowed selector and exact parameter succeed through the real execute path.
        assertEq(target.calls(), 1, "exact static parameter should pass");
        assertEq(target.total(), 7, "allowed static argument should reach the target");

        ParameterConstraint memory exactEight = exactSeven;
        exactEight.comparisonData = abi.encode(uint256(8));
        ValidationProofs memory mismatchedConstraintHashProofs = proofs;
        mismatchedConstraintHashProofs.constraints = _encodeSingleConstraint(exactEight);
        (bytes memory mismatchedConstraintHashSig, uint256 mismatchedConstraintHashExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, allowedData, 41, 9040);

        // Call: reuse the selector proof but change the constraint bytes, expecting the selector+constraints leaf
        // binding to reject it.
        _expectPolicyDoesNotApply(9040);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            allowedData,
            41,
            mismatchedConstraintHashExpiration,
            9040,
            mismatchedConstraintHashSig,
            bytes(""),
            mismatchedConstraintHashProofs
        );

        bytes memory shortData = hex"010203";
        (bytes memory shortSig, uint256 shortExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, shortData, 42, 9040);

        // Call: execute calldata shorter than one selector, expecting the allowlist path to fail closed.
        _expectPolicyDoesNotApply(9040);
        _executeAsGuardian(
            address(account), address(target), 0, shortData, 42, shortExpiration, 9040, shortSig, bytes(""), proofs
        );

        bytes memory wrongStaticValueData = abi.encodeWithSelector(target.ping.selector, uint256(8));
        (bytes memory wrongStaticValueSig, uint256 wrongStaticValueExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, wrongStaticValueData, 43, 9040);

        // Call: execute the allowed selector with the wrong static argument, expecting the exact constraint to fail.
        _expectPolicyDoesNotApply(9040);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            wrongStaticValueData,
            43,
            wrongStaticValueExpiration,
            9040,
            wrongStaticValueSig,
            bytes(""),
            proofs
        );
    }

    /**
     * @dev Verifies dynamic bytes exact constraints accept matching payloads and reject mismatched, head-overlap, or
     *      truncated calldata. [OPB-FAPC-5, OPB-FAPC-6, OPB-FAPC-7]
     */
    function test_OPB_FAPC_5__OPB_FAPC_6__OPB_FAPC_7_executeAccountTransaction_dynamicBytesConstraints_failClosed()
        public
    {
        // Setup: deploy one account plus one interaction target, then allow only `storePayload(bytes)` with one exact
        // bytes payload hash.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory expectedPayload = hex"CAFECAFE";
        bytes memory differentPayload = hex"DEADBEEF";

        ParameterConstraint memory payloadConstraint = ParameterConstraint({
            paramType: ParamType.Bytes,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(keccak256(expectedPayload)),
            paramValueInListProof: new bytes32[](0)
        });
        bytes memory payloadConstraints = _encodeSingleConstraint(payloadConstraint);

        Policy memory policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        policy.config.anyFunction = false;
        bytes32[] memory functionProof;
        (policy.roots.allowedFunctionsRoot, functionProof) =
            _buildSingleFunctionRootAndProof(target.storePayload.selector, payloadConstraints);

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(9050, policy);
        proofs.functionProof = functionProof;
        proofs.constraints = payloadConstraints;

        bytes memory matchingData = abi.encodeWithSelector(target.storePayload.selector, expectedPayload);
        (bytes memory matchingSig, uint256 matchingExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, matchingData, 50, 9050);

        // Call: execute the allowed dynamic-bytes payload.
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            matchingData,
            50,
            matchingExpiration,
            9050,
            matchingSig,
            bytes(""),
            proofs
        );

        // Verify: the exact bytes payload reaches the target and stores the expected hash.
        assertEq(target.payloadHash(), keccak256(expectedPayload), "matching bytes payload should succeed");

        bytes memory mismatchedData = abi.encodeWithSelector(target.storePayload.selector, differentPayload);
        (bytes memory mismatchedSig, uint256 mismatchedExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, mismatchedData, 51, 9050);

        // Call: execute the same selector with different bytes, expecting the exact constraint to reject it.
        _expectPolicyDoesNotApply(9050);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            mismatchedData,
            51,
            mismatchedExpiration,
            9050,
            mismatchedSig,
            bytes(""),
            proofs
        );

        // casting to bytes3 is safe because hex"AABBCC" is exactly 3 bytes
        // forge-lint: disable-next-item(unsafe-typecast)
        bytes memory badOffsetData =
            bytes.concat(target.storePayload.selector, abi.encode(uint256(31), uint256(3), bytes3(hex"AABBCC")));
        (bytes memory badOffsetSig, uint256 badOffsetExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, badOffsetData, 52, 9050);

        // Call: execute a dynamic-bytes payload whose offset points into the ABI head region, expecting fail-closed
        // validation.
        _expectPolicyDoesNotApply(9050);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            badOffsetData,
            52,
            badOffsetExpiration,
            9050,
            badOffsetSig,
            bytes(""),
            proofs
        );

        bytes memory truncatedData =
            bytes.concat(target.storePayload.selector, abi.encode(uint256(32), uint256(10)), hex"AABBCCDD");
        (bytes memory truncatedSig, uint256 truncatedExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, truncatedData, 53, 9050);

        // Call: execute a dynamic-bytes payload whose declared length runs past `data.length`, expecting fail-closed
        // validation.
        _expectPolicyDoesNotApply(9050);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            truncatedData,
            53,
            truncatedExpiration,
            9050,
            truncatedSig,
            bytes(""),
            proofs
        );
    }

    /**
     * @dev Verifies `anyFunction=true` allows arbitrary selectors and calldata without requiring a function proof.
     * [OPB-FAPC-2]
     */
    function test_OPB_FAPC_2_executeAccountTransaction_anyFunction_allowsAnySelectorAndCalldata() public {
        // Setup: deploy one account plus one interaction target and build a contract-interaction policy with
        // `anyFunction=true`.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory data = abi.encodeWithSelector(target.storePayload.selector, hex"CAFECAFE");

        Policy memory policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        policy.config.destinationType = DestinationType.Any;
        policy.config.anyFunction = true;

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(9051, policy);
        (bytes memory signature, uint256 expirationTimestamp) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 54, 9051);

        // Call: execute an arbitrary selector with arbitrary calldata and no function proof.
        _executeAsGuardian(
            address(account), address(target), 0, data, 54, expirationTimestamp, 9051, signature, bytes(""), proofs
        );

        // Verify: the interaction succeeds and the unconstrained payload reaches the target unchanged.
        assertEq(target.calls(), 1, "anyFunction should allow arbitrary selector execution");
        assertEq(target.payloadHash(), keccak256(hex"CAFECAFE"), "arbitrary calldata should reach the target");
    }

    /**
     * @dev Verifies per-entity rate-limit scopes separate initiator/account/destination budgets, while an all-shared
     *      scope collapses them into one budget. [OPB-RL-1, OPB-RL-2, OPB-RL-3, OPB-RL-4]
     */
    function test_OPB_RL_1__OPB_RL_2__OPB_RL_3__OPB_RL_4__TXRL_INV_3_executeAccountTransaction_rateLimitScopes_chargeExpectedKeys()
        public
    {
        // Setup: deploy two accounts and two interaction targets for four scoped-rate-limit subcases.
        MockAccountForOrganizationTransaction accountA = _deployMockAccount();
        MockAccountForOrganizationTransaction accountB = _deployMockAccount();
        MockInteractionTarget targetA = new MockInteractionTarget();
        MockInteractionTarget targetB = new MockInteractionTarget();
        bytes memory data = abi.encodeWithSelector(targetA.ping.selector, uint256(1));

        Policy memory initiatorScopedPolicy = _buildRateLimitedContractPolicy(
            RateLimitScope.PerEntity, RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, true
        );
        ValidationProofs memory initiatorScopedProofs = _setSinglePolicyRootAndBuildProofs(9060, initiatorScopedPolicy);
        (bytes memory initiatorOneSig, uint256 initiatorOneExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountA), address(targetA), 0, data, 60, 9060);
        (bytes memory initiatorTwoSig, uint256 initiatorTwoExpiration) =
            _signExecution(INITIATOR_PK_2, address(accountA), address(targetA), 0, data, 61, 9060);

        // Call: execute twice under a per-initiator policy with two different initiators.
        _executeAsGuardian(
            address(accountA),
            address(targetA),
            0,
            data,
            60,
            initiatorOneExpiration,
            9060,
            initiatorOneSig,
            bytes(""),
            initiatorScopedProofs
        );
        _executeAsGuardian(
            address(accountA),
            address(targetA),
            0,
            data,
            61,
            initiatorTwoExpiration,
            9060,
            initiatorTwoSig,
            bytes(""),
            initiatorScopedProofs
        );

        // Verify: each initiator accrues usage against a separate key.
        uint256 initiatorWindow = _computeTimeWindow(initiatorScopedPolicy);
        assertEq(
            harness.getPolicyUsage(
                _computeUsageKey(9060, initiatorScopedPolicy, address(accountA), address(targetA), initiator1),
                initiatorWindow
            ),
            1,
            "initiator one should have an isolated budget"
        );
        assertEq(
            harness.getPolicyUsage(
                _computeUsageKey(9060, initiatorScopedPolicy, address(accountA), address(targetA), initiator2),
                initiatorWindow
            ),
            1,
            "initiator two should have an isolated budget"
        );

        Policy memory sourceScopedPolicy = _buildRateLimitedContractPolicy(
            RateLimitScope.AcrossAll, RateLimitScope.PerEntity, RateLimitScope.AcrossAll, false
        );
        ValidationProofs memory sourceScopedProofs = _setSinglePolicyRootAndBuildProofs(9061, sourceScopedPolicy);
        (bytes memory sourceAccountASig, uint256 sourceAccountAExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountA), address(targetA), 0, data, 62, 9061);
        (bytes memory sourceAccountBSig, uint256 sourceAccountBExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountB), address(targetA), 0, data, 63, 9061);

        // Call: execute twice under a per-source-account policy with two different accounts.
        _executeAsGuardian(
            address(accountA),
            address(targetA),
            0,
            data,
            62,
            sourceAccountAExpiration,
            9061,
            sourceAccountASig,
            bytes(""),
            sourceScopedProofs
        );
        _executeAsGuardian(
            address(accountB),
            address(targetA),
            0,
            data,
            63,
            sourceAccountBExpiration,
            9061,
            sourceAccountBSig,
            bytes(""),
            sourceScopedProofs
        );

        // Verify: each source account accrues usage against a separate key.
        uint256 sourceWindow = _computeTimeWindow(sourceScopedPolicy);
        assertEq(
            harness.getPolicyUsage(
                _computeUsageKey(9061, sourceScopedPolicy, address(accountA), address(targetA), initiator1),
                sourceWindow
            ),
            1,
            "account A should have an isolated source budget"
        );
        assertEq(
            harness.getPolicyUsage(
                _computeUsageKey(9061, sourceScopedPolicy, address(accountB), address(targetA), initiator1),
                sourceWindow
            ),
            1,
            "account B should have an isolated source budget"
        );

        Policy memory destinationScopedPolicy = _buildRateLimitedContractPolicy(
            RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, RateLimitScope.PerEntity, false
        );
        ValidationProofs memory destinationScopedProofs =
            _setSinglePolicyRootAndBuildProofs(9062, destinationScopedPolicy);
        (bytes memory destinationASig, uint256 destinationAExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountA), address(targetA), 0, data, 64, 9062);
        bytes memory dataToTargetB = abi.encodeWithSelector(targetB.ping.selector, uint256(1));
        (bytes memory destinationBSig, uint256 destinationBExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountA), address(targetB), 0, dataToTargetB, 65, 9062);

        // Call: execute twice under a per-destination policy with two different destinations.
        _executeAsGuardian(
            address(accountA),
            address(targetA),
            0,
            data,
            64,
            destinationAExpiration,
            9062,
            destinationASig,
            bytes(""),
            destinationScopedProofs
        );
        _executeAsGuardian(
            address(accountA),
            address(targetB),
            0,
            dataToTargetB,
            65,
            destinationBExpiration,
            9062,
            destinationBSig,
            bytes(""),
            destinationScopedProofs
        );

        // Verify: each destination accrues usage against a separate key.
        uint256 destinationWindow = _computeTimeWindow(destinationScopedPolicy);
        assertEq(
            harness.getPolicyUsage(
                _computeUsageKey(9062, destinationScopedPolicy, address(accountA), address(targetA), initiator1),
                destinationWindow
            ),
            1,
            "target A should have an isolated destination budget"
        );
        assertEq(
            harness.getPolicyUsage(
                _computeUsageKey(9062, destinationScopedPolicy, address(accountA), address(targetB), initiator1),
                destinationWindow
            ),
            1,
            "target B should have an isolated destination budget"
        );

        Policy memory acrossAllPolicy = _buildRateLimitedContractPolicy(
            RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, true
        );
        ValidationProofs memory acrossAllProofs = _setSinglePolicyRootAndBuildProofs(9063, acrossAllPolicy);
        (bytes memory sharedBudgetSig, uint256 sharedBudgetExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountA), address(targetA), 0, data, 66, 9063);
        (bytes memory exhaustedBudgetSig, uint256 exhaustedBudgetExpiration) =
            _signExecution(INITIATOR_PK_2, address(accountB), address(targetB), 0, dataToTargetB, 67, 9063);

        // Call: consume the shared budget once, then retry from a different account, destination, and initiator.
        _executeAsGuardian(
            address(accountA),
            address(targetA),
            0,
            data,
            66,
            sharedBudgetExpiration,
            9063,
            sharedBudgetSig,
            bytes(""),
            acrossAllProofs
        );
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, 9063));
        _executeAsGuardian(
            address(accountB),
            address(targetB),
            0,
            dataToTargetB,
            67,
            exhaustedBudgetExpiration,
            9063,
            exhaustedBudgetSig,
            bytes(""),
            acrossAllProofs
        );

        // Verify: the across-all scope collapses all entities into one shared usage key.
        uint256 acrossAllWindow = _computeTimeWindow(acrossAllPolicy);
        assertEq(
            harness.getPolicyUsage(
                _computeUsageKey(9063, acrossAllPolicy, address(accountA), address(targetA), initiator1),
                acrossAllWindow
            ),
            1,
            "shared scope should store exactly one usage unit"
        );
    }

    /**
     * @dev Verifies rate-limit usage resets after a time window passes and that the exact boundary already belongs to
     *      the new window. [OPB-RL-5, OPB-RL-6]
     */
    function test_OPB_RL_5__OPB_RL_6__TXRL_INV_2_executeAccountTransaction_rateLimitWindows_resetAfterBoundary()
        public
    {
        // Setup: deploy one account plus one interaction target, then use a one-call-per-hour policy for two
        // time-window subcases.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory data = abi.encodeWithSelector(target.ping.selector, uint256(1));

        Policy memory rolloverPolicy = _buildRateLimitedContractPolicy(
            RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, false
        );
        ValidationProofs memory rolloverProofs = _setSinglePolicyRootAndBuildProofs(9070, rolloverPolicy);

        vm.warp(1);
        (bytes memory firstWindowSig, uint256 firstWindowExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 70, 9070);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            data,
            70,
            firstWindowExpiration,
            9070,
            firstWindowSig,
            bytes(""),
            rolloverProofs
        );
        uint256 firstWindow = _computeTimeWindow(rolloverPolicy);

        vm.warp(3601);
        (bytes memory secondWindowSig, uint256 secondWindowExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 71, 9070);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            data,
            71,
            secondWindowExpiration,
            9070,
            secondWindowSig,
            bytes(""),
            rolloverProofs
        );
        uint256 secondWindow = _computeTimeWindow(rolloverPolicy);

        // Verify: usage from the old window does not carry into the next window after the boundary passes.
        bytes32 rolloverKey = _computeUsageKey(9070, rolloverPolicy, address(account), address(target), initiator1);
        assertEq(harness.getPolicyUsage(rolloverKey, firstWindow), 1, "old window should retain its own usage");
        assertEq(harness.getPolicyUsage(rolloverKey, secondWindow), 1, "new window should start fresh");

        Policy memory exactBoundaryPolicy = _buildRateLimitedContractPolicy(
            RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, false
        );
        ValidationProofs memory exactBoundaryProofs = _setSinglePolicyRootAndBuildProofs(9071, exactBoundaryPolicy);

        vm.warp(7199);
        (bytes memory beforeBoundarySig, uint256 beforeBoundaryExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 72, 9071);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            data,
            72,
            beforeBoundaryExpiration,
            9071,
            beforeBoundarySig,
            bytes(""),
            exactBoundaryProofs
        );
        uint256 beforeBoundaryWindow = _computeTimeWindow(exactBoundaryPolicy);

        vm.warp(7200);
        (bytes memory onBoundarySig, uint256 onBoundaryExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 73, 9071);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            data,
            73,
            onBoundaryExpiration,
            9071,
            onBoundarySig,
            bytes(""),
            exactBoundaryProofs
        );
        uint256 onBoundaryWindow = _computeTimeWindow(exactBoundaryPolicy);

        // Verify: the transaction executed at the exact boundary uses the new window instead of the exhausted old one.
        bytes32 boundaryKey = _computeUsageKey(9071, exactBoundaryPolicy, address(account), address(target), initiator1);
        assertEq(harness.getPolicyUsage(boundaryKey, beforeBoundaryWindow), 1, "pre-boundary window should stay full");
        assertEq(harness.getPolicyUsage(boundaryKey, onBoundaryWindow), 1, "boundary execution should use fresh window");
    }

    /**
     * @dev Verifies rejection does not mutate rate-limit usage and rate-limit overflows fail closed with
     *      `RateLimitExceeded`. [OPB-RL-7, OPB-RL-8]
     */
    function test_OPB_RL_7__OPB_RL_8__OAT_RAT_4__TXRL_INV_4__TXRL_INV_8_executeAccountTransaction_rejectionAndOverflow_leaveUsageSafe()
        public
    {
        // Setup: deploy one account plus one interaction target, then prepare one rate-limited auto-approve policy.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory data = abi.encodeWithSelector(target.ping.selector, uint256(1));

        Policy memory policy = _buildRateLimitedContractPolicy(
            RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, false
        );
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(9080, policy);

        (bytes memory approvalSig, uint256 approvalExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 80, 9080);
        bytes memory rejectionSig =
            _signRejection(INITIATOR_PK_1, address(account), address(target), 0, data, 80, approvalExpiration, 9080);
        bytes32 usageKey = _computeUsageKey(9080, policy, address(account), address(target), initiator1);
        uint256 window = _computeTimeWindow(policy);

        // Call: reject one tuple first, then execute a different tuple under the same policy.
        vm.prank(GUARDIAN);
        harness.rejectAccountTransaction({
            account: address(account),
            to: address(target),
            value: 0,
            data: data,
            salt: 80,
            expirationTimestamp: approvalExpiration,
            policyId: 9080,
            initiatorSignature: approvalSig,
            reviewSignatures: rejectionSig,
            proofs: proofs
        });
        assertEq(harness.getPolicyUsage(usageKey, window), 0, "rejection should not consume any rate-limit usage");

        (bytes memory executedSig, uint256 executedExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 81, 9080);
        _executeAsGuardian(
            address(account), address(target), 0, data, 81, executedExpiration, 9080, executedSig, bytes(""), proofs
        );

        // Verify: the later execution still sees the pre-rejection usage and consumes exactly one unit.
        assertEq(harness.getPolicyUsage(usageKey, window), 1, "post-rejection execution should start from zero usage");

        Policy memory overflowPolicy = policy;
        overflowPolicy.config.rateLimit.timeIntervalLimit = type(uint256).max;
        ValidationProofs memory overflowProofs = _setSinglePolicyRootAndBuildProofs(9081, overflowPolicy);
        bytes32 overflowKey = _computeUsageKey(9081, overflowPolicy, address(account), address(target), initiator1);
        harness.setPolicyUsage(overflowKey, window, type(uint256).max);

        (bytes memory overflowSig, uint256 overflowExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 82, 9081);

        // Call: execute when usage addition would overflow `uint256`, expecting the fail-closed rate-limit error.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, 9081));
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            data,
            82,
            overflowExpiration,
            9081,
            overflowSig,
            bytes(""),
            overflowProofs
        );

        // Verify: overflow rejection preserves the seeded saturated usage value.
        assertEq(harness.getPolicyUsage(overflowKey, window), type(uint256).max, "overflow path must not wrap usage");
    }

    /**
     * @dev Verifies zero-threshold manual group approvals are rejected and `anyInitiator=true` still requires
     *      organization membership. [OPB-AIA-1, OPB-AIA-2]
     */
    function test_OPB_AIA_1__OPB_AIA_2__POL_INV_7_executeAccountTransaction_manualZeroThresholdAndNonMemberInitiator_failClosed()
        public
    {
        // Setup: deploy one account plus one interaction target, then prepare one zero-threshold manual policy and one
        // any-initiator policy signed by a non-member.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory data = abi.encodeWithSelector(target.ping.selector, uint256(1));

        Policy memory zeroThresholdPolicy =
            _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.RequireManualApproval);
        zeroThresholdPolicy.config.approval.approverType = ApproverType.Group;
        zeroThresholdPolicy.config.approval.approverGroupId = 880;
        zeroThresholdPolicy.config.approval.approvalThreshold = 0;
        harness.setGroupStatus(880, true);
        harness.setGroupMemberStatus(880, reviewer1, true);

        ValidationProofs memory zeroThresholdProofs = _setSinglePolicyRootAndBuildProofs(9090, zeroThresholdPolicy);
        (bytes memory zeroThresholdSig, uint256 zeroThresholdExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 90, 9090);

        // Call: execute with a manual group policy whose threshold resolves to zero, expecting fail-closed approval
        // validation.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 0, 0));
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            data,
            90,
            zeroThresholdExpiration,
            9090,
            zeroThresholdSig,
            bytes(""),
            zeroThresholdProofs
        );

        Policy memory anyInitiatorPolicy =
            _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        anyInitiatorPolicy.config.initiator.anyInitiator = true;
        ValidationProofs memory anyInitiatorProofs = _setSinglePolicyRootAndBuildProofs(9091, anyInitiatorPolicy);
        (bytes memory nonMemberSig, uint256 nonMemberExpiration) =
            _signExecution(NON_MEMBER_PK, address(account), address(target), 0, data, 91, 9091);

        // Call: execute with a non-member initiator under `anyInitiator=true`, expecting the membership requirement to
        // remain enforced.
        _expectPolicyDoesNotApply(9091);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            data,
            91,
            nonMemberExpiration,
            9091,
            nonMemberSig,
            bytes(""),
            anyInitiatorProofs
        );
    }

    /**
     * @dev Verifies `executeAccountTransaction` group initiator authorization uses current organization membership
     *      instead of stale group bits. [OPB-AIA-4]
     */
    function test_OPB_AIA_4_executeAccountTransaction_groupInitiatorRequiresCurrentOrgMembership() public {
        // Setup: deploy one account plus one interaction target, configure a single admin signer for real
        // `modifyGroups/modifyMembers` calls, create a two-member initiator group, and then remove one initiator from
        // the organization without touching the existing group membership bit.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory activeData = abi.encodeWithSelector(target.ping.selector, uint256(41));
        bytes memory removedData = abi.encodeWithSelector(target.ping.selector, uint256(42));
        uint256 initiatorGroupId = 882;

        _setMembersAndAdmins(buildArray(admin1), buildArray(admin1), 1);
        _createGroupViaGuardian(initiatorGroupId, buildArray(initiator1, initiator2), 9201);
        _removeMemberViaGuardian(initiator2, 9202);

        assertTrue(
            _policyConstraintsHarness().getGroupMemberStatus(initiatorGroupId, initiator2),
            "removed initiator should keep stale group bit"
        );
        assertFalse(
            _policyConstraintsHarness().isMember(initiator2), "removed initiator should no longer be an org member"
        );

        Policy memory policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        policy.config.initiator.initiatorType = ApproverType.Group;
        policy.config.initiator.initiatorGroupId = initiatorGroupId;

        ValidationProofs memory activeProofs = _setSinglePolicyRootAndBuildProofs(9092, policy);
        (bytes memory activeSig, uint256 activeExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, activeData, 92, 9092);

        // Call: execute once with the still-active initiator through the real group-initiator policy path.
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            activeData,
            92,
            activeExpiration,
            9092,
            activeSig,
            bytes(""),
            activeProofs
        );

        ValidationProofs memory removedProofs = _setSinglePolicyRootAndBuildProofs(9093, policy);
        (bytes memory removedSig, uint256 removedExpiration) =
            _signExecution(INITIATOR_PK_2, address(account), address(target), 0, removedData, 93, 9093);

        // Call: retry with the removed initiator on a fresh signed payload, expecting current org membership to win
        // over the stale group bit.
        _expectPolicyDoesNotApply(9093);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            removedData,
            93,
            removedExpiration,
            9093,
            removedSig,
            bytes(""),
            removedProofs
        );

        // Verify: only the still-active initiator execution reaches the downstream target.
        assertEq(target.calls(), 1, "only the active initiator should execute");
        assertEq(target.total(), 41, "failing stale-initiator branch must not mutate the target");
    }

    /**
     * @dev Verifies `executeAccountTransaction` group reviewer authorization uses current organization membership
     *      instead of stale group bits. [OPB-AIA-5]
     */
    function test_OPB_AIA_5_executeAccountTransaction_groupApproverRequiresCurrentOrgMembership() public {
        // Setup: deploy one account plus one interaction target, configure a single admin signer for real
        // `modifyGroups/modifyMembers` calls, create a two-reviewer group with threshold one, and then remove one
        // reviewer from the organization while leaving the existing group bit in place.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory activeData = abi.encodeWithSelector(target.ping.selector, uint256(51));
        bytes memory removedData = abi.encodeWithSelector(target.ping.selector, uint256(52));
        uint256 reviewerGroupId = 883;

        _setMembersAndAdmins(buildArray(admin1), buildArray(admin1), 1);
        _createGroupViaGuardian(reviewerGroupId, buildArray(reviewer1, reviewer2), 9203);
        _removeMemberViaGuardian(reviewer2, 9204);

        assertTrue(
            _policyConstraintsHarness().getGroupMemberStatus(reviewerGroupId, reviewer2),
            "removed reviewer should keep stale group bit"
        );
        assertFalse(
            _policyConstraintsHarness().isMember(reviewer2), "removed reviewer should no longer be an org member"
        );

        Policy memory policy =
            _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = reviewerGroupId;
        policy.config.approval.approvalThreshold = 1;

        ValidationProofs memory activeProofs = _setSinglePolicyRootAndBuildProofs(9094, policy);
        (bytes memory activeInitiatorSig, uint256 activeExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, activeData, 94, 9094);
        bytes memory activeReviewSig = _signReview(
            INITIATOR_PK_1, REVIEWER_PK_1, address(account), address(target), 0, activeData, 94, activeExpiration, 9094
        );

        // Call: execute once with the still-active reviewer signature satisfying the threshold-one group policy.
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            activeData,
            94,
            activeExpiration,
            9094,
            activeInitiatorSig,
            activeReviewSig,
            activeProofs
        );

        ValidationProofs memory removedProofs = _setSinglePolicyRootAndBuildProofs(9095, policy);
        (bytes memory removedInitiatorSig, uint256 removedExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, removedData, 95, 9095);
        bytes memory removedReviewSig = _signReview(
            INITIATOR_PK_1,
            REVIEWER_PK_2,
            address(account),
            address(target),
            0,
            removedData,
            95,
            removedExpiration,
            9095
        );

        // Call: retry with the removed reviewer on a fresh signed payload, expecting zero valid approvals after
        // membership revalidation.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            removedData,
            95,
            removedExpiration,
            9095,
            removedInitiatorSig,
            removedReviewSig,
            removedProofs
        );

        // Verify: the successful active-reviewer execution is the only call that reaches the target.
        assertEq(target.calls(), 1, "only the active reviewer branch should execute");
        assertEq(target.total(), 51, "failing stale-reviewer branch must not mutate the target");
    }

    /**
     * @dev Verifies `rejectAccountTransaction` group reviewer authorization uses current organization membership
     *      instead of stale group bits.
     */
    function test_rejectAccountTransaction_groupReviewerRequiresCurrentOrgMembership() public {
        // Setup: deploy one account plus one interaction target, configure a single admin signer for real
        // `modifyGroups/modifyMembers` calls, create a two-reviewer group with threshold one, and then remove one
        // reviewer from the organization while leaving the existing group bit in place.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory activeData = abi.encodeWithSelector(target.ping.selector, uint256(61));
        bytes memory removedData = abi.encodeWithSelector(target.ping.selector, uint256(62));
        uint256 reviewerGroupId = 884;

        _setMembersAndAdmins(buildArray(admin1), buildArray(admin1), 1);
        _createGroupViaGuardian(reviewerGroupId, buildArray(reviewer1, reviewer2), 9205);
        _removeMemberViaGuardian(reviewer2, 9206);

        assertTrue(
            _policyConstraintsHarness().getGroupMemberStatus(reviewerGroupId, reviewer2),
            "removed reviewer should keep stale group bit"
        );
        assertFalse(
            _policyConstraintsHarness().isMember(reviewer2), "removed reviewer should no longer be an org member"
        );

        Policy memory policy =
            _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = reviewerGroupId;
        policy.config.approval.approvalThreshold = 1;

        ValidationProofs memory activeProofs = _setSinglePolicyRootAndBuildProofs(9096, policy);
        (bytes memory activeInitiatorSig, uint256 activeExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, activeData, 96, 9096);
        bytes memory activeRejectionReviewSig = _signRejectionReview(
            INITIATOR_PK_1, REVIEWER_PK_1, address(account), address(target), 0, activeData, 96, activeExpiration, 9096
        );
        uint256 activeNonce =
            _computeAccountTransactionNonce(address(account), address(target), 0, activeData, 9096, 96);

        // Call: reject once with the still-active reviewer signature satisfying the threshold-one group policy.
        vm.prank(GUARDIAN);
        harness.rejectAccountTransaction({
            account: address(account),
            to: address(target),
            value: 0,
            data: activeData,
            salt: 96,
            expirationTimestamp: activeExpiration,
            policyId: 9096,
            initiatorSignature: activeInitiatorSig,
            reviewSignatures: activeRejectionReviewSig,
            proofs: activeProofs
        });

        ValidationProofs memory removedProofs = _setSinglePolicyRootAndBuildProofs(9097, policy);
        (bytes memory removedInitiatorSig, uint256 removedExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, removedData, 97, 9097);
        bytes memory removedRejectionReviewSig = _signRejectionReview(
            INITIATOR_PK_1,
            REVIEWER_PK_2,
            address(account),
            address(target),
            0,
            removedData,
            97,
            removedExpiration,
            9097
        );
        uint256 removedNonce =
            _computeAccountTransactionNonce(address(account), address(target), 0, removedData, 9097, 97);

        // Call: retry with the removed reviewer on a fresh rejection payload, expecting zero valid approvals after
        // membership revalidation.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 1, 0));
        vm.prank(GUARDIAN);
        harness.rejectAccountTransaction({
            account: address(account),
            to: address(target),
            value: 0,
            data: removedData,
            salt: 97,
            expirationTimestamp: removedExpiration,
            policyId: 9097,
            initiatorSignature: removedInitiatorSig,
            reviewSignatures: removedRejectionReviewSig,
            proofs: removedProofs
        });

        // Verify: only the active-reviewer rejection consumes its nonce; the stale-reviewer branch rolls back.
        assertTrue(harness.getUsedNonce(activeNonce), "active reviewer rejection should consume nonce");
        assertFalse(harness.getUsedNonce(removedNonce), "failing stale-reviewer rejection must not consume nonce");
        assertEq(target.calls(), 0, "reject path should never reach the downstream target");
    }

    /**
     * @dev Verifies policy-root updates invalidate previously collected signatures and group membership drops can make
     *      pre-collected manual approvals fall below threshold. [OPB-PGM-1, OPB-PGM-2]
     */
    function test_OPB_PGM_1__OPB_PGM_2_executeAccountTransaction_policyAndGroupMutations_invalidateCollectedSignatures()
        public
    {
        // Setup: deploy one account plus one interaction target, then collect signatures under one auto-approve policy
        // and one manual group-approval policy.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory data = abi.encodeWithSelector(target.ping.selector, uint256(1));

        Policy memory removedPolicy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        ValidationProofs memory removedPolicyProofs = _setSinglePolicyRootAndBuildProofs(9100, removedPolicy);
        (bytes memory removedPolicySig, uint256 removedPolicyExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 100, 9100);
        harness.setPoliciesRoot(bytes32(0));

        // Call: execute with signatures collected before the policy root dropped the policy.
        _expectPolicyDoesNotApply(9100);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            data,
            100,
            removedPolicyExpiration,
            9100,
            removedPolicySig,
            bytes(""),
            removedPolicyProofs
        );

        Policy memory groupPolicy =
            _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.RequireManualApproval);
        groupPolicy.config.approval.approverType = ApproverType.Group;
        groupPolicy.config.approval.approverGroupId = 881;
        groupPolicy.config.approval.approvalThreshold = 2;
        harness.setGroupStatus(881, true);
        harness.setGroupMemberStatus(881, reviewer1, true);
        harness.setGroupMemberStatus(881, reviewer2, true);

        ValidationProofs memory groupProofs = _setSinglePolicyRootAndBuildProofs(9101, groupPolicy);
        (bytes memory initiatorSig, uint256 groupExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 101, 9101);
        bytes memory reviewSigOne = _signReview(
            INITIATOR_PK_1, REVIEWER_PK_1, address(account), address(target), 0, data, 101, groupExpiration, 9101
        );
        bytes memory reviewSigTwo = _signReview(
            INITIATOR_PK_1, REVIEWER_PK_2, address(account), address(target), 0, data, 101, groupExpiration, 9101
        );
        bytes memory combinedReviewSigs =
            reviewer1 < reviewer2 ? bytes.concat(reviewSigOne, reviewSigTwo) : bytes.concat(reviewSigTwo, reviewSigOne);
        harness.setGroupMemberStatus(881, reviewer2, false);

        // Call: execute after removing one reviewer from the approval group, expecting the pre-collected approvals to
        // drop below threshold.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.InsufficientApprovals.selector, 2, 0));
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            data,
            101,
            groupExpiration,
            9101,
            initiatorSig,
            combinedReviewSigs,
            groupProofs
        );
    }

    /**
     * @dev Deploys and marks a mock account as organization-deployed.
     * @return account Fresh deployed-account mock bound to the harness organization.
     */
    function _deployMockAccount() internal returns (MockAccountForOrganizationTransaction account) {
        account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);
    }

    /**
     * @dev Returns the local composite harness with real member/group mutation entrypoints.
     * @return policyHarness Composite harness used by this suite.
     */
    function _policyConstraintsHarness()
        internal
        view
        returns (OrganizationAccountTransactionPolicyConstraintsHarness policyHarness)
    {
        return OrganizationAccountTransactionPolicyConstraintsHarness(address(harness));
    }

    /**
     * @dev Creates one organization group through the real guardian + admin-auth path.
     * @param groupId Group ID assigned to the new group.
     * @param members Initial members added during group creation.
     * @param salt Salt bound into the signed admin authorization payload.
     */
    function _createGroupViaGuardian(uint256 groupId, address[] memory members, uint256 salt) internal {
        (AdminAuthParams memory auth,) = _buildModifyGroupsAuth({
            modifications: _buildModificationsArray(_createModification(groupId, members)),
            salt: salt,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        _policyConstraintsHarness().modifyGroups(_buildModificationsArray(_createModification(groupId, members)), auth);
    }

    /**
     * @dev Removes one organization member through the real guardian + admin-auth path.
     * @param member Address removed from organization membership while leaving any group bits untouched.
     * @param salt Salt bound into the signed admin authorization payload.
     */
    function _removeMemberViaGuardian(address member, uint256 salt) internal {
        (AdminAuthParams memory auth,) = _buildModifyMembersAuth(
            buildEmptyAddressArray(),
            buildArray(member),
            salt,
            block.timestamp + 1 days,
            true,
            buildUint256Array(ADMIN_PK_1)
        );

        vm.prank(GUARDIAN);
        _policyConstraintsHarness().modifyMembers(buildEmptyAddressArray(), buildArray(member), auth);
    }

    /**
     * @dev Builds auth for `modifyMembers` using the base-contract operation-data encoding.
     * @param membersToAdd Members added by the authenticated operation.
     * @param membersToRemove Members removed by the authenticated operation.
     * @param salt Salt bound into the signed admin authorization payload.
     * @param expiration Expiration timestamp bound into the signed admin authorization payload.
     * @param isApproval Whether the signed admin payload authorizes execution or rejection.
     * @param privateKeys Admin private keys used to sign the operation hash.
     * @return auth Signed admin authorization params for `modifyMembers`.
     * @return operationData Encoded `modifyMembers` operation data matched by the signatures.
     */
    function _buildModifyMembersAuth(
        address[] memory membersToAdd,
        address[] memory membersToRemove,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        operationData = _encodeOperationDataForModifyMembers(membersToAdd, membersToRemove);
        auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyMembers,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Signs an execution payload for the requested tuple.
     * @param initiatorPrivateKey Private key used for the initiator signature.
     * @param account Source account bound into the signed tuple.
     * @param to Destination address bound into the signed tuple.
     * @param value Native token value bound into the signed tuple.
     * @param data Calldata bound into the signed tuple.
     * @param salt Salt bound into the signed tuple.
     * @param policyId Policy ID bound into the signed tuple.
     * @return signature Encoded initiator signature.
     * @return expirationTimestamp Shared expiration timestamp used for the signature.
     */
    function _signExecution(
        uint256 initiatorPrivateKey,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 policyId
    ) internal view returns (bytes memory signature, uint256 expirationTimestamp) {
        expirationTimestamp = block.timestamp + 1 days;
        signature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: initiatorPrivateKey,
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            isApproval: true
        });
    }

    /**
     * @dev Signs a rejection payload for the requested tuple.
     * @param initiatorPrivateKey Private key used for the rejection signature.
     * @param account Source account bound into the signed tuple.
     * @param to Destination address bound into the signed tuple.
     * @param value Native token value bound into the signed tuple.
     * @param data Calldata bound into the signed tuple.
     * @param salt Salt bound into the signed tuple.
     * @param expirationTimestamp Expiration timestamp bound into the signed tuple.
     * @param policyId Policy ID bound into the signed tuple.
     * @return signature Encoded rejection signature.
     */
    function _signRejection(
        uint256 initiatorPrivateKey,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId
    ) internal view returns (bytes memory signature) {
        signature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: initiatorPrivateKey,
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            isApproval: false
        });
    }

    /**
     * @dev Signs one manual-review approval for the requested tuple.
     * @param initiatorPrivateKey Private key used for the initiator signature embedded into the review hash.
     * @param reviewerPrivateKey Private key used for the reviewer signature.
     * @param account Source account bound into the signed tuple.
     * @param to Destination address bound into the signed tuple.
     * @param value Native token value bound into the signed tuple.
     * @param data Calldata bound into the signed tuple.
     * @param salt Salt bound into the signed tuple.
     * @param expirationTimestamp Expiration timestamp bound into the signed tuple.
     * @param policyId Policy ID bound into the signed tuple.
     * @return signature Encoded reviewer signature.
     */
    function _signReview(
        uint256 initiatorPrivateKey,
        uint256 reviewerPrivateKey,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId
    ) internal view returns (bytes memory signature) {
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: initiatorPrivateKey,
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            isApproval: true
        });
        signature = _signReviewTx({
            txHarness: address(harness),
            privateKey: reviewerPrivateKey,
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            isApproval: true,
            initiatorSignature: initiatorSignature
        });
    }

    /**
     * @dev Signs one manual-review rejection for the requested tuple.
     * @param initiatorPrivateKey Private key used for the approval-path initiator signature embedded into the review
     *        hash.
     * @param reviewerPrivateKey Private key used for the reviewer signature.
     * @param account Source account bound into the signed tuple.
     * @param to Destination address bound into the signed tuple.
     * @param value Native token value bound into the signed tuple.
     * @param data Calldata bound into the signed tuple.
     * @param salt Salt bound into the signed tuple.
     * @param expirationTimestamp Expiration timestamp bound into the signed tuple.
     * @param policyId Policy ID bound into the signed tuple.
     * @return signature Encoded reviewer signature for the rejection path.
     */
    function _signRejectionReview(
        uint256 initiatorPrivateKey,
        uint256 reviewerPrivateKey,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId
    ) internal view returns (bytes memory signature) {
        bytes memory initiatorSignature = _signInitiatorTx({
            txHarness: address(harness),
            privateKey: initiatorPrivateKey,
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            isApproval: true
        });
        signature = _signReviewTx({
            txHarness: address(harness),
            privateKey: reviewerPrivateKey,
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            isApproval: false,
            initiatorSignature: initiatorSignature
        });
    }

    /**
     * @dev Executes `executeAccountTransaction` as the guardian caller.
     * @param account Source account passed into `executeAccountTransaction`.
     * @param to Destination address passed into `executeAccountTransaction`.
     * @param value Native token value passed into `executeAccountTransaction`.
     * @param data Calldata passed into `executeAccountTransaction`.
     * @param salt Salt passed into `executeAccountTransaction`.
     * @param expirationTimestamp Expiration timestamp passed into `executeAccountTransaction`.
     * @param policyId Policy ID passed into `executeAccountTransaction`.
     * @param initiatorSignature Initiator signature passed into `executeAccountTransaction`.
     * @param reviewSignatures Review signatures passed into `executeAccountTransaction`.
     * @param proofs Proof bundle passed into `executeAccountTransaction`.
     */
    function _executeAsGuardian(
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
        vm.prank(GUARDIAN);
        harness.executeAccountTransaction({
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            initiatorSignature: initiatorSignature,
            reviewSignatures: reviewSignatures,
            proofs: proofs
        });
    }

    /**
     * @dev Builds a single-leaf address Merkle root and proof.
     * @param allowedAddress Sole address allowed by the resulting proof bundle.
     * @return root Merkle root for the singleton address tree.
     * @return proof Empty proof for the singleton address tree.
     */
    function _buildSingleAddressRootAndProof(address allowedAddress)
        internal
        returns (bytes32 root, bytes32[] memory proof)
    {
        address[] memory values = new address[](1);
        values[0] = allowedAddress;
        return _buildAddressRootAndProof(values, 0);
    }

    /**
     * @dev Builds a single-leaf function Merkle root and proof.
     * @param selector Sole selector allowed by the resulting proof bundle.
     * @param constraints ABI-encoded constraints bytes bound into the function leaf.
     * @return root Merkle root for the singleton function tree.
     * @return proof Empty proof for the singleton function tree.
     */
    function _buildSingleFunctionRootAndProof(bytes4 selector, bytes memory constraints)
        internal
        returns (bytes32 root, bytes32[] memory proof)
    {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        bytes[] memory constraintsList = new bytes[](1);
        constraintsList[0] = constraints;
        return _buildFunctionRootAndProof(selectors, constraintsList, 0);
    }

    /**
     * @dev Builds a count-based contract-interaction policy with a one-unit hourly rate limit.
     * @param initiatorScope Scope used for initiator rate-limit accounting.
     * @param sourceScope Scope used for source-account rate-limit accounting.
     * @param destinationScope Scope used for destination rate-limit accounting.
     * @param anyInitiator Whether the policy allows any organization member to initiate.
     * @return policy Rate-limited contract-interaction policy.
     */
    function _buildRateLimitedContractPolicy(
        RateLimitScope initiatorScope,
        RateLimitScope sourceScope,
        RateLimitScope destinationScope,
        bool anyInitiator
    ) internal view returns (Policy memory policy) {
        policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        policy.config.initiator.anyInitiator = anyInitiator;
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1;
        policy.config.rateLimit.initiatorScope = initiatorScope;
        policy.config.rateLimit.sourceScope = sourceScope;
        policy.config.rateLimit.destinationScope = destinationScope;
    }

    /**
     * @dev Computes the nonce for one account-transaction tuple.
     * @param account Source account bound into the nonce tuple.
     * @param to Destination address bound into the nonce tuple.
     * @param value Native token value bound into the nonce tuple.
     * @param data Calldata bound into the nonce tuple.
     * @param policyId Policy ID bound into the nonce tuple.
     * @param salt Salt bound into the nonce tuple.
     * @return nonce Derived nonce used by both execute and reject paths.
     */
    function _computeAccountTransactionNonce(
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 policyId,
        uint256 salt
    ) internal view returns (uint256 nonce) {
        bytes memory operationData = abi.encode(account, to, value, keccak256(data), policyId);
        nonce = harness.computeNonce(OperationType.AccountTransaction, operationData, salt);
    }

    /**
     * @dev Arms a `PolicyDoesNotApply(policyId)` expectation.
     * @param policyId Policy ID expected in the revert payload.
     */
    function _expectPolicyDoesNotApply(uint256 policyId) internal {
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, policyId));
    }
}
