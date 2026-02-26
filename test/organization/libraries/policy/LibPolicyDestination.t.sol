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
    /// @dev [LPD-GAD-1] Native transfer returns `to` as actual destination.
    function test_getActualDestination_nativeTransfer_returnsTo() public {
        address to = address(0xD501);
        address actual = harness.getActualDestinationViaPolicyLibrary(to, bytes(""), 1 ether);
        assertEq(actual, to, "native transfer destination should be to");
    }

    /// @dev [LPD-GAD-2] Contract interaction (non-token calldata) returns `to`.
    function test_getActualDestination_contractInteraction_returnsTo() public {
        address to = address(0xD502);
        bytes memory data = _encodeERC20Approve(address(0xAAAA), 123);

        address actual = harness.getActualDestinationViaPolicyLibrary(to, data, 0);
        assertEq(actual, to, "non-token interaction destination should be to");
    }

    /// @dev [LPD-GAD-3] ERC-20 transfer returns recipient extracted from calldata.
    function test_getActualDestination_erc20Transfer_returnsTransferRecipient() public {
        address token = address(0xD503);
        address recipient = address(0xD5AA);
        bytes memory data = _encodeERC20Transfer(recipient, 100);

        address actual = harness.getActualDestinationViaPolicyLibrary(token, data, 0);
        assertEq(actual, recipient, "erc20 transfer destination should be transfer recipient");
    }

    /// @dev [LPD-GAD-4] ERC-20 transfer selector with non-zero value is treated as non-token interaction and returns
    /// `to`.
    function test_getActualDestination_transferSelectorWithNonZeroValue_returnsTo() public {
        address token = address(0xD504);
        address recipient = address(0xD5AB);
        bytes memory data = _encodeERC20Transfer(recipient, 100);

        address actual = harness.getActualDestinationViaPolicyLibrary(token, data, 1);
        assertEq(actual, token, "non-zero value should force destination to token contract address");
    }

    /// @dev [LPD-GAD-5] Zero-value, zero-data transaction still returns `to`.
    function test_getActualDestination_zeroValueZeroData_returnsTo() public {
        address to = address(0xD505);
        address actual = harness.getActualDestinationViaPolicyLibrary(to, bytes(""), 0);
        assertEq(actual, to, "zero-value zero-data destination should still be to");
    }

    /// @dev [LPD-GAD-6] Desired behavior: malformed transfer calldata fails closed without ambiguous destination.
    function test_getActualDestination_malformedTransferCalldata_failsClosedToToAddress() public {
        address to = address(0xD506);
        bytes memory malformed = abi.encodePacked(IERC20.transfer.selector, bytes1(0xFF));

        address actual = harness.getActualDestinationViaPolicyLibrary(to, malformed, 0);
        assertEq(actual, to, "malformed transfer calldata should fail closed to to-address");
    }

    /// @dev [LPD-GAD-7] ERC-20 transfer selector with calldata shorter than 68 bytes returns `to`.
    function test_getActualDestination_shortTransferCalldata_returnsTo() public {
        address to = address(0xD507);
        bytes memory shortTransfer = abi.encodePacked(IERC20.transfer.selector, bytes32(uint256(123)));

        address actual = harness.getActualDestinationViaPolicyLibrary(to, shortTransfer, 0);
        assertEq(actual, to, "short transfer calldata should be treated as non-token interaction");
    }

    /// @dev [LPD-ALW-1] DestinationType.Any always returns true.
    function test_isDestinationAllowed_destinationTypeAny_alwaysTrue() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.destinationType = DestinationType.Any;
        policy.roots.customDestinationsRoot = keccak256("unused-root");

        bytes32[] memory fakeProof = new bytes32[](1);
        fakeProof[0] = bytes32(uint256(1));

        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, address(0xD601), 7, hex"deadbeef", fakeProof);
        assertTrue(allowed, "DestinationType.Any should ignore root/proof and always allow");
    }

    /// @dev [LPD-ALW-2] CustomList allows native-transfer destination with valid proof.
    function test_isDestinationAllowed_customListNativeTransferValidProof_returnsTrue() public {
        address destination = address(0xD602);
        address[] memory allowedDestinations = buildArray(destination);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);

        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, destination, 1 ether, bytes(""), proof);
        assertTrue(allowed, "valid destination proof should allow native transfer");
    }

    /// @dev [LPD-ALW-3] CustomList rejects native-transfer destination with invalid proof.
    function test_isDestinationAllowed_customListNativeTransferInvalidProof_returnsFalse() public {
        address destination = address(0xD603);
        address other = address(0xD6AA);
        address[] memory values = buildArray(destination, other);
        (bytes32 root, bytes32[] memory wrongProof) = _buildAddressRootAndProof(values, 1);

        Policy memory policy = _customDestinationPolicy(root);

        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, destination, 1 ether, bytes(""), wrongProof);
        assertFalse(allowed, "invalid proof should reject destination");
    }

    /// @dev [LPD-ALW-4] CustomList checks ERC-20 transfer recipient (not token contract address).
    function test_isDestinationAllowed_customListErc20TransferChecksRecipient() public {
        address token = address(0xD604);
        address recipient = address(0xD6AB);
        address[] memory allowedDestinations = buildArray(recipient);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);
        bytes memory data = _encodeERC20Transfer(recipient, 5);

        bool allowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, token, 0, data, proof);
        assertTrue(allowed, "recipient proof should authorize erc20 transfer destination");
    }

    /// @dev [LPD-ALW-5] CustomList checks contract interaction `to` address.
    function test_isDestinationAllowed_customListContractInteractionChecksTo() public {
        address target = address(0xD605);
        address[] memory allowedDestinations = buildArray(target);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);
        bytes memory data = _encodeERC20Approve(address(0xBBBB), 7);

        bool allowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, target, 0, data, proof);
        assertTrue(allowed, "contract interaction should validate against to-address");
    }

    /// @dev [LPD-ALW-6] Proof for one destination cannot authorize a different destination.
    function test_isDestinationAllowed_proofForDifferentDestination_returnsFalse() public {
        address allowedDestination = address(0xD606);
        address actualDestination = address(0xD6AC);
        address[] memory allowedDestinations = buildArray(allowedDestination);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);

        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, actualDestination, 1 ether, bytes(""), proof);
        assertFalse(allowed, "proof for destination A must not authorize destination B");
    }

    /// @dev [LPD-ALW-7] Unknown destination enum fails closed.
    function test_isDestinationAllowed_invalidDestinationEnum_returnsFalse() public {
        Policy memory policy = _buildBasePolicy();

        bool allowed = harness.isDestinationAllowedByPolicyViaPolicyLibraryRawDestinationType(
            policy, type(uint256).max, address(0xD607), 0, hex"", new bytes32[](0)
        );
        assertFalse(allowed, "invalid destination type should fail closed");
    }

    /// @dev [LPD-ALW-8] Empty proof is valid only for single-leaf custom-destination trees.
    function test_isDestinationAllowed_emptyProofOnlySingleLeafTree_validityMatchesTreeShape() public {
        address destination = address(0xD608);
        address[] memory single = buildArray(destination);
        (bytes32 singleRoot,) = _buildAddressRootAndProof(single, 0);

        Policy memory singleLeafPolicy = _customDestinationPolicy(singleRoot);
        bool singleLeafAllowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
            singleLeafPolicy, destination, 1, bytes(""), new bytes32[](0)
        );
        assertTrue(singleLeafAllowed, "single-leaf tree should accept empty proof");

        address[] memory twoLeaves = buildArray(destination, address(0xD6AD));
        (bytes32 twoLeafRoot,) = _buildAddressRootAndProof(twoLeaves, 0);
        Policy memory multiLeafPolicy = _customDestinationPolicy(twoLeafRoot);

        bool multiLeafAllowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
            multiLeafPolicy, destination, 1, bytes(""), new bytes32[](0)
        );
        assertFalse(multiLeafAllowed, "multi-leaf tree should reject empty proof");
    }

    /// @dev [LPD-ALW-9] Deterministic result for identical inputs.
    function test_isDestinationAllowed_identicalInputs_deterministic() public {
        address destination = address(0xD609);
        address[] memory allowedDestinations = buildArray(destination);
        (bytes32 root, bytes32[] memory proof) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);

        bool first = harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, destination, 1, bytes(""), proof);
        bool second = harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, destination, 1, bytes(""), proof);

        assertEq(first, second, "result must be deterministic");
        assertTrue(first, "both evaluations should be true");
    }

    /// @dev [LPD-ALW-10] Short transfer calldata validates `to`, not encoded recipient.
    function test_isDestinationAllowed_shortTransferCalldata_checksToNotEncodedRecipient() public {
        address token = address(0xD610);
        address encodedRecipient = address(0xD6B0);
        address[] memory allowedDestinations = buildArray(encodedRecipient);
        (bytes32 root, bytes32[] memory proofForRecipient) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);
        bytes memory shortTransfer =
            abi.encodePacked(IERC20.transfer.selector, bytes32(uint256(uint160(encodedRecipient))));

        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, token, 0, shortTransfer, proofForRecipient);
        assertFalse(allowed, "short transfer calldata should evaluate destination as token contract (to)");
    }

    /// @dev [LPD-ALW-11] ERC20-like calldata with non-zero value validates `to`, not encoded recipient.
    function test_isDestinationAllowed_erc20LikeWithNonZeroValue_checksToNotRecipient() public {
        address token = address(0xD611);
        address recipient = address(0xD6B1);
        address[] memory allowedDestinations = buildArray(recipient);
        (bytes32 root, bytes32[] memory proofForRecipient) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);
        bytes memory transferData = _encodeERC20Transfer(recipient, 1);

        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, token, 1, transferData, proofForRecipient);
        assertFalse(allowed, "non-zero value should force destination check on token contract address");
    }

    /// @dev [LPD-ALW-12] Approve interaction checks `to`; proof for encoded spender does not authorize.
    function test_isDestinationAllowed_approveInteraction_checksToNotSpender() public {
        address token = address(0xD612);
        address spender = address(0xD6B2);
        address[] memory allowedDestinations = buildArray(spender);
        (bytes32 root, bytes32[] memory proofForSpender) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);
        bytes memory approveData = _encodeERC20Approve(spender, 10);

        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, token, 0, approveData, proofForSpender);
        assertFalse(allowed, "approve interaction should check token contract address as destination");
    }

    /// @dev [LPD-ALW-13] transferFrom interaction checks `to`; proof for encoded params does not authorize.
    function test_isDestinationAllowed_transferFromInteraction_checksToNotEncodedParams() public {
        address token = address(0xD613);
        address encodedFrom = address(0xD6B3);
        address encodedTo = address(0xD6B4);
        address[] memory allowedDestinations = buildArray(encodedFrom);
        (bytes32 root, bytes32[] memory proofForEncodedValue) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);
        bytes memory transferFromData = _encodeERC20TransferFrom(encodedFrom, encodedTo, 1);

        bool allowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
            policy, token, 0, transferFromData, proofForEncodedValue
        );
        assertFalse(allowed, "transferFrom interaction should check token contract address as destination");
    }

    /// @dev [LPD-ALW-14] Selector-only transfer calldata checks `to`; proof for intended recipient does not authorize.
    function test_isDestinationAllowed_selectorOnlyTransfer_checksToNotRecipient() public {
        address token = address(0xD614);
        address recipient = address(0xD6B5);
        address[] memory allowedDestinations = buildArray(recipient);
        (bytes32 root, bytes32[] memory proofForRecipient) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);

        bool allowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(
            policy, token, 0, abi.encodePacked(IERC20.transfer.selector), proofForRecipient
        );
        assertFalse(allowed, "selector-only transfer calldata should evaluate destination as token contract address");
    }

    /// @dev [LPD-ALW-15] Calldata shorter than selector checks `to`; proof for unrelated address does not authorize.
    function test_isDestinationAllowed_calldataShorterThanSelector_checksToAndRejectsUnrelatedProof() public {
        address to = address(0xD615);
        address unrelated = address(0xD6B6);
        address[] memory allowedDestinations = buildArray(unrelated);
        (bytes32 root, bytes32[] memory proofForUnrelated) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);

        bool allowed =
            harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, to, 0, hex"010203", proofForUnrelated);
        assertFalse(allowed, "short calldata should check to-address and reject unrelated proof");
    }

    /// @dev [LPD-ALW-16] Zero-data, zero-value transaction checks `to`; proof for unrelated address does not authorize.
    function test_isDestinationAllowed_zeroDataZeroValue_checksToAndRejectsUnrelatedProof() public {
        address to = address(0xD616);
        address unrelated = address(0xD6B7);
        address[] memory allowedDestinations = buildArray(unrelated);
        (bytes32 root, bytes32[] memory proofForUnrelated) = _buildAddressRootAndProof(allowedDestinations, 0);

        Policy memory policy = _customDestinationPolicy(root);

        bool allowed = harness.isDestinationAllowedByPolicyViaPolicyLibrary(policy, to, 0, bytes(""), proofForUnrelated);
        assertFalse(allowed, "zero-data zero-value should check to-address and reject unrelated proof");
    }

    function _customDestinationPolicy(bytes32 customDestinationsRoot) internal view returns (Policy memory policy) {
        policy = _buildBasePolicy();
        policy.config.destinationType = DestinationType.CustomList;
        policy.roots.customDestinationsRoot = customDestinationsRoot;
    }
}
