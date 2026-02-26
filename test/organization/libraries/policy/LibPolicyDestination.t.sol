// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PolicyLibrariesSuiteBase} from "test/organization/libraries/policy/PolicyLibrariesSuiteBase.sol";
import {DestinationType, Policy} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibPolicyDestination` wrappers.
 */
contract LibPolicyDestinationTest is PolicyLibrariesSuiteBase {
    /// @dev Verifies that native transfer returns `to` as actual destination.
    function test_getActualDestination_nativeTransfer_returnsTo() public {
        // Setup: configure a valid fixture for native transfer returns `to` as actual destination.
        address to = address(0xD501);
        // Call: execute `getActualDestinationViaPolicyLibrary` with the happy-path payload.
        address actual = harness.getActualDestinationViaPolicyLibrary(to, bytes(""), 1 ether);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, to, "native transfer destination should be to");
    }

    /// @dev Verifies that contract interaction (non-token calldata) returns `to`.
    function test_getActualDestination_contractInteraction_returnsTo() public {
        // Setup: configure a valid fixture for contract interaction (non-token calldata) returns `to`.
        address to = address(0xD502);
        bytes memory data = _encodeERC20Approve(address(0xAAAA), 123);

        // Call: execute `getActualDestinationViaPolicyLibrary` with the happy-path payload.
        address actual = harness.getActualDestinationViaPolicyLibrary(to, data, 0);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, to, "non-token interaction destination should be to");
    }

    /// @dev Verifies that ERC-20 transfer returns recipient extracted from calldata.
    function test_getActualDestination_erc20Transfer_returnsTransferRecipient() public {
        // Setup: configure a valid fixture for ERC-20 transfer returns recipient extracted from calldata.
        address token = address(0xD503);
        address recipient = address(0xD5AA);
        bytes memory data = _encodeERC20Transfer(recipient, 100);

        // Call: execute `getActualDestinationViaPolicyLibrary` with the happy-path payload.
        address actual = harness.getActualDestinationViaPolicyLibrary(token, data, 0);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, recipient, "erc20 transfer destination should be transfer recipient");
    }

    /// @dev Verifies that ERC-20 transfer selector with non-zero value is treated as non-token interaction and returns.
    /// `to`.
    function test_getActualDestination_transferSelectorWithNonZeroValue_returnsTo() public {
        // Setup: configure a valid fixture for this behavior.
        address token = address(0xD504);
        address recipient = address(0xD5AB);
        bytes memory data = _encodeERC20Transfer(recipient, 100);

        // Call: execute `getActualDestinationViaPolicyLibrary` with the happy-path payload.
        address actual = harness.getActualDestinationViaPolicyLibrary(token, data, 1);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, token, "non-zero value should force destination to token contract address");
    }

    /// @dev Verifies that zero-value, zero-data transaction still returns `to`.
    function test_getActualDestination_zeroValueZeroData_returnsTo() public {
        // Setup: configure a valid fixture for zero-value, zero-data transaction still returns `to`.
        address to = address(0xD505);
        // Call: execute `getActualDestinationViaPolicyLibrary` with the happy-path payload.
        address actual = harness.getActualDestinationViaPolicyLibrary(to, bytes(""), 0);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, to, "zero-value zero-data destination should still be to");
    }

    /// @dev Verifies that desired behavior: malformed transfer calldata fails closed without ambiguous destination.
    function test_getActualDestination_malformedTransferCalldata_failsClosedToToAddress() public {
        // Setup: configure a valid fixture for desired behavior: malformed transfer calldata fails closed without ambiguous destination.
        address to = address(0xD506);
        bytes memory malformed = abi.encodePacked(IERC20.transfer.selector, bytes1(0xFF));

        // Call: execute `getActualDestinationViaPolicyLibrary` with the happy-path payload.
        address actual = harness.getActualDestinationViaPolicyLibrary(to, malformed, 0);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, to, "malformed transfer calldata should fail closed to to-address");
    }

    /// @dev Verifies that ERC-20 transfer selector with calldata shorter than 68 bytes returns `to`.
    function test_getActualDestination_shortTransferCalldata_returnsTo() public {
        // Setup: configure a valid fixture for ERC-20 transfer selector with calldata shorter than 68 bytes returns `to`.
        address to = address(0xD507);
        bytes memory shortTransfer = abi.encodePacked(IERC20.transfer.selector, bytes32(uint256(123)));

        // Call: execute `getActualDestinationViaPolicyLibrary` with the happy-path payload.
        address actual = harness.getActualDestinationViaPolicyLibrary(to, shortTransfer, 0);
        // Verify: assert the expected success result and state updates.
        assertEq(actual, to, "short transfer calldata should be treated as non-token interaction");
    }

    /// @dev Verifies that destinationType.Any always returns true.
    function test_isDestinationAllowed_destinationTypeAny_alwaysTrue() public {
        // Setup: configure a valid fixture for destinationType.Any always returns true.
        Policy memory policy = _buildBasePolicy();
        policy.config.destinationType = DestinationType.Any;
        policy.roots.customDestinationsRoot = keccak256("unused-root");

        bytes32[] memory fakeProof = new bytes32[](1);
        fakeProof[0] = bytes32(uint256(1));

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibrary` with the happy-path payload.
        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, address(0xD601), 7, hex"deadbeef", fakeProof);
        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "DestinationType.Any should ignore root/proof and always allow");
    }

    /// @dev Verifies that customList allows native-transfer destination with valid proof.
    function test_isDestinationAllowed_customListNativeTransferValidProof_returnsTrue() public {
        // Setup: configure a valid fixture for customList allows native-transfer destination with valid proof.
        address destination = address(0xD602);
        address[] memory allowedDestinations = buildArray(destination);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibrary` with the happy-path payload.
        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, destination, 1 ether, bytes(""), proof);
        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "valid destination proof should allow native transfer");
    }

    /// @dev Verifies that customList rejects native-transfer destination with invalid proof.
    function test_isDestinationAllowed_customListNativeTransferInvalidProof_returnsFalse() public {
        // Setup: build fixture inputs where customList rejects native-transfer destination with invalid proof should be denied.
        address destination = address(0xD603);
        address other = address(0xD6AA);
        address[] memory values = buildArray(destination, other);
        (bytes32 root, bytes32[] memory wrongProof) = _buildAddressRootAndProof(values, 1);

        Policy memory policy = _customDestinationPolicy(root);

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, destination, 1 ether, bytes(""), wrongProof);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "invalid proof should reject destination");
    }

    /// @dev Verifies that customList checks ERC-20 transfer recipient (not token contract address).
    function test_isDestinationAllowed_customListErc20TransferChecksRecipient() public {
        // Setup: configure a valid fixture for customList checks ERC-20 transfer recipient (not token contract address).
        address token = address(0xD604);
        address recipient = address(0xD6AB);
        address[] memory allowedDestinations = buildArray(recipient);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);
        bytes memory data = _encodeERC20Transfer(recipient, 5);

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, token, 0, data, proof);
        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "recipient proof should authorize erc20 transfer destination");
    }

    /// @dev Verifies that customList checks contract interaction `to` address.
    function test_isDestinationAllowed_customListContractInteractionChecksTo() public {
        // Setup: configure a valid fixture for customList checks contract interaction `to` address.
        address target = address(0xD605);
        address[] memory allowedDestinations = buildArray(target);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);
        bytes memory data = _encodeERC20Approve(address(0xBBBB), 7);

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibrary` with the happy-path payload.
        bool allowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, target, 0, data, proof);
        // Verify: assert the expected success result and state updates.
        assertTrue(allowed, "contract interaction should validate against to-address");
    }

    /// @dev Verifies that proof for one destination cannot authorize a different destination.
    function test_isDestinationAllowed_proofForDifferentDestination_returnsFalse() public {
        // Setup: build fixture inputs where proof for one destination cannot authorize a different destination should be denied.
        address allowedDestination = address(0xD606);
        address actualDestination = address(0xD6AC);
        address[] memory allowedDestinations = buildArray(allowedDestination);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, actualDestination, 1 ether, bytes(""), proof);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "proof for destination A must not authorize destination B");
    }

    /// @dev Verifies that unknown destination enum fails closed.
    function test_isDestinationAllowed_invalidDestinationEnum_returnsFalse() public {
        // Setup: build fixture inputs where unknown destination enum fails closed should be denied.
        Policy memory policy = _buildBasePolicy();

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibraryRawDestinationType` and capture the authorization decision.
        bool allowed = harness.isDestinationAllowedByPolicyViaPolicyLibraryRawDestinationType(
            policy, type(uint256).max, address(0xD607), 0, hex"", new bytes32[](0)
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "invalid destination type should fail closed");
    }

    /// @dev Verifies that empty proof is valid only for single-leaf custom-destination trees.
    function test_isDestinationAllowed_emptyProofOnlySingleLeafTree_validityMatchesTreeShape() public {
        // Setup: prepare contrasting fixtures to cover both pass and fail branches for empty proof is valid only for single-leaf custom-destination trees.
        address destination = address(0xD608);
        address[] memory single = buildArray(destination);
        (bytes32 singleRoot,) = _buildAddressRootAndProof(single, 0);

        Policy memory singleLeafPolicy = _customDestinationPolicy(singleRoot);
        // Call: run `isDestinationAllowedByPolicyViaPolicyLibrary` across the prepared variants.
        bool singleLeafAllowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
            singleLeafPolicy, destination, 1, bytes(""), new bytes32[](0)
        );
        // Verify: assert each variant returns the expected branch outcome.
        assertTrue(singleLeafAllowed, "single-leaf tree should accept empty proof");

        address[] memory twoLeaves = buildArray(destination, address(0xD6AD));
        (bytes32 twoLeafRoot,) = _buildAddressRootAndProof(twoLeaves, 0);
        Policy memory multiLeafPolicy = _customDestinationPolicy(twoLeafRoot);

        bool multiLeafAllowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
            multiLeafPolicy, destination, 1, bytes(""), new bytes32[](0)
        );
        assertFalse(multiLeafAllowed, "multi-leaf tree should reject empty proof");
    }

    /// @dev Verifies that deterministic result for identical inputs.
    function test_isDestinationAllowed_identicalInputs_deterministic() public {
        // Setup: configure a valid fixture for deterministic result for identical inputs.
        address destination = address(0xD609);
        address[] memory allowedDestinations = buildArray(destination);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibrary` with the happy-path payload.
        bool first = harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, destination, 1, bytes(""), proof);
        bool second = harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, destination, 1, bytes(""), proof);

        // Verify: assert the expected success result and state updates.
        assertEq(first, second, "result must be deterministic");
        assertTrue(first, "both evaluations should be true");
    }

    /// @dev Verifies that short transfer calldata validates `to`, not encoded recipient.
    function test_isDestinationAllowed_shortTransferCalldata_checksToNotEncodedRecipient() public {
        // Setup: build fixture inputs where short transfer calldata validates `to`, not encoded recipient should be denied.
        address token = address(0xD610);
        address encodedRecipient = address(0xD6B0);
        address[] memory allowedDestinations = buildArray(encodedRecipient);
        (bytes32 root, bytes32[] memory proofForRecipient) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);
        bytes memory shortTransfer =
            abi.encodePacked(IERC20.transfer.selector, bytes32(uint256(uint160(encodedRecipient))));

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, token, 0, shortTransfer, proofForRecipient);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "short transfer calldata should evaluate destination as token contract (to)");
    }

    /// @dev Verifies that ERC20-like calldata with non-zero value validates `to`, not encoded recipient.
    function test_isDestinationAllowed_erc20LikeWithNonZeroValue_checksToNotRecipient() public {
        // Setup: build fixture inputs where ERC20-like calldata with non-zero value validates `to`, not encoded recipient should be denied.
        address token = address(0xD611);
        address recipient = address(0xD6B1);
        address[] memory allowedDestinations = buildArray(recipient);
        (bytes32 root, bytes32[] memory proofForRecipient) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);
        bytes memory transferData = _encodeERC20Transfer(recipient, 1);

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, token, 1, transferData, proofForRecipient);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "non-zero value should force destination check on token contract address");
    }

    /// @dev Verifies that approve interaction checks `to`; proof for encoded spender does not authorize.
    function test_isDestinationAllowed_approveInteraction_checksToNotSpender() public {
        // Setup: build fixture inputs where approve interaction checks `to`; proof for encoded spender does not authorize should be denied.
        address token = address(0xD612);
        address spender = address(0xD6B2);
        address[] memory allowedDestinations = buildArray(spender);
        (bytes32 root, bytes32[] memory proofForSpender) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);
        bytes memory approveData = _encodeERC20Approve(spender, 10);

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, token, 0, approveData, proofForSpender);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "approve interaction should check token contract address as destination");
    }

    /// @dev Verifies that transferFrom interaction checks `to`; proof for encoded params does not authorize.
    function test_isDestinationAllowed_transferFromInteraction_checksToNotEncodedParams() public {
        // Setup: build fixture inputs where transferFrom interaction checks `to`; proof for encoded params does not authorize should be denied.
        address token = address(0xD613);
        address encodedFrom = address(0xD6B3);
        address encodedTo = address(0xD6B4);
        address[] memory allowedDestinations = buildArray(encodedFrom);
        (bytes32 root, bytes32[] memory proofForEncodedValue) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);
        bytes memory transferFromData = _encodeERC20TransferFrom(encodedFrom, encodedTo, 1);

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
            policy, token, 0, transferFromData, proofForEncodedValue
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "transferFrom interaction should check token contract address as destination");
    }

    /// @dev Verifies that selector-only transfer calldata checks `to`; proof for intended recipient does not authorize.
    function test_isDestinationAllowed_selectorOnlyTransfer_checksToNotRecipient() public {
        // Setup: build fixture inputs where selector-only transfer calldata checks `to`; proof for intended recipient does not authorize should be denied.
        address token = address(0xD614);
        address recipient = address(0xD6B5);
        address[] memory allowedDestinations = buildArray(recipient);
        (bytes32 root, bytes32[] memory proofForRecipient) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
            policy, token, 0, abi.encodePacked(IERC20.transfer.selector), proofForRecipient
        );
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "selector-only transfer calldata should evaluate destination as token contract address");
    }

    /// @dev Verifies that calldata shorter than selector checks `to`; proof for unrelated address does not authorize.
    function test_isDestinationAllowed_calldataShorterThanSelector_checksToAndRejectsUnrelatedProof() public {
        // Setup: build fixture inputs where calldata shorter than selector checks `to`; proof for unrelated address does not authorize should be denied.
        address to = address(0xD615);
        address unrelated = address(0xD6B6);
        address[] memory allowedDestinations = buildArray(unrelated);
        (bytes32 root, bytes32[] memory proofForUnrelated) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, to, 0, hex"010203", proofForUnrelated);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "short calldata should check to-address and reject unrelated proof");
    }

    /// @dev Verifies that zero-data, zero-value transaction checks `to`; proof for unrelated address does not authorize.
    function test_isDestinationAllowed_zeroDataZeroValue_checksToAndRejectsUnrelatedProof() public {
        // Setup: build fixture inputs where zero-data, zero-value transaction checks `to`; proof for unrelated address does not authorize should be denied.
        address to = address(0xD616);
        address unrelated = address(0xD6B7);
        address[] memory allowedDestinations = buildArray(unrelated);
        (bytes32 root, bytes32[] memory proofForUnrelated) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);

        // Call: execute `isDestinationAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, to, 0, bytes(""), proofForUnrelated);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "zero-data zero-value should check to-address and reject unrelated proof");
    }

    function _customDestinationPolicy(bytes32 customDestinationsRoot) internal view returns (Policy memory policy) {
        policy = _buildBasePolicy();
        policy.config.destinationType = DestinationType.CustomList;
        policy.roots.customDestinationsRoot = customDestinationsRoot;
    }
}
