// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ContractInteractionUtils} from "libraries/ContractInteractionUtils.sol";

/**
 * @dev ContractInteractionUtilsHarness
 *      Test harness that exposes the internal ContractInteractionUtils.extractFunctionSelector
 *      function via a public wrapper. Uses `external` because the library function takes
 *      `calldata` parameters.
 */
contract ContractInteractionUtilsHarness {
    /// @dev Exposes selector extraction for calldata-based fuzz and unit tests.
    /// @param data Calldata blob whose first four bytes are interpreted as a selector.
    /// @return selector The extracted selector.
    function extractFunctionSelector(bytes calldata data) external pure returns (bytes4) {
        return ContractInteractionUtils.extractFunctionSelector(data);
    }
}

/**
 * @dev ContractInteractionUtilsTest
 *      Tests for ContractInteractionUtils library.
 *      Covers function selector extraction from calldata, including boundary cases
 *      (exactly 4 bytes), known selectors, and fuzz testing.
 * @author Den Technologies Inc
 */
contract ContractInteractionUtilsTest is Test {
    ContractInteractionUtilsHarness public harness;

    /// @dev Deploys the harness exposing selector extraction wrappers.
    function setUp() public {
        harness = new ContractInteractionUtilsHarness();
    }

    /// @dev Test case: Valid calldata (standard ERC-20 transfer, 68 bytes) should extract the correct 4-byte selector
    ///      matching the known transfer(address,uint256) selector.
    function test_extractFunctionSelector_validCalldata_extractsCorrectSelector() public view {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, address(0xBEEF), uint256(100));

        bytes4 selector = harness.extractFunctionSelector(data);

        assertEq(selector, IERC20.transfer.selector, "Should extract transfer selector (0xa9059cbb)");
    }

    /// @dev Test case: Exactly 4 bytes of calldata (minimum valid input) should return those 4 bytes as the selector.
    ///      [TXUT-PARSE-4]
    function test_TXUT_PARSE_4_A_extractFunctionSelector_exactly4Bytes_returnsThoseBytes() public view {
        bytes memory data = hex"deadbeef";
        assertEq(data.length, 4, "Data should be exactly 4 bytes");

        bytes4 selector = harness.extractFunctionSelector(data);

        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(selector, bytes4(hex"deadbeef"), "Should return the 4 bytes as the selector"); // Safe: literal hex
    }

    /// @dev Test case: Known ERC-20 function selectors (transfer, approve, transferFrom) should all be extracted
    ///      correctly.
    function test_extractFunctionSelector_knownSelectors_allMatch() public view {
        // transfer(address,uint256) = 0xa9059cbb
        bytes memory transferData = abi.encodeWithSelector(IERC20.transfer.selector, address(0x1), uint256(1));
        assertEq(
            harness.extractFunctionSelector(transferData), IERC20.transfer.selector, "transfer selector should match"
        );

        // approve(address,uint256) = 0x095ea7b3
        bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, address(0x1), uint256(1));
        assertEq(harness.extractFunctionSelector(approveData), IERC20.approve.selector, "approve selector should match");

        // transferFrom(address,address,uint256) = 0x23b872dd
        bytes memory transferFromData =
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(0x1), address(0x2), uint256(1));
        assertEq(
            harness.extractFunctionSelector(transferFromData),
            IERC20.transferFrom.selector,
            "transferFrom selector should match"
        );
    }

    /// @dev Test case: Data shorter than 4 bytes should revert with an out-of-bounds calldata slice.
    function test_extractFunctionSelector_dataTooShort_reverts() public {
        // 0 bytes
        vm.expectRevert();
        harness.extractFunctionSelector(hex"");

        // 1 byte
        vm.expectRevert();
        harness.extractFunctionSelector(hex"aa");

        // 2 bytes
        vm.expectRevert();
        harness.extractFunctionSelector(hex"aabb");

        // 3 bytes
        vm.expectRevert();
        harness.extractFunctionSelector(hex"aabbcc");
    }

    /// @dev Test case: Random calldata (>= 4 bytes) should always extract the correct first 4 bytes as the selector.
    ///      [TXUT-PARSE-4]
    function testFuzz_TXUT_PARSE_4_B__FCIU_SELECT_18_extractFunctionSelector_randomCalldata_extractsFirst4Bytes(
        bytes calldata data
    )
        public
        view
    {
        // Setup: constrain fuzz calldata to the minimum valid selector length.
        vm.assume(data.length >= 4);

        // Call: extract the selector from the fuzz calldata.
        bytes4 selector = harness.extractFunctionSelector(data);

        // The expected selector is just the first 4 bytes of the data
        bytes4 expected = bytes4(data[:4]);

        // Verify: extraction should match the first four calldata bytes exactly.
        assertEq(selector, expected, "Should always extract the first 4 bytes as the selector");
    }

    /// @dev Verifies `ContractInteractionUtils.extractFunctionSelector` always reverts for calldata shorter than four
    /// bytes.
    /// @param data Fuzzed calldata constrained below the minimum selector length.
    function testFuzz_FCIU_SELECT_19_extractFunctionSelector_shortCalldataAlwaysReverts(bytes calldata data) public {
        // Setup: constrain fuzz calldata below the minimum selector length.
        vm.assume(data.length < 4);

        // Call: extract the selector, expecting the short-calldata path to revert.
        vm.expectRevert();
        harness.extractFunctionSelector(data);

        // Verify: the revert expectation above proves short calldata never returns padded garbage.
    }
}
