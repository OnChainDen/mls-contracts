// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {
    MockAccountForOrganizationTransaction,
    MockERC20ForAccountTransaction,
    MockInteractionTarget,
    MockNativeReceiver
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseMocks.sol";
import {
    OrganizationAccountTransactionBaseSuiteBase
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseSuiteBase.sol";
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
 * @dev Direct execute/reject-path policy constraint tests for `OrganizationAccountTransactionBase`.
 */
contract OrganizationAccountTransactionBasePolicyConstraintsTest is OrganizationAccountTransactionBaseSuiteBase {
    uint256 internal constant NON_MEMBER_PK = 0xD15EA5E;

    /**
     * @dev Verifies `executeAccountTransaction` rejects disallowed source accounts and allows any-source policies
     *      across different deployed accounts. [OPB-SAF-1, OPB-SAF-2]
     */
    function test_OPB_SAF_1__OPB_SAF_2_executeAccountTransaction_sourceAccountPolicies_requireProofOrAllowAnySource()
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
        (specificSourcePolicy.roots.sourceAccountsRoot, sourceProof) = _buildSingleAddressRootAndProof(address(accountA));

        ValidationProofs memory specificSourceProofs = _setSinglePolicyRootAndBuildProofs(9_001, specificSourcePolicy);
        specificSourceProofs.sourceAccountProof = sourceProof;

        (bytes memory allowedSig, uint256 allowedExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountA), address(target), 0, data, 1, 9_001);

        // Call: execute the specific-source policy from the proofed account.
        _executeAsGuardian(
            address(accountA), address(target), 0, data, 1, allowedExpiration, 9_001, allowedSig, bytes(""), specificSourceProofs
        );

        // Verify: the allowed source account reaches the downstream target exactly once.
        assertEq(target.calls(), 1, "proofed source account should execute successfully");
        assertEq(target.lastCaller(), address(accountA), "successful call should originate from the proofed account");

        (bytes memory deniedSig, uint256 deniedExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountB), address(target), 0, data, 2, 9_001);

        // Call: execute the same policy from a different deployed account, expecting the source-account gate to fail.
        _expectPolicyDoesNotApply(9_001);
        _executeAsGuardian(
            address(accountB), address(target), 0, data, 2, deniedExpiration, 9_001, deniedSig, bytes(""), specificSourceProofs
        );

        Policy memory anySourcePolicy =
            _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        anySourcePolicy.config.anySourceAccount = true;
        ValidationProofs memory anySourceProofs = _setSinglePolicyRootAndBuildProofs(9_002, anySourcePolicy);

        (bytes memory anySourceSigA, uint256 anySourceExpirationA) =
            _signExecution(INITIATOR_PK_1, address(accountA), address(target), 0, data, 3, 9_002);
        (bytes memory anySourceSigB, uint256 anySourceExpirationB) =
            _signExecution(INITIATOR_PK_1, address(accountB), address(target), 0, data, 4, 9_002);

        // Call: re-run through an any-source policy from both accounts.
        _executeAsGuardian(
            address(accountA),
            address(target),
            0,
            data,
            3,
            anySourceExpirationA,
            9_002,
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
            9_002,
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
     *      policies that do not allow ETH, and amount thresholds apply as a strict `<` boundary. [OPB-DV-1,
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

        ValidationProofs memory allowedProofs = _setSinglePolicyRootAndBuildProofs(9_010, allowedPolicy);
        allowedProofs.destinationProof = allowedDestinationProof;
        (bytes memory allowedSig, uint256 allowedExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(allowedReceiver), transferValue, bytes(""), 10, 9_010);

        // Call: execute the native ETH transfer to the proofed receiver.
        _executeAsGuardian(
            address(account),
            address(allowedReceiver),
            transferValue,
            bytes(""),
            10,
            allowedExpiration,
            9_010,
            allowedSig,
            bytes(""),
            allowedProofs
        );

        // Verify: the whitelisted native receiver gets the forwarded ETH.
        assertEq(allowedReceiver.totalReceived(), transferValue, "allowed receiver should get native transfer");

        (bytes memory thresholdSig, uint256 thresholdExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(allowedReceiver), 0.5 ether, bytes(""), 13, 9_010);

        // Call: retry at the exact configured threshold, expecting the strict `< threshold` rule to fail closed.
        _expectPolicyDoesNotApply(9_010);
        _executeAsGuardian(
            address(account),
            address(allowedReceiver),
            0.5 ether,
            bytes(""),
            13,
            thresholdExpiration,
            9_010,
            thresholdSig,
            bytes(""),
            allowedProofs
        );

        Policy memory deniedDestinationPolicy = _buildApprovalPolicy(TransactionType.TokenTransfers, PolicyType.AutoApprove);
        deniedDestinationPolicy.config.destinationType = DestinationType.CustomList;
        deniedDestinationPolicy.config.token.anyToken = false;
        deniedDestinationPolicy.config.token.tokenAddress = address(0);
        bytes32[] memory deniedDestinationProof;
        (deniedDestinationPolicy.roots.customDestinationsRoot, deniedDestinationProof) =
            _buildSingleAddressRootAndProof(address(deniedReceiver));

        ValidationProofs memory deniedDestinationProofs =
            _setSinglePolicyRootAndBuildProofs(9_011, deniedDestinationPolicy);
        deniedDestinationProofs.destinationProof = deniedDestinationProof;
        (bytes memory deniedDestinationSig, uint256 deniedDestinationExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(allowedReceiver), transferValue, bytes(""), 11, 9_011);

        // Call: retry against an unlisted native receiver, expecting the destination gate to fail before execution.
        _expectPolicyDoesNotApply(9_011);
        _executeAsGuardian(
            address(account),
            address(allowedReceiver),
            transferValue,
            bytes(""),
            11,
            deniedDestinationExpiration,
            9_011,
            deniedDestinationSig,
            bytes(""),
            deniedDestinationProofs
        );

        Policy memory deniedTokenPolicy = allowedPolicy;
        deniedTokenPolicy.config.token.tokenAddress = address(0xC0FFEE);
        ValidationProofs memory deniedTokenProofs = _setSinglePolicyRootAndBuildProofs(9_012, deniedTokenPolicy);
        deniedTokenProofs.destinationProof = allowedDestinationProof;
        (bytes memory deniedTokenSig, uint256 deniedTokenExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(allowedReceiver), transferValue, bytes(""), 12, 9_012);

        // Call: retry with a policy that disallows the native token, expecting the token filter to fail closed.
        _expectPolicyDoesNotApply(9_012);
        _executeAsGuardian(
            address(account),
            address(allowedReceiver),
            transferValue,
            bytes(""),
            12,
            deniedTokenExpiration,
            9_012,
            deniedTokenSig,
            bytes(""),
            deniedTokenProofs
        );

        // Verify: the failed branches do not transfer additional ETH.
        assertEq(allowedReceiver.totalReceived(), transferValue, "failed native-policy branches must not move ETH");
        assertEq(deniedReceiver.totalReceived(), 0, "unlisted receiver should remain unfunded");
    }

    /**
     * @dev Verifies ERC-20 transfers use the recipient argument for destination checks and bind the allowed token
     *      contract. [OPB-DV-2, OPB-TAT-2]
     */
    function test_OPB_DV_2__OPB_TAT_2_executeAccountTransaction_erc20TransferPolicies_checkRecipientAndToken()
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

        ValidationProofs memory allowedProofs = _setSinglePolicyRootAndBuildProofs(9_020, allowedPolicy);
        allowedProofs.destinationProof = recipientProof;
        bytes memory hundredTokenTransfer = _encodeERC20Transfer(RECIPIENT, 100);
        (bytes memory allowedSig, uint256 allowedExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(allowedToken), 0, hundredTokenTransfer, 20, 9_020);

        // Call: execute an allowed ERC-20 transfer that stays below the configured threshold.
        _executeAsGuardian(
            address(account),
            address(allowedToken),
            0,
            hundredTokenTransfer,
            20,
            allowedExpiration,
            9_020,
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

        ValidationProofs memory recipientOnlyProofs = _setSinglePolicyRootAndBuildProofs(9_021, recipientOnlyPolicy);
        recipientOnlyProofs.destinationProof = tokenAddressProof;
        bytes memory recipientCheckData = _encodeERC20Transfer(RECIPIENT, 10);
        (bytes memory recipientOnlySig, uint256 recipientOnlyExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(allowedToken), 0, recipientCheckData, 21, 9_021);

        // Call: present a proof for the token contract instead of the transfer recipient, expecting destination
        // validation to reject it.
        _expectPolicyDoesNotApply(9_021);
        _executeAsGuardian(
            address(account),
            address(allowedToken),
            0,
            recipientCheckData,
            21,
            recipientOnlyExpiration,
            9_021,
            recipientOnlySig,
            bytes(""),
            recipientOnlyProofs
        );

        ValidationProofs memory wrongTokenProofs = _setSinglePolicyRootAndBuildProofs(9_022, allowedPolicy);
        wrongTokenProofs.destinationProof = recipientProof;
        (bytes memory wrongTokenSig, uint256 wrongTokenExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(otherToken), 0, recipientCheckData, 22, 9_022);

        // Call: retry against a different token contract, expecting the token filter to reject it.
        _expectPolicyDoesNotApply(9_022);
        _executeAsGuardian(
            address(account),
            address(otherToken),
            0,
            recipientCheckData,
            22,
            wrongTokenExpiration,
            9_022,
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
    function test_OPB_DV_4_executeAccountTransaction_destinationTypeAny_allowsUnlistedDestinationWithoutProof()
        public
    {
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

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(9_023, policy);
        (bytes memory signature, uint256 expirationTimestamp) =
            _signExecution(INITIATOR_PK_1, address(account), address(receiver), transferValue, bytes(""), 23, 9_023);

        // Call: execute the ETH transfer without supplying any destination proof.
        _executeAsGuardian(
            address(account),
            address(receiver),
            transferValue,
            bytes(""),
            23,
            expirationTimestamp,
            9_023,
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

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(9_024, policy);
        (bytes memory signature, uint256 expirationTimestamp) =
            _signExecution(INITIATOR_PK_1, address(account), address(receiver), transferValue, bytes(""), 24, 9_024);

        // Call: execute a large native transfer that would exceed the stored threshold if threshold checks were
        // enabled.
        _executeAsGuardian(
            address(account),
            address(receiver),
            transferValue,
            bytes(""),
            24,
            expirationTimestamp,
            9_024,
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
    function test_OPB_FAPC_1__OPB_FAPC_3__OPB_FAPC_4_executeAccountTransaction_staticFunctionPolicies_failClosed()
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

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(9_040, policy);
        proofs.functionProof = functionProof;
        proofs.constraints = sevenConstraints;

        bytes memory allowedData = abi.encodeWithSelector(target.ping.selector, uint256(7));
        (bytes memory allowedSig, uint256 allowedExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, allowedData, 40, 9_040);

        // Call: execute the allowed selector with the exact allowed static argument.
        _executeAsGuardian(
            address(account), address(target), 0, allowedData, 40, allowedExpiration, 9_040, allowedSig, bytes(""), proofs
        );

        // Verify: the allowed selector and exact parameter succeed through the real execute path.
        assertEq(target.calls(), 1, "exact static parameter should pass");
        assertEq(target.total(), 7, "allowed static argument should reach the target");

        ParameterConstraint memory exactEight = exactSeven;
        exactEight.comparisonData = abi.encode(uint256(8));
        ValidationProofs memory mismatchedConstraintHashProofs = proofs;
        mismatchedConstraintHashProofs.constraints = _encodeSingleConstraint(exactEight);
        (bytes memory mismatchedConstraintHashSig, uint256 mismatchedConstraintHashExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, allowedData, 41, 9_040);

        // Call: reuse the selector proof but change the constraint bytes, expecting the selector+constraints leaf
        // binding to reject it.
        _expectPolicyDoesNotApply(9_040);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            allowedData,
            41,
            mismatchedConstraintHashExpiration,
            9_040,
            mismatchedConstraintHashSig,
            bytes(""),
            mismatchedConstraintHashProofs
        );

        bytes memory shortData = hex"010203";
        (bytes memory shortSig, uint256 shortExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, shortData, 42, 9_040);

        // Call: execute calldata shorter than one selector, expecting the allowlist path to fail closed.
        _expectPolicyDoesNotApply(9_040);
        _executeAsGuardian(
            address(account), address(target), 0, shortData, 42, shortExpiration, 9_040, shortSig, bytes(""), proofs
        );

        bytes memory wrongStaticValueData = abi.encodeWithSelector(target.ping.selector, uint256(8));
        (bytes memory wrongStaticValueSig, uint256 wrongStaticValueExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, wrongStaticValueData, 43, 9_040);

        // Call: execute the allowed selector with the wrong static argument, expecting the exact constraint to fail.
        _expectPolicyDoesNotApply(9_040);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            wrongStaticValueData,
            43,
            wrongStaticValueExpiration,
            9_040,
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

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(9_050, policy);
        proofs.functionProof = functionProof;
        proofs.constraints = payloadConstraints;

        bytes memory matchingData = abi.encodeWithSelector(target.storePayload.selector, expectedPayload);
        (bytes memory matchingSig, uint256 matchingExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, matchingData, 50, 9_050);

        // Call: execute the allowed dynamic-bytes payload.
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            matchingData,
            50,
            matchingExpiration,
            9_050,
            matchingSig,
            bytes(""),
            proofs
        );

        // Verify: the exact bytes payload reaches the target and stores the expected hash.
        assertEq(target.payloadHash(), keccak256(expectedPayload), "matching bytes payload should succeed");

        bytes memory mismatchedData = abi.encodeWithSelector(target.storePayload.selector, differentPayload);
        (bytes memory mismatchedSig, uint256 mismatchedExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, mismatchedData, 51, 9_050);

        // Call: execute the same selector with different bytes, expecting the exact constraint to reject it.
        _expectPolicyDoesNotApply(9_050);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            mismatchedData,
            51,
            mismatchedExpiration,
            9_050,
            mismatchedSig,
            bytes(""),
            proofs
        );

        bytes memory badOffsetData =
            bytes.concat(target.storePayload.selector, abi.encode(uint256(31), uint256(3), bytes3(hex"AABBCC")));
        (bytes memory badOffsetSig, uint256 badOffsetExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, badOffsetData, 52, 9_050);

        // Call: execute a dynamic-bytes payload whose offset points into the ABI head region, expecting fail-closed
        // validation.
        _expectPolicyDoesNotApply(9_050);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            badOffsetData,
            52,
            badOffsetExpiration,
            9_050,
            badOffsetSig,
            bytes(""),
            proofs
        );

        bytes memory truncatedData =
            bytes.concat(target.storePayload.selector, abi.encode(uint256(32), uint256(10)), hex"AABBCCDD");
        (bytes memory truncatedSig, uint256 truncatedExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, truncatedData, 53, 9_050);

        // Call: execute a dynamic-bytes payload whose declared length runs past `data.length`, expecting fail-closed
        // validation.
        _expectPolicyDoesNotApply(9_050);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            truncatedData,
            53,
            truncatedExpiration,
            9_050,
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

        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(9_051, policy);
        (bytes memory signature, uint256 expirationTimestamp) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 54, 9_051);

        // Call: execute an arbitrary selector with arbitrary calldata and no function proof.
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            data,
            54,
            expirationTimestamp,
            9_051,
            signature,
            bytes(""),
            proofs
        );

        // Verify: the interaction succeeds and the unconstrained payload reaches the target unchanged.
        assertEq(target.calls(), 1, "anyFunction should allow arbitrary selector execution");
        assertEq(target.payloadHash(), keccak256(hex"CAFECAFE"), "arbitrary calldata should reach the target");
    }

    /**
     * @dev Verifies per-entity rate-limit scopes separate initiator/account/destination budgets, while an all-shared
     *      scope collapses them into one budget. [OPB-RL-1, OPB-RL-2, OPB-RL-3, OPB-RL-4]
     */
    function test_OPB_RL_1__OPB_RL_2__OPB_RL_3__OPB_RL_4_executeAccountTransaction_rateLimitScopes_chargeExpectedKeys()
        public
    {
        // Setup: deploy two accounts and two interaction targets for four scoped-rate-limit subcases.
        MockAccountForOrganizationTransaction accountA = _deployMockAccount();
        MockAccountForOrganizationTransaction accountB = _deployMockAccount();
        MockInteractionTarget targetA = new MockInteractionTarget();
        MockInteractionTarget targetB = new MockInteractionTarget();
        bytes memory data = abi.encodeWithSelector(targetA.ping.selector, uint256(1));

        Policy memory initiatorScopedPolicy =
            _buildRateLimitedContractPolicy(RateLimitScope.PerEntity, RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, true);
        ValidationProofs memory initiatorScopedProofs =
            _setSinglePolicyRootAndBuildProofs(9_060, initiatorScopedPolicy);
        (bytes memory initiatorOneSig, uint256 initiatorOneExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountA), address(targetA), 0, data, 60, 9_060);
        (bytes memory initiatorTwoSig, uint256 initiatorTwoExpiration) =
            _signExecution(INITIATOR_PK_2, address(accountA), address(targetA), 0, data, 61, 9_060);

        // Call: execute twice under a per-initiator policy with two different initiators.
        _executeAsGuardian(
            address(accountA), address(targetA), 0, data, 60, initiatorOneExpiration, 9_060, initiatorOneSig, bytes(""), initiatorScopedProofs
        );
        _executeAsGuardian(
            address(accountA), address(targetA), 0, data, 61, initiatorTwoExpiration, 9_060, initiatorTwoSig, bytes(""), initiatorScopedProofs
        );

        // Verify: each initiator accrues usage against a separate key.
        uint256 initiatorWindow = _computeTimeWindow(initiatorScopedPolicy);
        assertEq(
            harness.getPolicyUsage(_computeUsageKey(9_060, initiatorScopedPolicy, address(accountA), address(targetA), initiator1), initiatorWindow),
            1,
            "initiator one should have an isolated budget"
        );
        assertEq(
            harness.getPolicyUsage(_computeUsageKey(9_060, initiatorScopedPolicy, address(accountA), address(targetA), initiator2), initiatorWindow),
            1,
            "initiator two should have an isolated budget"
        );

        Policy memory sourceScopedPolicy =
            _buildRateLimitedContractPolicy(RateLimitScope.AcrossAll, RateLimitScope.PerEntity, RateLimitScope.AcrossAll, false);
        ValidationProofs memory sourceScopedProofs = _setSinglePolicyRootAndBuildProofs(9_061, sourceScopedPolicy);
        (bytes memory sourceAccountASig, uint256 sourceAccountAExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountA), address(targetA), 0, data, 62, 9_061);
        (bytes memory sourceAccountBSig, uint256 sourceAccountBExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountB), address(targetA), 0, data, 63, 9_061);

        // Call: execute twice under a per-source-account policy with two different accounts.
        _executeAsGuardian(
            address(accountA), address(targetA), 0, data, 62, sourceAccountAExpiration, 9_061, sourceAccountASig, bytes(""), sourceScopedProofs
        );
        _executeAsGuardian(
            address(accountB), address(targetA), 0, data, 63, sourceAccountBExpiration, 9_061, sourceAccountBSig, bytes(""), sourceScopedProofs
        );

        // Verify: each source account accrues usage against a separate key.
        uint256 sourceWindow = _computeTimeWindow(sourceScopedPolicy);
        assertEq(
            harness.getPolicyUsage(_computeUsageKey(9_061, sourceScopedPolicy, address(accountA), address(targetA), initiator1), sourceWindow),
            1,
            "account A should have an isolated source budget"
        );
        assertEq(
            harness.getPolicyUsage(_computeUsageKey(9_061, sourceScopedPolicy, address(accountB), address(targetA), initiator1), sourceWindow),
            1,
            "account B should have an isolated source budget"
        );

        Policy memory destinationScopedPolicy =
            _buildRateLimitedContractPolicy(RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, RateLimitScope.PerEntity, false);
        ValidationProofs memory destinationScopedProofs =
            _setSinglePolicyRootAndBuildProofs(9_062, destinationScopedPolicy);
        (bytes memory destinationASig, uint256 destinationAExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountA), address(targetA), 0, data, 64, 9_062);
        bytes memory dataToTargetB = abi.encodeWithSelector(targetB.ping.selector, uint256(1));
        (bytes memory destinationBSig, uint256 destinationBExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountA), address(targetB), 0, dataToTargetB, 65, 9_062);

        // Call: execute twice under a per-destination policy with two different destinations.
        _executeAsGuardian(
            address(accountA), address(targetA), 0, data, 64, destinationAExpiration, 9_062, destinationASig, bytes(""), destinationScopedProofs
        );
        _executeAsGuardian(
            address(accountA),
            address(targetB),
            0,
            dataToTargetB,
            65,
            destinationBExpiration,
            9_062,
            destinationBSig,
            bytes(""),
            destinationScopedProofs
        );

        // Verify: each destination accrues usage against a separate key.
        uint256 destinationWindow = _computeTimeWindow(destinationScopedPolicy);
        assertEq(
            harness.getPolicyUsage(
                _computeUsageKey(9_062, destinationScopedPolicy, address(accountA), address(targetA), initiator1),
                destinationWindow
            ),
            1,
            "target A should have an isolated destination budget"
        );
        assertEq(
            harness.getPolicyUsage(
                _computeUsageKey(9_062, destinationScopedPolicy, address(accountA), address(targetB), initiator1),
                destinationWindow
            ),
            1,
            "target B should have an isolated destination budget"
        );

        Policy memory acrossAllPolicy =
            _buildRateLimitedContractPolicy(RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, true);
        ValidationProofs memory acrossAllProofs = _setSinglePolicyRootAndBuildProofs(9_063, acrossAllPolicy);
        (bytes memory sharedBudgetSig, uint256 sharedBudgetExpiration) =
            _signExecution(INITIATOR_PK_1, address(accountA), address(targetA), 0, data, 66, 9_063);
        (bytes memory exhaustedBudgetSig, uint256 exhaustedBudgetExpiration) =
            _signExecution(INITIATOR_PK_2, address(accountB), address(targetB), 0, dataToTargetB, 67, 9_063);

        // Call: consume the shared budget once, then retry from a different account, destination, and initiator.
        _executeAsGuardian(
            address(accountA), address(targetA), 0, data, 66, sharedBudgetExpiration, 9_063, sharedBudgetSig, bytes(""), acrossAllProofs
        );
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, 9_063));
        _executeAsGuardian(
            address(accountB),
            address(targetB),
            0,
            dataToTargetB,
            67,
            exhaustedBudgetExpiration,
            9_063,
            exhaustedBudgetSig,
            bytes(""),
            acrossAllProofs
        );

        // Verify: the across-all scope collapses all entities into one shared usage key.
        uint256 acrossAllWindow = _computeTimeWindow(acrossAllPolicy);
        assertEq(
            harness.getPolicyUsage(
                _computeUsageKey(9_063, acrossAllPolicy, address(accountA), address(targetA), initiator1),
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
    function test_OPB_RL_5__OPB_RL_6_executeAccountTransaction_rateLimitWindows_resetAfterBoundary() public {
        // Setup: deploy one account plus one interaction target, then use a one-call-per-hour policy for two
        // time-window subcases.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory data = abi.encodeWithSelector(target.ping.selector, uint256(1));

        Policy memory rolloverPolicy =
            _buildRateLimitedContractPolicy(RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, false);
        ValidationProofs memory rolloverProofs = _setSinglePolicyRootAndBuildProofs(9_070, rolloverPolicy);

        vm.warp(1);
        (bytes memory firstWindowSig, uint256 firstWindowExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 70, 9_070);
        _executeAsGuardian(
            address(account), address(target), 0, data, 70, firstWindowExpiration, 9_070, firstWindowSig, bytes(""), rolloverProofs
        );
        uint256 firstWindow = _computeTimeWindow(rolloverPolicy);

        vm.warp(3_601);
        (bytes memory secondWindowSig, uint256 secondWindowExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 71, 9_070);
        _executeAsGuardian(
            address(account), address(target), 0, data, 71, secondWindowExpiration, 9_070, secondWindowSig, bytes(""), rolloverProofs
        );
        uint256 secondWindow = _computeTimeWindow(rolloverPolicy);

        // Verify: usage from the old window does not carry into the next window after the boundary passes.
        bytes32 rolloverKey = _computeUsageKey(9_070, rolloverPolicy, address(account), address(target), initiator1);
        assertEq(harness.getPolicyUsage(rolloverKey, firstWindow), 1, "old window should retain its own usage");
        assertEq(harness.getPolicyUsage(rolloverKey, secondWindow), 1, "new window should start fresh");

        Policy memory exactBoundaryPolicy =
            _buildRateLimitedContractPolicy(RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, false);
        ValidationProofs memory exactBoundaryProofs = _setSinglePolicyRootAndBuildProofs(9_071, exactBoundaryPolicy);

        vm.warp(7_199);
        (bytes memory beforeBoundarySig, uint256 beforeBoundaryExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 72, 9_071);
        _executeAsGuardian(
            address(account), address(target), 0, data, 72, beforeBoundaryExpiration, 9_071, beforeBoundarySig, bytes(""), exactBoundaryProofs
        );
        uint256 beforeBoundaryWindow = _computeTimeWindow(exactBoundaryPolicy);

        vm.warp(7_200);
        (bytes memory onBoundarySig, uint256 onBoundaryExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 73, 9_071);
        _executeAsGuardian(
            address(account), address(target), 0, data, 73, onBoundaryExpiration, 9_071, onBoundarySig, bytes(""), exactBoundaryProofs
        );
        uint256 onBoundaryWindow = _computeTimeWindow(exactBoundaryPolicy);

        // Verify: the transaction executed at the exact boundary uses the new window instead of the exhausted old one.
        bytes32 boundaryKey = _computeUsageKey(9_071, exactBoundaryPolicy, address(account), address(target), initiator1);
        assertEq(harness.getPolicyUsage(boundaryKey, beforeBoundaryWindow), 1, "pre-boundary window should stay full");
        assertEq(harness.getPolicyUsage(boundaryKey, onBoundaryWindow), 1, "boundary execution should use fresh window");
    }

    /**
     * @dev Verifies rejection does not mutate rate-limit usage and rate-limit overflows fail closed with
     *      `RateLimitExceeded`. [OPB-RL-7, OPB-RL-8]
     */
    function test_OPB_RL_7__OPB_RL_8__OAT_RAT_4_executeAccountTransaction_rejectionAndOverflow_leaveUsageSafe()
        public
    {
        // Setup: deploy one account plus one interaction target, then prepare one rate-limited auto-approve policy.
        MockAccountForOrganizationTransaction account = _deployMockAccount();
        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory data = abi.encodeWithSelector(target.ping.selector, uint256(1));

        Policy memory policy =
            _buildRateLimitedContractPolicy(RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, RateLimitScope.AcrossAll, false);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(9_080, policy);

        (bytes memory approvalSig, uint256 approvalExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 80, 9_080);
        bytes memory rejectionSig =
            _signRejection(INITIATOR_PK_1, address(account), address(target), 0, data, 80, approvalExpiration, 9_080);
        bytes32 usageKey = _computeUsageKey(9_080, policy, address(account), address(target), initiator1);
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
            policyId: 9_080,
            initiatorSignature: approvalSig,
            reviewSignatures: rejectionSig,
            proofs: proofs
        });
        assertEq(harness.getPolicyUsage(usageKey, window), 0, "rejection should not consume any rate-limit usage");

        (bytes memory executedSig, uint256 executedExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 81, 9_080);
        _executeAsGuardian(
            address(account), address(target), 0, data, 81, executedExpiration, 9_080, executedSig, bytes(""), proofs
        );

        // Verify: the later execution still sees the pre-rejection usage and consumes exactly one unit.
        assertEq(harness.getPolicyUsage(usageKey, window), 1, "post-rejection execution should start from zero usage");

        Policy memory overflowPolicy = policy;
        overflowPolicy.config.rateLimit.timeIntervalLimit = type(uint256).max;
        ValidationProofs memory overflowProofs = _setSinglePolicyRootAndBuildProofs(9_081, overflowPolicy);
        bytes32 overflowKey = _computeUsageKey(9_081, overflowPolicy, address(account), address(target), initiator1);
        harness.setPolicyUsage(overflowKey, window, type(uint256).max);

        (bytes memory overflowSig, uint256 overflowExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 82, 9_081);

        // Call: execute when usage addition would overflow `uint256`, expecting the fail-closed rate-limit error.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.RateLimitExceeded.selector, 9_081));
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            data,
            82,
            overflowExpiration,
            9_081,
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
    function test_OPB_AIA_1__OPB_AIA_2_executeAccountTransaction_manualZeroThresholdAndNonMemberInitiator_failClosed()
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

        ValidationProofs memory zeroThresholdProofs =
            _setSinglePolicyRootAndBuildProofs(9_090, zeroThresholdPolicy);
        (bytes memory zeroThresholdSig, uint256 zeroThresholdExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 90, 9_090);

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
            9_090,
            zeroThresholdSig,
            bytes(""),
            zeroThresholdProofs
        );

        Policy memory anyInitiatorPolicy =
            _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        anyInitiatorPolicy.config.initiator.anyInitiator = true;
        ValidationProofs memory anyInitiatorProofs =
            _setSinglePolicyRootAndBuildProofs(9_091, anyInitiatorPolicy);
        (bytes memory nonMemberSig, uint256 nonMemberExpiration) =
            _signExecution(NON_MEMBER_PK, address(account), address(target), 0, data, 91, 9_091);

        // Call: execute with a non-member initiator under `anyInitiator=true`, expecting the membership requirement to
        // remain enforced.
        _expectPolicyDoesNotApply(9_091);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            data,
            91,
            nonMemberExpiration,
            9_091,
            nonMemberSig,
            bytes(""),
            anyInitiatorProofs
        );
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

        Policy memory removedPolicy =
            _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        ValidationProofs memory removedPolicyProofs = _setSinglePolicyRootAndBuildProofs(9_100, removedPolicy);
        (bytes memory removedPolicySig, uint256 removedPolicyExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 100, 9_100);
        harness.setPoliciesRoot(bytes32(0));

        // Call: execute after the policy root was cleared; signatures were collected before the drop.
        _expectPolicyDoesNotApply(9_100);
        _executeAsGuardian(
            address(account),
            address(target),
            0,
            data,
            100,
            removedPolicyExpiration,
            9_100,
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

        ValidationProofs memory groupProofs = _setSinglePolicyRootAndBuildProofs(9_101, groupPolicy);
        (bytes memory initiatorSig, uint256 groupExpiration) =
            _signExecution(INITIATOR_PK_1, address(account), address(target), 0, data, 101, 9_101);
        bytes memory reviewSigOne =
            _signReview(INITIATOR_PK_1, REVIEWER_PK_1, address(account), address(target), 0, data, 101, groupExpiration, 9_101);
        bytes memory reviewSigTwo =
            _signReview(INITIATOR_PK_1, REVIEWER_PK_2, address(account), address(target), 0, data, 101, groupExpiration, 9_101);
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
            9_101,
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
     * @dev Arms a `PolicyDoesNotApply(policyId)` expectation.
     * @param policyId Policy ID expected in the revert payload.
     */
    function _expectPolicyDoesNotApply(uint256 policyId) internal {
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAccountTransaction.PolicyDoesNotApply.selector, policyId));
    }
}
