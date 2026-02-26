// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesSuiteBase} from "test/organization/libraries/policy/PolicyLibrariesSuiteBase.sol";
import {DestinationType, Policy} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibPolicyTokenTransfer` wrappers.
 */
contract LibPolicyTokenTransferTest is PolicyLibrariesSuiteBase {
    /// @dev [LPT-1] Valid token + amount + destination returns true.
    function test_isTokenTransferAllowed_validTokenAmountDestination_returnsTrue() public {
        address token = address(0x7601);
        address recipient = address(0xA601);
        uint256 amount = 100;

        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = token;
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = amount + 1;

        bytes32[] memory destinationProof;
        (policy.roots.customDestinationsRoot, destinationProof) = _buildSingleDestinationRootAndProof(recipient);
        policy.config.destinationType = DestinationType.CustomList;

        bool allowed = harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(
            policy, token, 0, _encodeERC20Transfer(recipient, amount), destinationProof
        );
        assertTrue(allowed, "valid token transfer should be allowed");
    }

    /// @dev [LPT-2] Disallowed token returns false.
    function test_isTokenTransferAllowed_disallowedToken_returnsFalse() public {
        address configuredToken = address(0x7602);
        address actualToken = address(0xB602);
        address recipient = address(0xA602);

        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = configuredToken;
        policy.config.destinationType = DestinationType.Any;

        bool allowed = harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(
            policy, actualToken, 0, _encodeERC20Transfer(recipient, 1), new bytes32[](0)
        );
        assertFalse(allowed, "non-configured token should be rejected");
    }

    /// @dev [LPT-3] Amount above threshold returns false.
    function test_isTokenTransferAllowed_amountAboveThreshold_returnsFalse() public {
        address token = address(0x7603);
        address recipient = address(0xA603);

        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = token;
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 50;
        policy.config.destinationType = DestinationType.Any;

        bool allowed = harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(
            policy, token, 0, _encodeERC20Transfer(recipient, 51), new bytes32[](0)
        );
        assertFalse(allowed, "amount above threshold should be rejected");
    }

    /// @dev [LPT-4] Disallowed destination returns false.
    function test_isTokenTransferAllowed_disallowedDestination_returnsFalse() public {
        address token = address(0x7604);
        address recipient = address(0xA604);
        address differentRecipient = address(0xB604);

        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = token;
        policy.config.token.hasAmountThreshold = false;
        policy.config.destinationType = DestinationType.CustomList;

        bytes32[] memory proofForDifferentRecipient;
        (policy.roots.customDestinationsRoot, proofForDifferentRecipient) =
            _buildSingleDestinationRootAndProof(differentRecipient);

        bool allowed = harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(
            policy, token, 0, _encodeERC20Transfer(recipient, 1), proofForDifferentRecipient
        );
        assertFalse(allowed, "destination not in custom list should be rejected");
    }

    /// @dev [LPT-5] `anyToken == true` allows native and ERC-20 token addresses.
    function test_isTokenTransferAllowed_anyTokenAllowsNativeAndErc20() public {
        address nativeRecipient = address(0xA605);
        address token = address(0x7605);
        address erc20Recipient = address(0xB605);

        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = true;
        policy.config.destinationType = DestinationType.Any;

        bool nativeAllowed = harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(
            policy, nativeRecipient, 1 ether, bytes(""), new bytes32[](0)
        );
        bool erc20Allowed = harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(
            policy, token, 0, _encodeERC20Transfer(erc20Recipient, 10), new bytes32[](0)
        );

        assertTrue(nativeAllowed, "native transfer should be allowed when anyToken is true");
        assertTrue(erc20Allowed, "erc20 transfer should be allowed when anyToken is true");
    }

    /// @dev [LPT-6] Specific native-token policy allows only native transfers.
    function test_isTokenTransferAllowed_specificNativeTokenPolicy_allowsOnlyNative() public {
        address nativeRecipient = address(0xA606);
        address token = address(0x7606);

        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = address(0);
        policy.config.destinationType = DestinationType.Any;

        bool nativeAllowed = harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(
            policy, nativeRecipient, 1, bytes(""), new bytes32[](0)
        );
        bool erc20Allowed = harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(
            policy, token, 0, _encodeERC20Transfer(address(0xB606), 1), new bytes32[](0)
        );

        assertTrue(nativeAllowed, "native transfer should be allowed for native token policy");
        assertFalse(erc20Allowed, "erc20 transfer should be rejected for native token policy");
    }

    /// @dev [LPT-7] Specific ERC-20 token policy allows only that token contract.
    function test_isTokenTransferAllowed_specificErc20Policy_allowsOnlyConfiguredToken() public {
        address configuredToken = address(0x7607);
        address otherToken = address(0xB607);
        address recipient = address(0xA607);

        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = configuredToken;
        policy.config.destinationType = DestinationType.Any;

        bool configuredAllowed = harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(
            policy, configuredToken, 0, _encodeERC20Transfer(recipient, 1), new bytes32[](0)
        );
        bool otherAllowed = harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(
            policy, otherToken, 0, _encodeERC20Transfer(recipient, 1), new bytes32[](0)
        );
        bool nativeAllowed =
            harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(policy, recipient, 1, bytes(""), new bytes32[](0));

        assertTrue(configuredAllowed, "configured erc20 token should be allowed");
        assertFalse(otherAllowed, "other erc20 token should be rejected");
        assertFalse(nativeAllowed, "native transfer should be rejected under specific erc20 policy");
    }

    /// @dev [LPT-8] All sub-checks must pass; no short-circuit bypass.
    function test_isTokenTransferAllowed_allChecksMustPass_noShortCircuitBypass() public {
        address token = address(0x7608);
        address recipient = address(0xA608);
        address allowedRecipient = address(0xB608);

        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = token;
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 10;
        policy.config.destinationType = DestinationType.CustomList;
        (policy.roots.customDestinationsRoot,) = _buildSingleDestinationRootAndProof(allowedRecipient);

        bool wrongToken = harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(
            policy, address(0xBAD0), 0, _encodeERC20Transfer(allowedRecipient, 1), new bytes32[](0)
        );
        bool highAmount = harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(
            policy, token, 0, _encodeERC20Transfer(allowedRecipient, 11), new bytes32[](0)
        );
        bool wrongDestination = harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(
            policy, token, 0, _encodeERC20Transfer(recipient, 1), new bytes32[](0)
        );

        assertFalse(wrongToken, "wrong token must fail even if other checks pass");
        assertFalse(highAmount, "amount above threshold must fail even if other checks pass");
        assertFalse(wrongDestination, "wrong destination must fail even if other checks pass");
    }

    /// @dev [LPT-9] Desired behavior: non-token-transfer calldata should fail closed.
    function test_isTokenTransferAllowed_nonTokenTransferCalldata_rejected_desired() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = true;
        policy.config.token.hasAmountThreshold = false;
        policy.config.destinationType = DestinationType.Any;

        bool allowed = harness.isTokenTransferAllowedByPolicyViaPolicyLibrary(
            policy, address(0x7609), 0, _encodeERC20Approve(address(0xA609), 1), new bytes32[](0)
        );
        assertFalse(allowed, "desired behavior: non-transfer calldata should be rejected");
    }

    /// @dev [LPT-TKN-1] `anyToken == true` returns true.
    function test_isTokenAllowedByPolicy_anyTokenTrue_returnsTrue() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = true;

        bool allowed = harness.isTokenAllowedByPolicyViaPolicyLibrary(policy, address(0xAA01), hex"deadbeef");
        assertTrue(allowed, "anyToken should bypass token-address filtering");
    }

    /// @dev [LPT-TKN-2] Native transfers use `address(0)` as token identity.
    function test_isTokenAllowedByPolicy_nativeTransferUsesAddressZeroIdentity() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = address(0);

        bool allowed = harness.isTokenAllowedByPolicyViaPolicyLibrary(policy, address(0xAA02), bytes(""));
        assertTrue(allowed, "native transfer should map to token address(0)");
    }

    /// @dev [LPT-TKN-3] ERC-20 transfers use `to` as token contract identity.
    function test_isTokenAllowedByPolicy_erc20TransferUsesToAsTokenIdentity() public {
        address token = address(0xAA03);
        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = token;

        bool allowed =
            harness.isTokenAllowedByPolicyViaPolicyLibrary(policy, token, _encodeERC20Transfer(address(0xB603), 1));
        assertTrue(allowed, "erc20 transfer should use to-address as token identity");
    }

    /// @dev [LPT-TKN-4] Non-matching configured token returns false.
    function test_isTokenAllowedByPolicy_nonMatchingConfiguredToken_returnsFalse() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = address(0xAA04);

        bool allowed = harness.isTokenAllowedByPolicyViaPolicyLibrary(
            policy, address(0xAA05), _encodeERC20Transfer(address(0xB604), 1)
        );
        assertFalse(allowed, "non-matching token should be rejected");
    }

    /// @dev [LPT-TKN-5] Deterministic output for identical inputs.
    function test_isTokenAllowedByPolicy_identicalInputs_deterministic() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.token.anyToken = false;
        policy.config.token.tokenAddress = address(0xAA06);

        bytes memory data = _encodeERC20Transfer(address(0xB605), 77);
        bool first = harness.isTokenAllowedByPolicyViaPolicyLibrary(policy, address(0xAA06), data);
        bool second = harness.isTokenAllowedByPolicyViaPolicyLibrary(policy, address(0xAA06), data);

        assertEq(first, second, "token-allowance check should be deterministic");
        assertTrue(first, "both checks should pass");
    }

    /// @dev [LPT-AMT-1] `hasAmountThreshold == false` always returns true.
    function test_isTokenAmountAllowedByPolicy_thresholdDisabled_alwaysTrue() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.token.hasAmountThreshold = false;

        bool allowed = harness.isTokenAmountAllowedByPolicyViaPolicyLibrary(policy, hex"010203", type(uint256).max);
        assertTrue(allowed, "disabled threshold should always allow");
    }

    /// @dev [LPT-AMT-2] Amount below threshold returns true.
    function test_isTokenAmountAllowedByPolicy_amountBelowThreshold_returnsTrue() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 101;

        bool allowed =
            harness.isTokenAmountAllowedByPolicyViaPolicyLibrary(policy, _encodeERC20Transfer(address(0xB606), 100), 0);
        assertTrue(allowed, "amount below threshold should pass");
    }

    /// @dev [LPT-AMT-3] Desired behavior: amount equal to threshold should be allowed (inclusive max).
    function test_isTokenAmountAllowedByPolicy_amountEqualThreshold_allowed_desired() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 100;

        bool allowed =
            harness.isTokenAmountAllowedByPolicyViaPolicyLibrary(policy, _encodeERC20Transfer(address(0xB607), 100), 0);
        assertTrue(allowed, "desired behavior: threshold should be inclusive");
    }

    /// @dev [LPT-AMT-4] Amount above threshold returns false.
    function test_isTokenAmountAllowedByPolicy_amountAboveThreshold_returnsFalse() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 100;

        bool allowed =
            harness.isTokenAmountAllowedByPolicyViaPolicyLibrary(policy, _encodeERC20Transfer(address(0xB608), 101), 0);
        assertFalse(allowed, "amount above threshold should fail");
    }

    /// @dev [LPT-AMT-5] Threshold `0`: desired behavior allows only zero-amount transfers.
    function test_isTokenAmountAllowedByPolicy_thresholdZero_allowsOnlyZeroAmount_desired() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 0;

        bool zeroAmountAllowed = harness.isTokenAmountAllowedByPolicyViaPolicyLibrary(policy, bytes(""), 0);
        bool nonZeroAllowed = harness.isTokenAmountAllowedByPolicyViaPolicyLibrary(policy, bytes(""), 1);

        assertTrue(zeroAmountAllowed, "desired behavior: zero amount should pass for threshold 0");
        assertFalse(nonZeroAllowed, "desired behavior: non-zero amount should fail for threshold 0");
    }

    /// @dev [LPT-AMT-6] Native amount extraction uses top-level `value`.
    function test_isTokenAmountAllowedByPolicy_nativeAmountUsesValue() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 5;

        bool below = harness.isTokenAmountAllowedByPolicyViaPolicyLibrary(policy, bytes(""), 4);
        bool above = harness.isTokenAmountAllowedByPolicyViaPolicyLibrary(policy, bytes(""), 6);

        assertTrue(below, "native amount below threshold should pass");
        assertFalse(above, "native amount above threshold should fail");
    }

    /// @dev [LPT-AMT-7] Desired behavior: malformed ERC-20 amount calldata fails closed without revert.
    function test_isTokenAmountAllowedByPolicy_malformedErc20AmountCalldata_failsClosed_desired() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 10;

        bytes memory malformed = abi.encodePacked(bytes4(keccak256("transfer(address,uint256)")), bytes32(uint256(1)));
        bool allowed = harness.isTokenAmountAllowedByPolicyViaPolicyLibrary(policy, malformed, 0);
        assertFalse(allowed, "desired behavior: malformed amount calldata should fail closed");
    }

    /// @dev [LPT-AMT-8] Desired behavior: non-transfer selector calldata with threshold enabled fails closed.
    function test_isTokenAmountAllowedByPolicy_nonTransferSelectorWithThresholdEnabled_failsClosed_desired() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 100;

        bool allowed =
            harness.isTokenAmountAllowedByPolicyViaPolicyLibrary(policy, _encodeERC20Approve(address(0xB609), 1), 0);
        assertFalse(allowed, "desired behavior: non-transfer selector should fail closed");
    }

    function _buildSingleDestinationRootAndProof(address destination)
        internal
        returns (bytes32 root, bytes32[] memory proof)
    {
        address[] memory values = buildArray(destination);
        return _buildAddressRootAndProof(values, 0);
    }
}
