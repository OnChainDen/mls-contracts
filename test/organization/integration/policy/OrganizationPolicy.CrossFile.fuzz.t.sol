// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {
    LibOrganizationPolicySuiteBase
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicySuiteBase.sol";
import {
    ApproverType,
    ConstraintType,
    DestinationType,
    ParamType,
    ParameterConstraint,
    Policy,
    RateLimitScope,
    TransactionType,
    ValidationProofs
} from "types/PolicyTypes.sol";

/**
 * @dev Cross-file fuzz tests for organization policy behaviors.
 */
contract OrganizationPolicyCrossFileFuzzTest is LibOrganizationPolicySuiteBase {
    /// @dev Encapsulates one concrete transaction case used by policy-evaluation fuzz tests.
    struct PolicyTransactionCase {
        address to;
        uint256 value;
        bytes data;
    }

    uint256 internal constant DEFAULT_POLICY_ID = 5001;

    /**
     * @dev Seeds the reusable initiator membership fixture required by top-level transaction-policy checks.
     */
    function setUp() public override {
        super.setUp();
        policyStateHarness.setMemberStatus(initiator1, true);
        policyStateHarness.setMemberStatus(initiator2, true);
    }

    /**
     * @dev Verifies `LibOrganizationPolicy.isPolicyInOrg` accepts the exact policy/proof tuple and fails closed for
     *      any single-field policy mutation or single-word proof mutation.
     * @param policyIdSeed Raw policy id used to derive a bounded non-zero policy id
     * @param mutationSelector Chooses which policy field to mutate after the exact-tuple control check
     */
    function testFuzz_FLOP_MERKLE_56_isPolicyInOrg_exactTuplePassesAndPolicyOrProofMutationFails(
        uint256 policyIdSeed,
        uint8 mutationSelector
    ) public {
        // Setup: build a two-leaf policy tree so the exact tuple has both a non-empty proof and multiple mutable
        // policy fields.
        uint256 policyId = bound(policyIdSeed, 1, type(uint96).max - 1);
        Policy memory policy = _buildBasePolicy();
        policy.config.anySourceAccount = false;
        policy.config.destinationType = DestinationType.CustomList;
        policy.config.transactionType = TransactionType.ContractInteractions;
        policy.config.approval.approvalThreshold = 2;
        policy.roots.sourceAccountsRoot = keccak256("floa-merkle-56-source-root");
        policy.roots.customDestinationsRoot = keccak256("floa-merkle-56-destination-root");
        policy.roots.allowedFunctionsRoot = keccak256("floa-merkle-56-function-root");

        Policy memory siblingPolicy = _buildBasePolicy();
        siblingPolicy.config.anyFunction = false;

        uint256[] memory policyIds = new uint256[](2);
        policyIds[0] = policyId;
        policyIds[1] = policyId + 1;
        Policy[] memory policies = new Policy[](2);
        policies[0] = policy;
        policies[1] = siblingPolicy;

        (bytes32 root, bytes32[] memory proof) = _buildPolicyRootAndProof(policyIds, policies, 0);
        policyStateHarness.setPoliciesRoot(root);

        // Call: validate the exact policy/proof tuple against the stored root.
        assertTrue(harness.isPolicyInOrgViaLibrary(policyId, policy, proof), "exact policy+proof tuple should pass");

        Policy memory mutated = policy;
        uint8 mode = uint8(mutationSelector % 8);
        if (mode == 0) {
            mutated.config.transactionType = TransactionType.TokenTransfers;
        } else if (mode == 1) {
            mutated.config.anySourceAccount = true;
        } else if (mode == 2) {
            mutated.config.destinationType = DestinationType.Any;
        } else if (mode == 3) {
            mutated.config.approval.approvalThreshold = 3;
        } else if (mode == 4) {
            mutated.config.initiator.initiatorMember = reviewer1;
        } else if (mode == 5) {
            mutated.config.token.amountThreshold = 1;
        } else if (mode == 6) {
            mutated.roots.sourceAccountsRoot = policy.roots.sourceAccountsRoot ^ bytes32(uint256(1));
        } else {
            mutated.roots.allowedFunctionsRoot = policy.roots.allowedFunctionsRoot ^ bytes32(uint256(1));
        }

        bytes32[] memory mutatedProof = new bytes32[](proof.length);
        for (uint256 i = 0; i < proof.length; i++) {
            mutatedProof[i] = proof[i];
        }
        mutatedProof[0] = mutatedProof[0] ^ bytes32(uint256(1));

        // Verify: mutating either the policy fields or one proof word should invalidate membership verification.
        assertFalse(
            harness.isPolicyInOrgViaLibrary(policyId, mutated, proof), "single policy-field mutation should fail"
        );
        assertFalse(
            harness.isPolicyInOrgViaLibrary(policyId, policy, mutatedProof), "single proof-word mutation should fail"
        );
    }

    /**
     * @dev Verifies `LibOrganizationPolicy.isSourceAccountAllowedByPolicy` always accepts when
     *      `anySourceAccount == true`, and otherwise requires the exact source-account proof tuple.
     * @param allowedAccount Account included in the source-account merkle tree
     * @param otherAccount Distinct account excluded from the source-account merkle tree
     */
    function testFuzz_FLOP_SOURCE_57_isSourceAccountAllowedByPolicy_anySourceAcceptsOtherwiseExactProofRequired(
        address allowedAccount,
        address otherAccount
    ) public {
        // Setup: build a two-leaf source-account tree whose proof covers `allowedAccount` but excludes
        // `otherAccount`, then derive policy variants that differ only on the any-source flag.
        vm.assume(allowedAccount != address(0));
        vm.assume(otherAccount != address(0));
        vm.assume(allowedAccount != otherAccount);

        address witnessAccount = address(
            uint160(uint256(keccak256(abi.encodePacked("floop-source-57", allowedAccount, otherAccount))) | uint256(1))
        );
        vm.assume(witnessAccount != allowedAccount);
        vm.assume(witnessAccount != otherAccount);

        (bytes32 sourceRoot, bytes32[] memory sourceProof) =
            _buildAddressRootAndProof(buildArray(allowedAccount, witnessAccount), 0);
        bytes32[] memory emptyProof = new bytes32[](0);

        Policy memory filteredPolicy = _buildBasePolicy();
        filteredPolicy.config.anySourceAccount = false;
        filteredPolicy.roots.sourceAccountsRoot = sourceRoot;

        Policy memory anySourcePolicy = _buildBasePolicy();
        anySourcePolicy.config.anySourceAccount = true;
        anySourcePolicy.roots.sourceAccountsRoot = sourceRoot;

        // Verify: the any-source branch should always pass, while the filtered branch should require the exact
        // proof/account tuple.
        assertTrue(
            harness.isSourceAccountAllowedByPolicyViaLibrary(anySourcePolicy, allowedAccount, emptyProof),
            "any-source policy should accept the included account"
        );
        assertTrue(
            harness.isSourceAccountAllowedByPolicyViaLibrary(anySourcePolicy, otherAccount, sourceProof),
            "any-source policy should accept even without an exact source proof"
        );
        assertTrue(
            harness.isSourceAccountAllowedByPolicyViaLibrary(filteredPolicy, allowedAccount, sourceProof),
            "filtered policy should accept the exact source-account proof"
        );
        assertFalse(
            harness.isSourceAccountAllowedByPolicyViaLibrary(filteredPolicy, otherAccount, sourceProof),
            "filtered policy should reject a different account with the same proof"
        );
        assertFalse(
            harness.isSourceAccountAllowedByPolicyViaLibrary(filteredPolicy, allowedAccount, emptyProof),
            "filtered policy should reject the included account without its proof"
        );
    }

    /// @dev Verifies that policy field mutation invalidates original proof.
    function testFuzz_policyFieldMutationInvalidatesOriginalProof(uint256 policyIdSeed, uint8 mutationSelector)
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for policy field mutation
        // invalidates original proof.
        public
    {
        uint256 policyId = bound(policyIdSeed, 1, type(uint96).max);

        Policy memory policy = _buildBasePolicy();
        policy.config.anySourceAccount = false;
        policy.config.destinationType = DestinationType.CustomList;
        policy.config.transactionType = TransactionType.ContractInteractions;
        policy.config.approval.approvalThreshold = 2;

        policy.roots.sourceAccountsRoot = keccak256("src-root");
        policy.roots.customDestinationsRoot = keccak256("dest-root");
        policy.roots.allowedFunctionsRoot = keccak256("fn-root");

        bytes32 root = _computePolicyLeaf(policyId, policy);
        policyStateHarness.setPoliciesRoot(root);

        bytes32[] memory empty = new bytes32[](0);
        // Call: run `isPolicyInOrgViaLibrary` across the prepared variants.
        assertTrue(harness.isPolicyInOrgViaLibrary(policyId, policy, empty), "baseline proof should validate");

        Policy memory mutated = policy;
        uint8 selector = uint8(mutationSelector % 8);

        if (selector == 0) {
            mutated.config.transactionType = TransactionType.TokenTransfers;
        } else if (selector == 1) {
            mutated.config.anySourceAccount = !policy.config.anySourceAccount;
        } else if (selector == 2) {
            mutated.config.destinationType = DestinationType.Any;
        } else if (selector == 3) {
            mutated.config.approval.approvalThreshold = policy.config.approval.approvalThreshold + 1;
        } else if (selector == 4) {
            mutated.config.initiator.initiatorMember = reviewer1;
        } else if (selector == 5) {
            mutated.config.token.amountThreshold = policy.config.token.amountThreshold + 1;
        } else if (selector == 6) {
            mutated.roots.sourceAccountsRoot = keccak256("mut-src-root");
        } else {
            mutated.roots.allowedFunctionsRoot = keccak256("mut-fn-root");
        }

        assertFalse(harness.isPolicyInOrgViaLibrary(policyId, mutated, empty), "single-field mutation must break proof");
    }

    /// @dev Verifies that source account proofs only pass for exact tuple.
    function testFuzz_POL_INV_3_sourceAccountProofsOnlyPassForExactTuple(
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for source account proofs only pass
        // for exact tuple.
        address accountA,
        address accountB,
        bool useFirst
    ) public {
        vm.assume(accountA != address(0));
        vm.assume(accountB != address(0));
        vm.assume(accountA != accountB);

        address[] memory sourceAccounts = buildArray(accountA, accountB);
        uint256 targetIndex = useFirst ? 0 : 1;
        uint256 otherIndex = useFirst ? 1 : 0;

        (bytes32 sourceRoot, bytes32[] memory proof) = _buildAddressRootAndProof(sourceAccounts, targetIndex);

        Policy memory policy = _buildBasePolicy();
        policy.config.anySourceAccount = false;
        policy.roots.sourceAccountsRoot = sourceRoot;

        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(
            // Call: run `isSourceAccountAllowedByPolicyViaLibrary` across the prepared variants.
            harness.isSourceAccountAllowedByPolicyViaLibrary(policy, sourceAccounts[targetIndex], proof),
            "exact account/root/proof tuple should pass"
        );

        assertFalse(
            harness.isSourceAccountAllowedByPolicyViaLibrary(policy, sourceAccounts[otherIndex], proof),
            "wrong account with same proof should fail"
        );
    }

    /// @dev Verifies that destination proofs validate only actual destination.
    function testFuzz_destinationProofsValidateOnlyActualDestination(
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for destination proofs validate only
        // actual destination.
        uint8 shape,
        address allowedDestination,
        address otherDestination,
        address tokenContract,
        uint256 amount
    ) public {
        vm.assume(allowedDestination != address(0));
        vm.assume(otherDestination != address(0));
        vm.assume(tokenContract != address(0));
        vm.assume(allowedDestination != otherDestination);

        amount = bound(amount, 1, type(uint96).max);

        Policy memory policy = _buildBasePolicy();
        policy.config.destinationType = DestinationType.CustomList;

        address[] memory destinations = buildArray(allowedDestination);
        (bytes32 root, bytes32[] memory destinationProof) = _buildAddressRootAndProof(destinations, 0);
        policy.roots.customDestinationsRoot = root;

        uint8 mode = uint8(shape % 3);
        bool allowedResult;
        bool deniedResult;

        if (mode == 0) {
            // Native transfer destination is `to`.
            // Call: run `isDestinationAllowedByPolicyViaPolicyLibrary` across the prepared variants.
            allowedResult = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
                policy, allowedDestination, amount, bytes(""), destinationProof
            );
            deniedResult = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
                policy, otherDestination, amount, bytes(""), destinationProof
            );
        } else if (mode == 1) {
            // ERC-20 transfer destination is encoded recipient.
            bytes memory allowedData = _encodeERC20Transfer(allowedDestination, amount);
            bytes memory deniedData = _encodeERC20Transfer(otherDestination, amount);

            allowedResult = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
                policy, tokenContract, 0, allowedData, destinationProof
            );
            deniedResult = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
                policy, tokenContract, 0, deniedData, destinationProof
            );
        } else {
            // Contract interaction destination is `to`.
            bytes memory callData = abi.encodeWithSelector(bytes4(0x11223344), uint256(1));
            allowedResult = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
                policy, allowedDestination, 0, callData, destinationProof
            );
            deniedResult = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
                policy, otherDestination, 0, callData, destinationProof
            );
        }

        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(allowedResult, "exact actual destination should pass");
        assertFalse(deniedResult, "different actual destination should fail");
    }

    /// @dev Verifies that function proofs bind selector and constraints.
    function testFuzz_functionProofsBindSelectorAndConstraints(
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for function proofs bind selector
        // and constraints.
        bytes4 selector,
        uint256 callArg,
        bytes32 constraintsSeed,
        bytes32 alternateConstraintsSeed
    ) public {
        vm.assume(constraintsSeed != alternateConstraintsSeed);

        bytes memory constraints = abi.encode(constraintsSeed);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;

        bytes[] memory constraintsList = new bytes[](1);
        constraintsList[0] = constraints;

        (bytes32 functionRoot, bytes32[] memory functionProof) =
            _buildFunctionRootAndProof(selectors, constraintsList, 0);

        Policy memory policy = _buildBasePolicy();
        policy.config.anyFunction = false;
        policy.roots.allowedFunctionsRoot = functionRoot;

        bytes memory data = abi.encodeWithSelector(selector, callArg);
        // Call: run `isFunctionAllowedByPolicyViaPolicyLibrary` across the prepared variants.
        bool exactPairAllowed =
            harness.isFunctionAllowedByPolicyViaPolicyLibrary(policy, data, functionProof, constraints);
        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(exactPairAllowed, "exact selector+constraints tuple should pass");

        bytes4 mutatedSelector = selector ^ bytes4(uint32(1));
        bytes memory mutatedSelectorData = abi.encodeWithSelector(mutatedSelector, callArg);
        bool mutatedSelectorAllowed =
            harness.isFunctionAllowedByPolicyViaPolicyLibrary(policy, mutatedSelectorData, functionProof, constraints);
        assertFalse(mutatedSelectorAllowed, "selector mutation should fail proof");

        bytes memory alternateConstraints = abi.encode(alternateConstraintsSeed);
        bool mutatedConstraintsAllowed =
            harness.isFunctionAllowedByPolicyViaPolicyLibrary(policy, data, functionProof, alternateConstraints);
        assertFalse(mutatedConstraintsAllowed, "constraints mutation should fail proof");
    }

    /// @dev Verifies that duplicate or out of order signers fail closed.
    function testFuzz_duplicateOrOutOfOrderSignersFailClosed(bool useDuplicate, bytes32 hashSeed) public {
        // Setup: build group-approval fixture and prepare invalid signer ordering payloads.
        policyStateHarness.setMemberStatus(reviewer1, true);
        policyStateHarness.setMemberStatus(reviewer2, true);
        policyStateHarness.setGroupStatus(55, true);
        policyStateHarness.setGroupMemberStatus(55, reviewer1, true);
        policyStateHarness.setGroupMemberStatus(55, reviewer2, true);

        Policy memory policy = _buildBasePolicy();
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = 55;
        policy.config.approval.approvalThreshold = 2;

        bytes32 messageHash = keccak256(abi.encode(hashSeed));
        bytes memory sig1 = _signHash(REVIEWER_PK_1, messageHash);
        bytes memory sig2 = _signHash(REVIEWER_PK_2, messageHash);

        bytes memory packed;
        if (useDuplicate) {
            packed = abi.encodePacked(sig1, sig1);
        } else {
            // Deliberately construct descending order.
            packed = reviewer1 < reviewer2 ? abi.encodePacked(sig2, sig1) : abi.encodePacked(sig1, sig2);
        }

        // Call: evaluate approvals with duplicate/out-of-order signer bundle.
        bool approvalsValid = harness.areApprovalsValidViaPolicyLibrary(policy, packed, messageHash);
        // Verify: assert invalid signer ordering is rejected via fail-closed result.
        assertFalse(approvalsValid, "duplicate/out-of-order signer bundles should fail closed");
    }

    /// @dev Verifies that rate limit scope collision matches scope model.
    /// SAG-FUZ-5
    function testFuzz_SAG_FUZ_5_rateLimitScopeCollisionMatchesScopeModel(
        // Setup: configure a valid fixture for rate limit scope collision matches scope model.
        uint8 sourceScopeSeed,
        uint8 destinationScopeSeed,
        uint8 initiatorScopeSeed,
        bool sameAccount,
        bool sameDestination,
        bool sameInitiator
    ) public {
        Policy memory policy = _buildBasePolicy();
        policy.config.rateLimit.sourceScope = RateLimitScope(sourceScopeSeed % 2);
        policy.config.rateLimit.destinationScope = RateLimitScope(destinationScopeSeed % 2);
        policy.config.rateLimit.initiatorScope = RateLimitScope(initiatorScopeSeed % 2);

        address account1 = address(0xA101);
        address account2 = sameAccount ? account1 : address(0xA202);
        address destination1 = address(0xB101);
        address destination2 = sameDestination ? destination1 : address(0xB202);
        address initiatorA = address(0xC101);
        address initiatorB = sameInitiator ? initiatorA : address(0xC202);

        // Call: execute `computeUsageKeyViaPolicyLibrary` with the happy-path payload.
        bytes32 keyA =
            harness.computeUsageKeyViaPolicyLibrary(DEFAULT_POLICY_ID, policy, account1, destination1, initiatorA);
        bytes32 keyB =
            harness.computeUsageKeyViaPolicyLibrary(DEFAULT_POLICY_ID, policy, account2, destination2, initiatorB);

        bool expectCollision = (policy.config.rateLimit.sourceScope != RateLimitScope.PerEntity || account1 == account2)
            && (policy.config.rateLimit.destinationScope != RateLimitScope.PerEntity || destination1 == destination2)
            && (policy.config.rateLimit.initiatorScope != RateLimitScope.PerEntity || initiatorA == initiatorB);

        // Verify: assert the expected success result and state updates.
        assertEq(keyA == keyB, expectCollision, "observed key collision should match scope model");
    }

    /// @dev Verifies that dynamic bytes string out of bounds fail closed.
    function testFuzz_dynamicBytesStringOutOfBoundsFailClosed(uint256 offsetSeed, uint256 lengthSeed) public {
        // Setup: build fixture inputs where dynamic bytes string out of bounds fail closed should be denied.
        uint256 badOffset = bound(offsetSeed, 64, 10_000);
        uint256 badLength = bound(lengthSeed, 1, 10_000);

        bytes32 expectedHash = keccak256("expected-dynamic-value");
        bytes32[] memory noProof = new bytes32[](0);

        ParameterConstraint memory bytesConstraint = ParameterConstraint({
            paramType: ParamType.Bytes,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(expectedHash),
            paramValueInListProof: noProof
        });
        bytes memory bytesConstraints = _encodeSingleConstraint(bytesConstraint);

        ParameterConstraint memory stringConstraint = ParameterConstraint({
            paramType: ParamType.String,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(expectedHash),
            paramValueInListProof: noProof
        });
        bytes memory stringConstraints = _encodeSingleConstraint(stringConstraint);

        // Case 1: Offset points beyond available calldata.
        bytes memory badOffsetData = abi.encodePacked(bytes4(0xABCD0001), bytes32(badOffset));

        // Call: execute `areParametersAllowedByConstraintsViaPolicyLibrary` and capture the authorization decision.
        bool bytesOffsetResult =
            harness.areParametersAllowedByConstraintsViaPolicyLibrary(bytesConstraints, badOffsetData);
        bool stringOffsetResult =
            harness.areParametersAllowedByConstraintsViaPolicyLibrary(stringConstraints, badOffsetData);

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(bytesOffsetResult, "bytes offset OOB should fail closed");
        assertFalse(stringOffsetResult, "string offset OOB should fail closed");

        // Case 2: Offset is in-bounds, but declared length exceeds calldata.
        bytes memory badLengthData = abi.encodePacked(bytes4(0xABCD0002), bytes32(uint256(32)), bytes32(badLength));

        bool bytesLengthResult =
            harness.areParametersAllowedByConstraintsViaPolicyLibrary(bytesConstraints, badLengthData);
        bool stringLengthResult =
            harness.areParametersAllowedByConstraintsViaPolicyLibrary(stringConstraints, badLengthData);

        assertFalse(bytesLengthResult, "bytes length OOB should fail closed");
        assertFalse(stringLengthResult, "string length OOB should fail closed");
    }

    /**
     * @dev Verifies token-transfer policies only authorize actual token transfers whose token and destination satisfy
     *      the policy filters.
     * @param useERC20 Whether to test the ERC-20 transfer branch instead of the native-transfer branch
     * @param allowedDestination Allowed transfer recipient encoded into the destination proof
     * @param deniedDestination Distinct disallowed transfer recipient
     * @param tokenContract ERC-20 token contract used for the token-transfer branch
     * @param amountRaw Raw transfer amount used to derive a bounded non-zero amount
     */
    function testFuzz_FLOP_TX_58_isTransactionAllowedByPolicy_tokenTransferPoliciesOnlyAcceptActualMatchingTransfers(
        bool useERC20,
        address allowedDestination,
        address deniedDestination,
        address tokenContract,
        uint96 amountRaw
    ) public {
        // Setup: build one token-transfer policy whose destination proof matches only `allowedDestination`.
        vm.assume(allowedDestination != address(0));
        vm.assume(deniedDestination != address(0));
        vm.assume(allowedDestination != deniedDestination);
        vm.assume(tokenContract != address(0));
        vm.assume(tokenContract != address(0xBAD1));

        uint256 transferAmount = bound(uint256(amountRaw), 1, type(uint96).max);
        (bytes32 destinationRoot, bytes32[] memory destinationProof) =
            _buildAddressRootAndProof(buildArray(allowedDestination, deniedDestination), 0);

        Policy memory policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.TokenTransfers;
        policy.config.destinationType = DestinationType.CustomList;
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = useERC20 ? tokenContract : address(0);
        policy.roots.customDestinationsRoot = destinationRoot;

        bytes32[] memory policyProof = _setPolicyRootForExactPolicyWithSibling(DEFAULT_POLICY_ID, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: new bytes32[](0),
            destinationProof: destinationProof,
            functionProof: new bytes32[](0),
            constraints: bytes("")
        });

        // Verify: only actual token transfers that match both the token filter and the destination proof should pass.
        _assertTokenTransferPolicyOutcomes(
            useERC20, allowedDestination, deniedDestination, tokenContract, transferAmount, proofs
        );
    }

    /**
     * @dev Verifies contract-interaction policies reject token transfers and enforce function, constraint, and
     *      destination checks on the top-level transaction path.
     * @param allowedDestination Allowed interaction target encoded into the destination proof
     * @param deniedDestination Distinct disallowed interaction target
     * @param allowedArg Argument value that satisfies the exact parameter constraint
     * @param deniedArg Distinct argument value that violates the parameter constraint
     */
    function testFuzz_FLOP_TX_59_isTransactionAllowedByPolicy_contractInteractionPoliciesRejectTokenTransfersAndEnforceChecks(
        address allowedDestination,
        address deniedDestination,
        uint256 allowedArg,
        uint256 deniedArg
    ) public {
        // Setup: build one contract-interaction policy with exact destination, selector, and parameter constraints.
        vm.assume(allowedDestination != address(0));
        vm.assume(deniedDestination != address(0));
        vm.assume(allowedDestination != deniedDestination);
        vm.assume(allowedArg != deniedArg);

        bytes4 selector = bytes4(0x11223344);
        (bytes32 destinationRoot, bytes32[] memory destinationProof) =
            _buildAddressRootAndProof(buildArray(allowedDestination, deniedDestination), 0);
        ParameterConstraint memory exactArgConstraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(allowedArg),
            paramValueInListProof: new bytes32[](0)
        });
        bytes memory constraints = _encodeSingleConstraint(exactArgConstraint);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        bytes[] memory constraintsList = new bytes[](1);
        constraintsList[0] = constraints;
        (bytes32 functionRoot, bytes32[] memory functionProof) =
            _buildFunctionRootAndProof(selectors, constraintsList, 0);

        Policy memory policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.ContractInteractions;
        policy.config.destinationType = DestinationType.CustomList;
        policy.config.anyFunction = false;
        policy.roots.customDestinationsRoot = destinationRoot;
        policy.roots.allowedFunctionsRoot = functionRoot;

        bytes32[] memory policyProof = _setPolicyRootForExactPolicyWithSibling(DEFAULT_POLICY_ID, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: new bytes32[](0),
            destinationProof: destinationProof,
            functionProof: functionProof,
            constraints: constraints
        });

        bytes memory validData = abi.encodeWithSelector(selector, allowedArg);
        bytes memory wrongSelectorData = abi.encodeWithSelector(selector ^ bytes4(uint32(1)), allowedArg);
        bytes memory wrongConstraintData = abi.encodeWithSelector(selector, deniedArg);

        // Verify: the contract-interaction path should reject token transfers and fail closed on selector,
        // constraint, or destination mismatches.
        assertTrue(
            harness.isTransactionAllowedByPolicyViaLibrary(
                DEFAULT_POLICY_ID, address(0xAA59), allowedDestination, 0, validData, initiator1, proofs
            ),
            "matching contract interaction should pass"
        );
        assertFalse(
            harness.isTransactionAllowedByPolicyViaLibrary(
                DEFAULT_POLICY_ID,
                address(0xAA59),
                address(0xC59),
                0,
                _encodeERC20Transfer(allowedDestination, bound(allowedArg, 1, type(uint96).max)),
                initiator1,
                proofs
            ),
            "token transfers should fail the contract-interaction policy"
        );
        assertFalse(
            harness.isTransactionAllowedByPolicyViaLibrary(
                DEFAULT_POLICY_ID, address(0xAA59), deniedDestination, 0, validData, initiator1, proofs
            ),
            "wrong destination should fail the contract-interaction policy"
        );
        assertFalse(
            harness.isTransactionAllowedByPolicyViaLibrary(
                DEFAULT_POLICY_ID, address(0xAA59), allowedDestination, 0, wrongSelectorData, initiator1, proofs
            ),
            "wrong selector should fail the contract-interaction policy"
        );
        assertFalse(
            harness.isTransactionAllowedByPolicyViaLibrary(
                DEFAULT_POLICY_ID, address(0xAA59), allowedDestination, 0, wrongConstraintData, initiator1, proofs
            ),
            "wrong parameter value should fail the contract-interaction policy"
        );
    }

    /**
     * @dev Verifies `TransactionType.Any` policies authorize both token transfers and contract interactions only when
     *      the actual destination satisfies the destination filter.
     * @param useTokenTransfer Whether to test the token-transfer class instead of the contract-interaction class
     * @param useERC20 When `useTokenTransfer == true`, whether to test the ERC-20 branch instead of the native branch
     * @param allowedDestination Allowed actual destination encoded into the destination proof
     * @param deniedDestination Distinct disallowed actual destination
     * @param tokenContract ERC-20 token contract used for the ERC-20 transfer branch
     * @param amountRaw Raw amount used to derive a bounded non-zero transfer amount
     */
    function testFuzz_FLOP_TX_60_isTransactionAllowedByPolicy_anyPoliciesAcceptBothTransactionClassesOnlyWhenDestinationAllowed(
        bool useTokenTransfer,
        bool useERC20,
        address allowedDestination,
        address deniedDestination,
        address tokenContract,
        uint96 amountRaw
    ) public {
        // Setup: build one `TransactionType.Any` policy whose destination proof matches only `allowedDestination`.
        vm.assume(allowedDestination != address(0));
        vm.assume(deniedDestination != address(0));
        vm.assume(allowedDestination != deniedDestination);
        vm.assume(tokenContract != address(0));

        uint256 transferAmount = bound(uint256(amountRaw), 1, type(uint96).max);
        (bytes32 destinationRoot, bytes32[] memory destinationProof) =
            _buildAddressRootAndProof(buildArray(allowedDestination, deniedDestination), 0);

        Policy memory policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.Any;
        policy.config.destinationType = DestinationType.CustomList;
        policy.roots.customDestinationsRoot = destinationRoot;

        bytes32[] memory policyProof = _setPolicyRootForExactPolicyWithSibling(DEFAULT_POLICY_ID, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: new bytes32[](0),
            destinationProof: destinationProof,
            functionProof: new bytes32[](0),
            constraints: bytes("")
        });

        (bool allowedResult, bool deniedResult) = _evaluateAnyPolicyTransactionClass(
            useTokenTransfer,
            useERC20,
            allowedDestination,
            deniedDestination,
            tokenContract,
            transferAmount,
            proofs
        );

        // Verify: both transaction classes should be accepted only when the destination filter matches the actual
        // destination derived by the policy helpers.
        assertTrue(allowedResult, "allowed destination should pass for the selected transaction class");
        assertFalse(deniedResult, "disallowed destination should fail for the selected transaction class");
    }

    /**
     * @dev Verifies `TransactionType.Signatures` policies never authorize account-transaction execution or rejection
     *      paths regardless of whether the calldata looks like a native transfer, ERC-20 transfer, or contract
     *      interaction.
     * @param useTokenTransfer Whether to exercise a token-transfer-shaped transaction instead of a contract
     * interaction
     * @param useERC20 When `useTokenTransfer == true`, whether to exercise the ERC-20 branch instead of the native
     * transfer branch
     * @param destination Destination used for native-transfer or contract-interaction branches
     * @param tokenContract ERC-20 token contract used for the ERC-20 transfer branch
     * @param amountRaw Raw amount used to derive a bounded non-zero transfer amount
     */
    function testFuzz_FLOP_TX_61_isTransactionAllowedByPolicy_signaturesPoliciesNeverAuthorizeAccountTransactionPaths(
        bool useTokenTransfer,
        bool useERC20,
        address destination,
        address tokenContract,
        uint96 amountRaw
    ) public {
        // Setup: store one existing `TransactionType.Signatures` policy with otherwise-permissive filters.
        vm.assume(destination != address(0));
        vm.assume(tokenContract != address(0));

        uint256 transferAmount = bound(uint256(amountRaw), 1, type(uint96).max);
        Policy memory policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.Signatures;

        policyStateHarness.setPoliciesRoot(_computePolicyLeaf(DEFAULT_POLICY_ID, policy));
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: new bytes32[](0),
            sourceAccountProof: new bytes32[](0),
            destinationProof: new bytes32[](0),
            functionProof: new bytes32[](0),
            constraints: bytes("")
        });

        PolicyTransactionCase memory txCase =
            _buildSignaturesPolicyTransactionCase(useTokenTransfer, useERC20, destination, tokenContract, transferAmount);

        // Call: evaluate the representative account-transaction path against the signatures-only policy.
        bool allowed = harness.isTransactionAllowedByPolicyViaLibrary(
            DEFAULT_POLICY_ID, address(0xAA61), txCase.to, txCase.value, txCase.data, initiator1, proofs
        );

        // Verify: signature-validation policies should never authorize account-transaction execution/rejection flows.
        assertFalse(allowed, "signatures-only policy should reject every account-transaction path");
    }

    /**
     * @dev Builds a two-leaf policy tree, stores the resulting root, and returns the proof for the exact policy under
     *      test.
     * @param policyId Policy id assigned to the exact policy under test
     * @param policy Exact policy whose proof should be returned
     * @return proof Merkle proof for `policy` at `policyId`
     */
    function _setPolicyRootForExactPolicyWithSibling(uint256 policyId, Policy memory policy)
        internal
        returns (bytes32[] memory proof)
    {
        Policy memory siblingPolicy = _buildBasePolicy();
        siblingPolicy.config.transactionType = TransactionType.Signatures;
        siblingPolicy.config.anyFunction = false;

        uint256[] memory policyIds = new uint256[](2);
        policyIds[0] = policyId;
        policyIds[1] = policyId + 1;
        Policy[] memory policies = new Policy[](2);
        policies[0] = policy;
        policies[1] = siblingPolicy;

        bytes32 root;
        (root, proof) = _buildPolicyRootAndProof(policyIds, policies, 0);
        policyStateHarness.setPoliciesRoot(root);
    }

    /// @dev Verifies token-transfer policy outcomes for matching, wrong-token, and wrong-destination cases.
    /// @param useERC20 Whether to evaluate the ERC-20 transfer branch instead of the native-transfer branch.
    /// @param allowedDestination Allowed destination encoded into the destination proof.
    /// @param deniedDestination Distinct disallowed destination.
    /// @param tokenContract ERC-20 token contract used when `useERC20 == true`.
    /// @param transferAmount Bounded transfer amount used for the token-transfer case.
    /// @param proofs Validation proofs for the exact policy under test.
    function _assertTokenTransferPolicyOutcomes(
        bool useERC20,
        address allowedDestination,
        address deniedDestination,
        address tokenContract,
        uint256 transferAmount,
        ValidationProofs memory proofs
    ) internal view {
        PolicyTransactionCase memory validCase = PolicyTransactionCase({
            to: useERC20 ? tokenContract : allowedDestination,
            value: useERC20 ? 0 : transferAmount,
            data: useERC20 ? _encodeERC20Transfer(allowedDestination, transferAmount) : bytes("")
        });
        PolicyTransactionCase memory wrongDestinationCase = PolicyTransactionCase({
            to: useERC20 ? tokenContract : deniedDestination,
            value: useERC20 ? 0 : transferAmount,
            data: useERC20 ? _encodeERC20Transfer(deniedDestination, transferAmount) : bytes("")
        });

        assertTrue(
            harness.isTransactionAllowedByPolicyViaLibrary(
                DEFAULT_POLICY_ID,
                address(0xAA58),
                validCase.to,
                validCase.value,
                validCase.data,
                initiator1,
                proofs
            ),
            "matching token transfer should pass"
        );
        assertFalse(
            harness.isTransactionAllowedByPolicyViaLibrary(
                DEFAULT_POLICY_ID,
                address(0xAA58),
                useERC20 ? address(0xBAD1) : allowedDestination,
                0,
                useERC20 ? validCase.data : abi.encodeWithSelector(bytes4(0x11223344), transferAmount),
                initiator1,
                proofs
            ),
            "non-transfer or wrong-token inputs should fail the token-transfer policy"
        );
        assertFalse(
            harness.isTransactionAllowedByPolicyViaLibrary(
                DEFAULT_POLICY_ID,
                address(0xAA58),
                wrongDestinationCase.to,
                wrongDestinationCase.value,
                wrongDestinationCase.data,
                initiator1,
                proofs
            ),
            "wrong transfer destination should fail the token-transfer policy"
        );
    }

    /// @dev Evaluates the allowed and denied transaction-class branches for `TransactionType.Any`.
    /// @param useTokenTransfer Whether to evaluate a token-transfer class instead of a contract interaction.
    /// @param useERC20 When `useTokenTransfer == true`, whether to use the ERC-20 branch instead of native transfer.
    /// @param allowedDestination Allowed destination encoded into the destination proof.
    /// @param deniedDestination Distinct disallowed destination.
    /// @param tokenContract ERC-20 token contract used for ERC-20 transfer branches.
    /// @param transferAmount Bounded transfer amount used for the selected transaction class.
    /// @param proofs Validation proofs for the exact policy under test.
    /// @return allowedResult Whether the allowed branch passed policy validation.
    /// @return deniedResult Whether the denied branch passed policy validation.
    function _evaluateAnyPolicyTransactionClass(
        bool useTokenTransfer,
        bool useERC20,
        address allowedDestination,
        address deniedDestination,
        address tokenContract,
        uint256 transferAmount,
        ValidationProofs memory proofs
    ) internal view returns (bool allowedResult, bool deniedResult) {
        if (useTokenTransfer) {
            if (useERC20) {
                allowedResult = harness.isTransactionAllowedByPolicyViaLibrary(
                    DEFAULT_POLICY_ID,
                    address(0xAA60),
                    tokenContract,
                    0,
                    _encodeERC20Transfer(allowedDestination, transferAmount),
                    initiator1,
                    proofs
                );
                deniedResult = harness.isTransactionAllowedByPolicyViaLibrary(
                    DEFAULT_POLICY_ID,
                    address(0xAA60),
                    tokenContract,
                    0,
                    _encodeERC20Transfer(deniedDestination, transferAmount),
                    initiator1,
                    proofs
                );
                return (allowedResult, deniedResult);
            }

            allowedResult = harness.isTransactionAllowedByPolicyViaLibrary(
                DEFAULT_POLICY_ID,
                address(0xAA60),
                allowedDestination,
                transferAmount,
                bytes(""),
                initiator1,
                proofs
            );
            deniedResult = harness.isTransactionAllowedByPolicyViaLibrary(
                DEFAULT_POLICY_ID,
                address(0xAA60),
                deniedDestination,
                transferAmount,
                bytes(""),
                initiator1,
                proofs
            );
            return (allowedResult, deniedResult);
        }

        bytes memory callData = abi.encodeWithSelector(bytes4(0x88776655), transferAmount);
        allowedResult = harness.isTransactionAllowedByPolicyViaLibrary(
            DEFAULT_POLICY_ID, address(0xAA60), allowedDestination, 0, callData, initiator1, proofs
        );
        deniedResult = harness.isTransactionAllowedByPolicyViaLibrary(
            DEFAULT_POLICY_ID, address(0xAA60), deniedDestination, 0, callData, initiator1, proofs
        );
    }

    /// @dev Builds one representative transaction case for a signatures-only policy check.
    /// @param useTokenTransfer Whether to build a token-transfer case instead of a contract interaction.
    /// @param useERC20 When `useTokenTransfer == true`, whether to use the ERC-20 branch instead of native transfer.
    /// @param destination Destination used for the native-transfer or contract-interaction branch.
    /// @param tokenContract ERC-20 token contract used for the ERC-20 transfer branch.
    /// @param transferAmount Bounded transfer amount used for the representative case.
    /// @return txCase The representative transaction case that should still be rejected by a signatures-only policy.
    function _buildSignaturesPolicyTransactionCase(
        bool useTokenTransfer,
        bool useERC20,
        address destination,
        address tokenContract,
        uint256 transferAmount
    ) internal pure returns (PolicyTransactionCase memory txCase) {
        if (useTokenTransfer) {
            if (useERC20) {
                return PolicyTransactionCase({
                    to: tokenContract,
                    value: 0,
                    data: _encodeERC20Transfer(destination, transferAmount)
                });
            }

            return PolicyTransactionCase({to: destination, value: transferAmount, data: bytes("")});
        }

        return PolicyTransactionCase({
            to: destination,
            value: 0,
            data: abi.encodeWithSelector(bytes4(0x55667788), transferAmount)
        });
    }
}
