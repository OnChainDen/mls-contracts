// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {
    LibOrganizationPolicySuiteBase
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicySuiteBase.sol";
import {
    ConstraintType,
    DestinationType,
    ParamType,
    ParameterConstraint,
    Policy,
    RateLimitScope,
    RateLimitType,
    TransactionType,
    ValidationProofs
} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationPolicy.isTransactionAllowedByPolicy` and source-account filtering.
 */
contract LibOrganizationPolicyTransactionAllowedTest is LibOrganizationPolicySuiteBase {
    /// @dev Deterministic fixture addresses for transaction-shape tests.
    address internal constant SOURCE_ACCOUNT = address(0xA001);
    address internal constant SOURCE_ACCOUNT_2 = address(0xA002);
    address internal constant TOKEN_CONTRACT = address(0xA100);
    address internal constant RECIPIENT = address(0xA200);
    address internal constant OTHER_RECIPIENT = address(0xA201);
    address internal constant INTERACTION_TARGET = address(0xA300);

    /**
     * @dev Initializes deterministic member fixture state for initiator authorization tests.
     */
    function setUp() public override {
        super.setUp();
        policyStateHarness.setMemberStatus(initiator1, true);
        policyStateHarness.setMemberStatus(initiator2, true);
    }

    /// @dev Verifies that invalid policy proof returns false before downstream validation.
    function test_isTransactionAllowed_invalidPolicyProof_returnsFalse() public {
        // Setup: build fixture inputs where invalid policy proof returns false before downstream validation should be
        // denied.
        Policy memory policy = _buildTokenTransferPolicy();
        bytes32[] memory badPolicyProof = new bytes32[](1);
        badPolicyProof[0] = keccak256("bad-proof");

        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: badPolicyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: _emptyProof(),
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        // Call: execute `isTransactionAllowedByPolicyViaLibrary` and capture the authorization decision.
        bool allowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3001, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 10), initiator1, proofs
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "invalid policy proof must fail closed");
    }

    /// @dev Verifies that source-account mismatch returns false.
    function test_isTransactionAllowed_sourceAccountMismatch_returnsFalse() public {
        // Setup: build fixture inputs where source-account mismatch returns false should be denied.
        Policy memory policy = _buildTokenTransferPolicy();
        policy.config.anySourceAccount = false;

        address[] memory allowedAccounts = new address[](1);
        allowedAccounts[0] = SOURCE_ACCOUNT;
        (bytes32 sourceRoot, bytes32[] memory sourceProof) = _buildAddressRootAndProof(allowedAccounts, 0);
        policy.roots.sourceAccountsRoot = sourceRoot;

        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3002, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: sourceProof,
            destinationProof: _emptyProof(),
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        // Call: execute `isTransactionAllowedByPolicyViaLibrary` and capture the authorization decision.
        bool allowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3002, SOURCE_ACCOUNT_2, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 10), initiator1, proofs
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "source mismatch should fail");
    }

    /// @dev Verifies that unauthorized initiator returns false.
    function test_isTransactionAllowed_unauthorizedInitiator_returnsFalse() public {
        // Setup: build fixture inputs where unauthorized initiator returns false should be denied.
        Policy memory policy = _buildTokenTransferPolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = policy.config.approval.approverType;
        policy.config.initiator.initiatorMember = initiator1;

        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3003, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: _emptyProof(),
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        // Call: execute `isTransactionAllowedByPolicyViaLibrary` and capture the authorization decision.
        bool allowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3003, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 10), initiator2, proofs
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "unauthorized initiator should fail");
    }

    /// @dev Verifies that token-transfer policy rejects non-token transaction.
    function test_isTransactionAllowed_tokenTransferPolicy_nonTokenTransactionReturnsFalse() public {
        // Setup: build fixture inputs where token-transfer policy rejects non-token transaction should be denied.
        Policy memory policy = _buildTokenTransferPolicy();
        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3004, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: _emptyProof(),
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        bytes memory nonTokenData = abi.encodeWithSignature("foo(uint256)", 1);
        // Call: execute `isTransactionAllowedByPolicyViaLibrary` and capture the authorization decision.
        bool allowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3004, SOURCE_ACCOUNT, INTERACTION_TARGET, 0, nonTokenData, initiator1, proofs
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "non-token transaction should not match token-transfer policy");
    }

    /// @dev Verifies that token-transfer policy accepts matching token/destination and rejects disallowed values.
    function test_isTransactionAllowed_tokenTransferPolicy_validAndInvalidCombinations() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for token-transfer policy accepts
        // matching token/destination and rejects disallowed values.
        Policy memory policy = _buildTokenTransferPolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = TOKEN_CONTRACT;
        policy.config.destinationType = DestinationType.CustomList;

        address[] memory destinations = new address[](1);
        destinations[0] = RECIPIENT;
        (bytes32 destinationRoot, bytes32[] memory destinationProof) = _buildAddressRootAndProof(destinations, 0);
        policy.roots.customDestinationsRoot = destinationRoot;

        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3005, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: destinationProof,
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        // Call: run `isTransactionAllowedByPolicyViaLibrary` across the prepared variants.
        bool validAllowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3005, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 10), initiator1, proofs
        );
        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(validAllowed, "matching token/destination should be allowed");

        bool wrongToken = harness.isTransactionAllowedByPolicyViaLibrary(
            3005, SOURCE_ACCOUNT, address(0xBAD), 0, _encodeErc20Transfer(RECIPIENT, 10), initiator1, proofs
        );
        assertFalse(wrongToken, "disallowed token contract should fail");

        bool wrongDestination = harness.isTransactionAllowedByPolicyViaLibrary(
            3005, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(OTHER_RECIPIENT, 10), initiator1, proofs
        );
        assertFalse(wrongDestination, "disallowed recipient should fail");
    }

    /// @dev Verifies that token-transfer policy rejects transfers above configured amount threshold.
    function test_isTransactionAllowed_tokenTransferPolicy_amountAboveThreshold_returnsFalse() public {
        // Setup: configure a token-transfer policy with an inclusive amount threshold.
        Policy memory policy = _buildTokenTransferPolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = TOKEN_CONTRACT;
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 10;

        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3015, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: _emptyProof(),
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        // Call: execute `isTransactionAllowedByPolicyViaLibrary` for equal-threshold and above-threshold transfers.
        bool equalThresholdAllowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3015, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 10), initiator1, proofs
        );
        bool belowThresholdAllowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3015, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 9), initiator1, proofs
        );
        bool aboveThresholdAllowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3015, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 11), initiator1, proofs
        );

        // Verify: equality is allowed while transfers above threshold fail closed in the top-level policy path.
        assertTrue(equalThresholdAllowed, "equal-threshold transfer should be allowed");
        assertTrue(belowThresholdAllowed, "below-threshold transfer should be allowed");
        assertFalse(aboveThresholdAllowed, "above-threshold transfer should fail");
    }

    /// @dev Verifies that contract-interaction policy branch checks function proof, constraints, and value threshold.
    function test_isTransactionAllowed_contractInteractionBranch_checksFunctionConstraintsAndValueThreshold() public {
        // Setup: prepare contrasting fixtures to cover the contract-interaction validator, including a finite
        // contract-call value threshold.
        Policy memory policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.ContractInteractions;
        policy.config.destinationType = DestinationType.CustomList;
        policy.config.anyFunction = false;
        policy.config.valueThresholdForContractCalls = 5;

        address[] memory destinations = new address[](1);
        destinations[0] = INTERACTION_TARGET;
        (bytes32 destinationRoot, bytes32[] memory destinationProof) = _buildAddressRootAndProof(destinations, 0);
        policy.roots.customDestinationsRoot = destinationRoot;

        bytes4 selector = bytes4(keccak256("foo(uint256)"));
        bytes memory callData = abi.encodeWithSelector(selector, 5);

        ParameterConstraint memory exactFive = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(uint256(5))
        });
        bytes memory constraints = _encodeSingleConstraint(exactFive);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        bytes[] memory constraintsList = new bytes[](1);
        constraintsList[0] = constraints;
        (bytes32 functionsRoot, bytes32[] memory functionProof) =
            _buildFunctionRootAndProof(selectors, constraintsList, 0);
        policy.roots.allowedFunctionsRoot = functionsRoot;

        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3006, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: destinationProof,
            functionProof: functionProof,
            constraints: constraints,
            constraintOneOfProofs: bytes("")
        });

        // Call: run `isTransactionAllowedByPolicyViaLibrary` across the prepared variants.
        bool validAllowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3006, SOURCE_ACCOUNT, INTERACTION_TARGET, 5, callData, initiator1, proofs
        );
        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(validAllowed, "valid contract interaction should pass");

        bool belowThresholdAllowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3006, SOURCE_ACCOUNT, INTERACTION_TARGET, 4, callData, initiator1, proofs
        );
        assertTrue(belowThresholdAllowed, "below-threshold contract interaction should pass");

        bool tokenTransferInput = harness.isTransactionAllowedByPolicyViaLibrary(
            3006, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 10), initiator1, proofs
        );
        assertFalse(tokenTransferInput, "token-transfer input should fail contract-interaction policy");

        bytes32[] memory invalidFunctionProof = new bytes32[](1);
        invalidFunctionProof[0] = keccak256("lop-tx-invalid-function-proof");
        ValidationProofs memory badFunctionProofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: destinationProof,
            functionProof: invalidFunctionProof,
            constraints: constraints,
            constraintOneOfProofs: bytes("")
        });
        bool badFunctionAllowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3006, SOURCE_ACCOUNT, INTERACTION_TARGET, 0, callData, initiator1, badFunctionProofs
        );
        assertFalse(badFunctionAllowed, "function proof mismatch should fail");

        bytes memory mismatchedData = abi.encodeWithSelector(selector, 9);
        bool badConstraintAllowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3006, SOURCE_ACCOUNT, INTERACTION_TARGET, 0, mismatchedData, initiator1, proofs
        );
        assertFalse(badConstraintAllowed, "parameter mismatch should fail");

        bool aboveThresholdAllowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3006, SOURCE_ACCOUNT, INTERACTION_TARGET, 6, callData, initiator1, proofs
        );
        assertFalse(aboveThresholdAllowed, "above-threshold contract interaction should fail");
    }

    /// @dev Verifies that `Any` type destination checks and fail-closed enum handling.
    function test_isTransactionAllowed_anyTypeDestinationChecks_andFailClosedEnums() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for `Any` type destination checks
        // and fail-closed enum handling.
        Policy memory policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.Any;
        policy.config.destinationType = DestinationType.CustomList;

        address[] memory destinations = new address[](1);
        destinations[0] = INTERACTION_TARGET;
        (bytes32 destinationRoot, bytes32[] memory destinationProof) = _buildAddressRootAndProof(destinations, 0);
        policy.roots.customDestinationsRoot = destinationRoot;

        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3007, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: destinationProof,
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        // Call: run `isTransactionAllowedByPolicyViaLibrary` across the prepared variants.
        bool allowedDestination = harness.isTransactionAllowedByPolicyViaLibrary(
            3007, SOURCE_ACCOUNT, INTERACTION_TARGET, 0, abi.encodeWithSignature("foo()"), initiator1, proofs
        );
        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(allowedDestination, "allowed destination should pass");

        bool disallowedDestination = harness.isTransactionAllowedByPolicyViaLibrary(
            3007, SOURCE_ACCOUNT, address(0xDEAD), 0, abi.encodeWithSignature("foo()"), initiator1, proofs
        );
        assertFalse(disallowedDestination, "disallowed destination should fail");

        Policy memory signaturesOnly = policy;
        signaturesOnly.config.transactionType = TransactionType.Signatures;
        (bytes32[] memory signaturesPolicyProof,) = _setPolicyRootForSinglePolicy(3008, signaturesOnly);
        ValidationProofs memory signaturesProofs = ValidationProofs({
            policy: signaturesOnly,
            policyProof: signaturesPolicyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: destinationProof,
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });
        bool signaturesTxAllowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3008, SOURCE_ACCOUNT, INTERACTION_TARGET, 0, abi.encodeWithSignature("foo()"), initiator1, signaturesProofs
        );
        assertFalse(signaturesTxAllowed, "signature-only policy must not authorize account transactions");

        bytes memory invalidEnumCallData = abi.encodeCall(
            harness.isTransactionAllowedByPolicyViaLibrary,
            (3007, SOURCE_ACCOUNT, INTERACTION_TARGET, 0, abi.encodeWithSignature("foo()"), initiator1, proofs)
        );
        uint256 proofsOffset = _readWord(invalidEnumCallData, 4 + 6 * 32);
        _setWord(invalidEnumCallData, 4 + proofsOffset, 7);

        // Call: execute low-level call with malformed enum calldata.
        (bool invalidEnumSuccess,) = address(harness).call(invalidEnumCallData);
        // Verify: assert malformed enum values fail with a revert/panic.
        assertFalse(invalidEnumSuccess, "unknown transaction enum should revert");
    }

    /// @dev Verifies that malformed constraints payload reverts in transaction policy validation.
    function test_isTransactionAllowed_malformedConstraints_payloadReverts() public {
        // Setup: use malformed constraints that trigger ABI decode failure in contract-interaction checks.
        Policy memory policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.ContractInteractions;
        policy.config.anyFunction = true;

        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3010, policy);
        bytes memory malformedConstraints = abi.encode(uint256(32), uint256(2));
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: _emptyProof(),
            functionProof: _emptyProof(),
            constraints: malformedConstraints,
            constraintOneOfProofs: bytes("")
        });

        // Verify: malformed constraints should revert in the current implementation.
        // Note: compiler-generated ABI decoder emits revert(0,0) on bounds-check failure — no error selector.
        vm.expectRevert();
        // Call: execute `isTransactionAllowedByPolicyViaLibrary` with malformed constraints.
        harness.isTransactionAllowedByPolicyViaLibrary(
            3010, SOURCE_ACCOUNT, INTERACTION_TARGET, 0, abi.encodeWithSignature("foo(uint256)", 1), initiator1, proofs
        );
    }

    /// @dev Verifies that malformed or non-transfer token calldata fails closed in token-transfer path.
    function test_isTransactionAllowed_tokenTransferMalformedCalldata_failClosed() public {
        // Setup: build fixture inputs where malformed or non-transfer token calldata fails closed in token-transfer
        // path should be denied.
        Policy memory policy = _buildTokenTransferPolicy();
        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3011, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: _emptyProof(),
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(
            // Call: execute `isTransactionAllowedByPolicyViaLibrary` and capture the authorization decision.
            harness.isTransactionAllowedByPolicyViaLibrary(
                3011, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, hex"a9059cbb", initiator1, proofs
            ),
            "selector-only calldata should fail"
        );
        assertFalse(
            harness.isTransactionAllowedByPolicyViaLibrary(
                3011, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, hex"a905", initiator1, proofs
            ),
            "data shorter than selector should fail"
        );
        assertFalse(
            harness.isTransactionAllowedByPolicyViaLibrary(
                3011, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, "", initiator1, proofs
            ),
            "zero-data zero-value should fail"
        );
        assertFalse(
            harness.isTransactionAllowedByPolicyViaLibrary(
                3011, SOURCE_ACCOUNT, TOKEN_CONTRACT, 1, _encodeErc20Transfer(RECIPIENT, 10), initiator1, proofs
            ),
            "erc20-like calldata with non-zero top-level value should fail token-transfer branch"
        );
        assertFalse(
            harness.isTransactionAllowedByPolicyViaLibrary(
                3011, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Approve(RECIPIENT, 10), initiator1, proofs
            ),
            "approve selector should fail token-transfer branch"
        );
        assertFalse(
            harness.isTransactionAllowedByPolicyViaLibrary(
                3011,
                SOURCE_ACCOUNT,
                TOKEN_CONTRACT,
                0,
                _encodeErc20TransferFrom(SOURCE_ACCOUNT, RECIPIENT, 10),
                initiator1,
                proofs
            ),
            "transferFrom selector should fail token-transfer branch"
        );
        assertFalse(
            harness.isTransactionAllowedByPolicyViaLibrary(
                3011,
                SOURCE_ACCOUNT,
                TOKEN_CONTRACT,
                0,
                abi.encodePacked(bytes4(keccak256("bar(uint256)")), bytes32(uint256(1)), bytes32(uint256(2))),
                initiator1,
                proofs
            ),
            "non-transfer selector should fail token-transfer branch"
        );
    }

    /// @dev Verifies that no partial success and deterministic outputs for unchanged inputs/state.
    function test_isTransactionAllowed_noPartialSuccess_andDeterministicResult() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for no partial success and
        // deterministic outputs for unchanged inputs/state.
        Policy memory policy = _buildTokenTransferPolicy();
        policy.config.destinationType = DestinationType.CustomList;

        address[] memory allowedDestinations = new address[](1);
        allowedDestinations[0] = RECIPIENT;
        (bytes32 destinationRoot, bytes32[] memory destinationProof) = _buildAddressRootAndProof(allowedDestinations, 0);
        policy.roots.customDestinationsRoot = destinationRoot;

        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3012, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: destinationProof,
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        bytes memory validTransfer = _encodeErc20Transfer(RECIPIENT, 10);
        // Call: run `isTransactionAllowedByPolicyViaLibrary` across the prepared variants.
        bool first = harness.isTransactionAllowedByPolicyViaLibrary(
            3012, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, validTransfer, initiator1, proofs
        );
        bool second = harness.isTransactionAllowedByPolicyViaLibrary(
            3012, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, validTransfer, initiator1, proofs
        );
        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(first, "all required checks passing should allow");
        assertEq(first, second, "result should be deterministic");

        bool partialFailure = harness.isTransactionAllowedByPolicyViaLibrary(
            3012, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(OTHER_RECIPIENT, 10), initiator1, proofs
        );
        assertFalse(partialFailure, "single failed sub-check must fail full validation");
    }

    /// @dev Verifies that single-leaf policy tree and single-leaf destination tree accept empty proofs.
    function test_isTransactionAllowed_singleLeafProofs_emptyProofAcceptedForPolicyAndDestination() public {
        // Setup: configure a valid fixture for single-leaf policy tree and single-leaf destination tree accept empty
        // proofs.
        Policy memory policy = _buildTokenTransferPolicy();
        policy.config.destinationType = DestinationType.CustomList;

        address[] memory destinations = new address[](1);
        destinations[0] = RECIPIENT;
        (bytes32 destinationRoot,) = _buildAddressRootAndProof(destinations, 0);
        policy.roots.customDestinationsRoot = destinationRoot;

        (bytes32[] memory policyProof, bytes32 root) = _setPolicyRootForSinglePolicy(3013, policy);
        assertEq(root, harness.getPoliciesRoot(), "precondition: root should be set");
        assertEq(policyProof.length, 0, "single-policy tree should use empty policy proof");

        bytes32[] memory emptyDestinationProof = new bytes32[](0);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: emptyDestinationProof,
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });
        // Call: execute `isTransactionAllowedByPolicyViaLibrary` with the happy-path payload.
        bool allowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3013, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 10), initiator1, proofs
        );
        assertTrue(allowed, "single-leaf policy and destination trees should accept empty proofs");
    }

    /// @dev Verifies that fuzz random non-`transfer` selectors in 68-byte payload fail token-transfer policy.
    function testFuzz_isTransactionAllowed_tokenTransferPolicy_randomNonTransferSelectorFails(bytes4 selector) public {
        // Setup: build fixture inputs where fuzz random non-`transfer` selectors in 68-byte payload fail token-transfer
        // policy should be denied.
        vm.assume(selector != bytes4(0xa9059cbb));
        Policy memory policy = _buildTokenTransferPolicy();
        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3014, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: _emptyProof(),
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        bytes memory payload = abi.encodePacked(selector, bytes32(uint256(uint160(RECIPIENT))), bytes32(uint256(1)));
        // Call: execute `isTransactionAllowedByPolicyViaLibrary` and capture the authorization decision.
        bool allowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3014, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, payload, initiator1, proofs
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "random non-transfer selector should fail");
    }

    /// @dev Verifies that `isSourceAccountAllowedByPolicy` source filter semantics.
    function test_isSourceAccountAllowedByPolicy_sourceFilterModes() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for `isSourceAccountAllowedByPolicy`
        // source filter semantics.
        Policy memory anyPolicy = _buildBasePolicy();
        anyPolicy.config.anySourceAccount = true;
        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(
            // Call: run `isSourceAccountAllowedByPolicyViaLibrary` across the prepared variants.
            harness.isSourceAccountAllowedByPolicyViaLibrary(anyPolicy, SOURCE_ACCOUNT, _emptyProof()),
            "any-source mode should allow any account"
        );

        Policy memory specificPolicy = _buildBasePolicy();
        specificPolicy.config.anySourceAccount = false;
        address[] memory allowedAccounts = new address[](1);
        allowedAccounts[0] = SOURCE_ACCOUNT;
        (bytes32 sourceRoot, bytes32[] memory sourceProof) = _buildAddressRootAndProof(allowedAccounts, 0);
        specificPolicy.roots.sourceAccountsRoot = sourceRoot;

        assertTrue(
            harness.isSourceAccountAllowedByPolicyViaLibrary(specificPolicy, SOURCE_ACCOUNT, sourceProof),
            "valid source account proof should pass"
        );
        assertFalse(
            harness.isSourceAccountAllowedByPolicyViaLibrary(specificPolicy, SOURCE_ACCOUNT_2, sourceProof),
            "proof for different account should fail"
        );

        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256("bad-source-proof");
        assertFalse(
            harness.isSourceAccountAllowedByPolicyViaLibrary(specificPolicy, SOURCE_ACCOUNT, invalidProof),
            "invalid source proof should fail"
        );

        specificPolicy.roots.sourceAccountsRoot = keccak256("unknown-root");
        assertFalse(
            harness.isSourceAccountAllowedByPolicyViaLibrary(specificPolicy, SOURCE_ACCOUNT, sourceProof),
            "unknown source root should fail closed"
        );

        // Empty proof is valid only in single-leaf case (already covered by valid case above).
        assertFalse(
            harness.isSourceAccountAllowedByPolicyViaLibrary(specificPolicy, SOURCE_ACCOUNT, _emptyProof()),
            "empty proof should fail when root is not a single-leaf self root"
        );
    }

    /// @dev Verifies that a `TokenTransfers + anyToken + hasAmountThreshold` policy reverts when evaluated.
    function test_isTransactionAllowed_anyTokenWithAmountThreshold_reverts() public {
        // Setup: build a token-transfer policy that pairs `anyToken` with a raw-amount threshold.
        // This combination compares amounts across tokens with different decimals, so it cannot
        // express a meaningful cap and must be rejected at evaluation time.
        Policy memory policy = _buildTokenTransferPolicy();
        policy.config.token.anyToken = true;
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 100;

        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3100, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: _emptyProof(),
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        // Call: invoke `isTransactionAllowedByPolicyViaLibrary` against the malformed policy.
        // Verify: the call reverts with `AnyTokenIncompatibleWithAmountOrRateLimit`.
        vm.expectRevert(IOrganizationPolicy.AnyTokenIncompatibleWithAmountOrRateLimit.selector);
        harness.isTransactionAllowedByPolicyViaLibrary(
            3100, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 1), initiator1, proofs
        );
    }

    /// @dev Verifies that a `TokenTransfers + anyToken + TimeInterval` rate limit policy reverts when evaluated.
    function test_isTransactionAllowed_anyTokenWithTimeIntervalRateLimit_reverts() public {
        // Setup: build a token-transfer policy that pairs `anyToken` with a time-interval rate
        // limit. The rate-limit bucket accrues raw token amounts for token-transfer policies,
        // so the cumulative cap is meaningless across tokens with different decimals.
        Policy memory policy = _buildTokenTransferPolicy();
        policy.config.token.anyToken = true;
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 24;
        policy.config.rateLimit.timeIntervalLimit = 1000;

        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3101, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: _emptyProof(),
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        // Call: invoke `isTransactionAllowedByPolicyViaLibrary` against the malformed policy.
        // Verify: the call reverts with `AnyTokenIncompatibleWithAmountOrRateLimit` regardless
        // of the rate-limit scopes or window configuration.
        vm.expectRevert(IOrganizationPolicy.AnyTokenIncompatibleWithAmountOrRateLimit.selector);
        harness.isTransactionAllowedByPolicyViaLibrary(
            3101, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 1), initiator1, proofs
        );
    }

    /// @dev Verifies that combining all three of `anyToken`, amount threshold, and rate limit reverts.
    function test_isTransactionAllowed_anyTokenWithAmountAndRateLimit_reverts() public {
        // Setup: build a token-transfer policy with `anyToken`, a raw-amount threshold, and a
        // time-interval rate limit set together. Either footgun alone reverts, and both
        // present together should still surface the same single error.
        Policy memory policy = _buildTokenTransferPolicy();
        policy.config.token.anyToken = true;
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 50;
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 100;

        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3102, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: _emptyProof(),
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        // Call: invoke `isTransactionAllowedByPolicyViaLibrary` against the malformed policy.
        // Verify: the policy still reverts with `AnyTokenIncompatibleWithAmountOrRateLimit`
        // when both incompatibilities are present at once.
        vm.expectRevert(IOrganizationPolicy.AnyTokenIncompatibleWithAmountOrRateLimit.selector);
        harness.isTransactionAllowedByPolicyViaLibrary(
            3102, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 1), initiator1, proofs
        );
    }

    /// @dev Verifies that `anyToken` alone (no amount threshold, no rate limit) is still allowed.
    function test_isTransactionAllowed_anyTokenWithoutAmountOrRateLimit_allowed() public {
        // Setup: build a token-transfer policy with `anyToken` but no amount cap and no rate
        // limit. This is the documented "match any token, do not cap the amount" use case and
        // must remain functional after the footgun guard is added.
        Policy memory policy = _buildTokenTransferPolicy();
        policy.config.token.anyToken = true;
        policy.config.token.hasAmountThreshold = false;
        policy.config.rateLimit.limitType = RateLimitType.None;

        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3103, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: _emptyProof(),
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        // Call: execute `isTransactionAllowedByPolicyViaLibrary` for a normal ERC-20 transfer.
        bool allowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3103, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 1), initiator1, proofs
        );
        // Verify: `anyToken` without any raw-amount-based controls still authorizes the transfer.
        assertTrue(allowed, "anyToken without amount/rate limit should still pass");
    }

    /// @dev Verifies that a specific-token policy with amount threshold and rate limit is still allowed.
    function test_isTransactionAllowed_specificTokenWithAmountAndRateLimit_allowed() public {
        // Setup: build a token-transfer policy pinned to a single token with both a raw-amount
        // threshold and a time-interval rate limit. The guard only targets `anyToken`, so this
        // single-token configuration must keep working.
        Policy memory policy = _buildTokenTransferPolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = TOKEN_CONTRACT;
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 100;
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 24;
        policy.config.rateLimit.timeIntervalLimit = 500;
        policy.config.rateLimit.sourceScope = RateLimitScope.AcrossAll;
        policy.config.rateLimit.destinationScope = RateLimitScope.AcrossAll;
        policy.config.rateLimit.initiatorScope = RateLimitScope.AcrossAll;

        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3104, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: _emptyProof(),
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        // Call: execute `isTransactionAllowedByPolicyViaLibrary` for an at-threshold transfer.
        bool allowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3104, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 50), initiator1, proofs
        );
        // Verify: a single-token policy with raw-amount caps remains allowed because each cap
        // is calibrated against one token's decimals.
        assertTrue(allowed, "specific-token policy with amount and rate limit should still pass");
    }

    /// @dev Verifies that an `Any` transactionType policy with `anyToken` and a rate limit is not blocked.
    function test_isTransactionAllowed_anyTransactionTypeWithAnyTokenAndRateLimit_allowed() public {
        // Setup: build an `Any`-type policy with both `anyToken` and a time-interval rate limit.
        // For `Any` policies the rate-limit bucket accrues `1` per call (count-based), not raw
        // token amounts, so the cross-decimal footgun does not apply and the policy is valid.
        Policy memory policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.Any;
        policy.config.token.anyToken = true;
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 1;
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 24;
        policy.config.rateLimit.timeIntervalLimit = 10;

        (bytes32[] memory policyProof,) = _setPolicyRootForSinglePolicy(3105, policy);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: policyProof,
            sourceAccountProof: _emptyProof(),
            destinationProof: _emptyProof(),
            functionProof: _emptyProof(),
            constraints: "",
            constraintOneOfProofs: bytes("")
        });

        // Call: execute `isTransactionAllowedByPolicyViaLibrary` for an ERC-20 transfer that
        // would exceed the meaningless `amountThreshold` if it were enforced for `Any`
        // policies, which it is not.
        bool allowed = harness.isTransactionAllowedByPolicyViaLibrary(
            3105, SOURCE_ACCOUNT, TOKEN_CONTRACT, 0, _encodeErc20Transfer(RECIPIENT, 999), initiator1, proofs
        );
        // Verify: the guard only fires for `TokenTransfers` policies, so `Any` policies with
        // the same fields set remain authorized.
        assertTrue(allowed, "Any-type policy should not be blocked by the anyToken guard");
    }

    /**
     * @dev Helper: builds a permissive token-transfer policy fixture.
     */
    function _buildTokenTransferPolicy() internal view returns (Policy memory policy) {
        policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.TokenTransfers;
        policy.config.anySourceAccount = true;
        policy.config.destinationType = DestinationType.Any;
        policy.config.token.anyToken = true;
    }

    /**
     * @dev Helper: configures root/proof for a single policy leaf.
     */
    function _setPolicyRootForSinglePolicy(uint256 policyId, Policy memory policy)
        internal
        returns (bytes32[] memory proof, bytes32 root)
    {
        uint256[] memory policyIds = new uint256[](1);
        policyIds[0] = policyId;
        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;
        (root, proof) = _buildPolicyRootAndProof(policyIds, policies, 0);
        harness.setPoliciesRoot(root);
    }

    /**
     * @dev Helper: returns an empty proof array.
     */
    function _emptyProof() internal pure returns (bytes32[] memory proof) {
        proof = new bytes32[](0);
    }
}
