// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TokenTransferUtils} from "libraries/TokenTransferUtils.sol";

/**
 * @dev TokenTransferUtilsHarness
 *      Test harness that exposes all internal TokenTransferUtils library functions
 *      via public wrappers. Because the library functions use `calldata` parameters,
 *      all harness functions must be `external` to receive calldata from the test.
 */
contract TokenTransferUtilsHarness {
    /// @dev Exposes token-transfer classification for direct testing.
    /// @param data Calldata associated with the transaction.
    /// @param value Native-token value attached to the transaction.
    /// @return isTokenTransfer True when the transaction is classified as a token transfer.
    function isTransactionTokenTransfer(bytes calldata data, uint256 value) external pure returns (bool) {
        return TokenTransferUtils.isTransactionTokenTransfer(data, value);
    }

    /// @dev Exposes native-transfer classification for direct testing.
    /// @param data Calldata associated with the transaction.
    /// @param value Native-token value attached to the transaction.
    /// @return isNativeTransfer True when the transaction is classified as a native transfer.
    function isTransactionNativeTokenTransfer(bytes calldata data, uint256 value) external pure returns (bool) {
        return TokenTransferUtils.isTransactionNativeTokenTransfer(data, value);
    }

    // forge-lint: disable-next-line(mixed-case-function)
    /// @dev Exposes ERC-20 transfer classification for direct testing.
    /// @param data Calldata associated with the transaction.
    /// @param value Native-token value attached to the transaction.
    /// @return isErc20Transfer True when the transaction is classified as an ERC-20 transfer.
    function isTransactionERC20TokenTransfer(bytes calldata data, uint256 value) external pure returns (bool) {
        return TokenTransferUtils.isTransactionERC20TokenTransfer(data, value);
    }

    // forge-lint: disable-next-line(mixed-case-function)
    /// @dev Exposes ERC-20 transfer recipient extraction for direct testing.
    /// @param data ERC-20 calldata expected to encode `transfer(address,uint256)`.
    /// @return recipient Extracted transfer recipient.
    function extractERC20TransferRecipient(bytes calldata data) external pure returns (address) {
        return TokenTransferUtils.extractERC20TransferRecipient(data);
    }

    /// @dev Exposes token-address extraction for direct testing.
    /// @param to Transaction target address.
    /// @param data Transaction calldata.
    /// @return tokenAddress Extracted token address or `address(0)` for native transfers.
    function extractTokenAddress(address to, bytes calldata data) external pure returns (address) {
        return TokenTransferUtils.extractTokenAddress(to, data);
    }

    /// @dev Exposes transfer-amount extraction for direct testing.
    /// @param data Transaction calldata.
    /// @param value Native-token value attached to the transaction.
    /// @return amount Extracted transfer amount.
    function extractTransferAmount(bytes calldata data, uint256 value) external pure returns (uint256) {
        return TokenTransferUtils.extractTransferAmount(data, value);
    }
}

/**
 * @dev TokenTransferUtilsTest
 *      Comprehensive tests for TokenTransferUtils library covering transfer
 *         detection and extraction for both native ETH and ERC-20 token transfers.
 *      Test coverage spans:
 *      - Detection tests (isTransactionTokenTransfer, isTransactionNativeTokenTransfer,
 *        isTransactionERC20TokenTransfer)
 *      - Extraction tests (extractERC20TransferRecipient, extractTokenAddress,
 *        extractTransferAmount)
 *      - Fuzz tests
 * @author Den Technologies Inc
 */
contract TokenTransferUtilsTest is Test {
    TokenTransferUtilsHarness public harness;

    /// @dev Well-known ERC-20 transfer(address,uint256) selector = 0xa9059cbb
    bytes4 constant TRANSFER_SELECTOR = IERC20.transfer.selector;

    /// @dev ERC-20 approve(address,uint256) selector = 0x095ea7b3
    bytes4 constant APPROVE_SELECTOR = IERC20.approve.selector;

    /// @dev ERC-20 transferFrom(address,address,uint256) selector = 0x23b872dd
    bytes4 constant TRANSFER_FROM_SELECTOR = IERC20.transferFrom.selector;

    /// @dev A sample recipient address used across tests
    address constant RECIPIENT = address(0xBEEF);

    /// @dev A sample token contract address used across tests
    address constant TOKEN_ADDRESS = address(0xCAFE);

    /// @dev A sample transfer amount
    uint256 constant AMOUNT = 1 ether;

    /// @dev Deploys the harness exposing the token-transfer helper functions.
    /// @dev Deploys the harness exposing the token-transfer classification and parsing helpers.
    function setUp() public {
        harness = new TokenTransferUtilsHarness();
    }

    /**
     * @dev Encodes a valid ERC-20 transfer(address,uint256) calldata.
     *      Returns: selector (4) | to address padded to 32 bytes | amount (32) = 68 bytes total.
     */
    function _encodeTransferCalldata(address to, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(TRANSFER_SELECTOR, to, amount);
    }

    /**
     * @dev Encodes a valid ERC-20 approve(address,uint256) calldata.
     */
    function _encodeApproveCalldata(address spender, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(APPROVE_SELECTOR, spender, amount);
    }

    /**
     * @dev Encodes a valid ERC-20 transferFrom(address,address,uint256) calldata.
     */
    function _encodeTransferFromCalldata(address from, address to, uint256 amount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(TRANSFER_FROM_SELECTOR, from, to, amount);
    }

    /// @dev Test case: A native transfer (empty data, value > 0) should be detected as a token transfer.
    function test_isTransactionTokenTransfer_nativeTransfer_returnsTrue() public view {
        bytes memory emptyData = new bytes(0);

        bool result = harness.isTransactionTokenTransfer(emptyData, 1 ether);

        assertTrue(result, "Native transfer (empty data, value>0) should be detected");
    }

    /// @dev Test case: An ERC-20 transfer (correct selector, value = 0) should be detected as a token transfer.
    function test_isTransactionTokenTransfer_erc20Transfer_returnsTrue() public view {
        bytes memory data = _encodeTransferCalldata(RECIPIENT, AMOUNT);

        bool result = harness.isTransactionTokenTransfer(data, 0);

        assertTrue(result, "ERC-20 transfer should be detected");
    }

    /// @dev Test case: A contract interaction with a non-transfer selector should not be detected as a token transfer.
    function test_isTransactionTokenTransfer_nonTransferSelector_returnsFalse() public view {
        bytes memory data = _encodeApproveCalldata(RECIPIENT, AMOUNT);

        bool result = harness.isTransactionTokenTransfer(data, 0);

        assertFalse(result, "Non-transfer selector should not be detected as token transfer");
    }

    /// @dev Test case: A transaction with no data and no value should not be detected as a token transfer.
    function test_isTransactionTokenTransfer_noDataNoValue_returnsFalse() public view {
        bytes memory emptyData = new bytes(0);

        bool result = harness.isTransactionTokenTransfer(emptyData, 0);

        assertFalse(result, "Empty data with zero value should not be a token transfer");
    }

    /// @dev Test case: An ERC-20 selector combined with value > 0 should not be detected as a token transfer,
    ///      because isTransactionNativeTokenTransfer checks data.length == 0 (false here) and
    ///      isTransactionERC20TokenTransfer rejects value > 0.
    function test_isTransactionTokenTransfer_erc20SelectorWithValue_returnsFalse() public view {
        bytes memory data = _encodeTransferCalldata(RECIPIENT, AMOUNT);

        bool result = harness.isTransactionTokenTransfer(data, 1 ether);

        assertFalse(result, "ERC-20 selector with value > 0 should not be detected as token transfer");
    }

    /// @dev Test case: Data with exactly 4 bytes (transfer selector only, no params) should not be detected as a
    ///      token transfer because calldata is missing required ABI-encoded arguments.
    function test_isTransactionTokenTransfer_selectorOnly_returnsFalse() public view {
        bytes memory data = abi.encodePacked(TRANSFER_SELECTOR);
        assertEq(data.length, 4, "Data should be exactly 4 bytes");

        bool result = harness.isTransactionTokenTransfer(data, 0);

        assertFalse(result, "Selector-only calldata should not be detected as token transfer");
    }

    /// @dev Test case: Empty data with value > 0 should be detected as a native token transfer.
    function test_isTransactionNativeTokenTransfer_emptyDataValueGt0_returnsTrue() public view {
        bytes memory emptyData = new bytes(0);

        bool result = harness.isTransactionNativeTokenTransfer(emptyData, 1 ether);

        assertTrue(result, "Empty data with value > 0 should be native transfer");
    }

    /// @dev Test case: Empty data with value = 0 should not be detected as a native token transfer.
    function test_isTransactionNativeTokenTransfer_emptyDataValueZero_returnsFalse() public view {
        bytes memory emptyData = new bytes(0);

        bool result = harness.isTransactionNativeTokenTransfer(emptyData, 0);

        assertFalse(result, "Empty data with value = 0 should NOT be native transfer");
    }

    /// @dev Test case: Non-empty data with value > 0 should not be detected as a native token transfer.
    function test_isTransactionNativeTokenTransfer_nonEmptyDataWithValue_returnsFalse() public view {
        bytes memory data = hex"deadbeef";

        bool result = harness.isTransactionNativeTokenTransfer(data, 1 ether);

        assertFalse(result, "Non-empty data should NOT be native transfer even with value > 0");
    }

    /// @dev Test case: Non-empty data with value = 0 should not be detected as a native token transfer.
    function test_isTransactionNativeTokenTransfer_nonEmptyDataValueZero_returnsFalse() public view {
        bytes memory data = hex"deadbeef";

        bool result = harness.isTransactionNativeTokenTransfer(data, 0);

        assertFalse(result, "Non-empty data with value = 0 should NOT be native transfer");
    }

    /// @dev Test case: A transfer(address,uint256) selector with value = 0 should be detected as an ERC-20 token
    ///      transfer.
    function test_isTransactionERC20TokenTransfer_transferSelectorValueZero_returnsTrue() public view {
        bytes memory data = _encodeTransferCalldata(RECIPIENT, AMOUNT);

        bool result = harness.isTransactionERC20TokenTransfer(data, 0);

        assertTrue(result, "transfer selector with value=0 should be ERC-20 transfer");
    }

    /// @dev Test case: A transfer selector with value > 0 should not be detected as an ERC-20 token transfer.
    function test_isTransactionERC20TokenTransfer_transferSelectorValueGt0_returnsFalse() public view {
        bytes memory data = _encodeTransferCalldata(RECIPIENT, AMOUNT);

        bool result = harness.isTransactionERC20TokenTransfer(data, 1 ether);

        assertFalse(result, "transfer selector with value > 0 should NOT be ERC-20 transfer");
    }

    /// @dev Test case: An approve(address,uint256) selector should not be detected as an ERC-20 token transfer.
    function test_isTransactionERC20TokenTransfer_approveSelector_returnsFalse() public view {
        bytes memory data = _encodeApproveCalldata(RECIPIENT, AMOUNT);

        bool result = harness.isTransactionERC20TokenTransfer(data, 0);

        assertFalse(result, "approve selector should NOT be detected as ERC-20 transfer");
    }

    /// @dev Test case: A transferFrom selector should not be detected as an ERC-20 token transfer.
    function test_isTransactionERC20TokenTransfer_transferFromSelector_returnsFalse() public view {
        bytes memory data = _encodeTransferFromCalldata(address(0x1), RECIPIENT, AMOUNT);

        bool result = harness.isTransactionERC20TokenTransfer(data, 0);

        assertFalse(result, "transferFrom selector should NOT be detected as ERC-20 transfer");
    }

    /// @dev Test case: Data shorter than 4 bytes should not be detected as an ERC-20 token transfer.
    function test_isTransactionERC20TokenTransfer_dataTooShort_returnsFalse() public view {
        bytes memory shortData = hex"a905"; // Only 2 bytes

        bool result = harness.isTransactionERC20TokenTransfer(shortData, 0);

        assertFalse(result, "Data shorter than 4 bytes should return false");
    }

    /// @dev Test case: Any random non-transfer selector with value = 0 should not be detected as an ERC-20 token
    ///      transfer.
    function testFuzz_isTransactionERC20TokenTransfer_randomNonTransferSelector_returnsFalse(bytes4 selector)
        public
        view
    {
        vm.assume(selector != TRANSFER_SELECTOR);

        bytes memory data = abi.encodePacked(selector, bytes32(uint256(uint160(RECIPIENT))), bytes32(AMOUNT));

        bool result = harness.isTransactionERC20TokenTransfer(data, 0);

        assertFalse(result, "Non-transfer selector with value=0 should NOT be detected as ERC-20 transfer");
    }

    /// @dev Test case: Valid ERC-20 transfer calldata should extract the correct recipient address.
    function test_extractERC20TransferRecipient_validCalldata_extractsCorrectRecipient() public view {
        bytes memory data = _encodeTransferCalldata(RECIPIENT, AMOUNT);

        address recipient = harness.extractERC20TransferRecipient(data);

        assertEq(recipient, RECIPIENT, "Should extract the correct recipient");
    }

    /// @dev Test case: Data too short to contain a recipient should revert with MalformedTokenTransfer.
    function test_extractERC20TransferRecipient_dataTooShort_reverts() public {
        bytes memory shortData = hex"a9059cbb0000000000000000000000000000000000000000"; // 24 bytes (< 36)

        vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
        harness.extractERC20TransferRecipient(shortData);
    }

    /// @dev Test case: Extracting a recipient of address(0) should succeed without validation.
    function test_extractERC20TransferRecipient_addressZero_extractsCorrectly() public view {
        bytes memory data = _encodeTransferCalldata(address(0), AMOUNT);

        address recipient = harness.extractERC20TransferRecipient(data);

        assertEq(recipient, address(0), "Should extract address(0) without validation");
    }

    /// @dev Test case: Data with length 35 (one byte short of the minimum 36) should revert with
    ///  MalformedTokenTransfer.
    function test_extractERC20TransferRecipient_length35_reverts() public {
        // Build 35 bytes: transfer selector (4) + 31 bytes of address padding
        bytes memory data = new bytes(35);
        data[0] = TRANSFER_SELECTOR[0];
        data[1] = TRANSFER_SELECTOR[1];
        data[2] = TRANSFER_SELECTOR[2];
        data[3] = TRANSFER_SELECTOR[3];

        vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
        harness.extractERC20TransferRecipient(data);
    }

    /// @dev Test case: Data with length 36 (exact minimum: selector + address, no amount word) should successfully
    ///      extract the recipient.
    function test_extractERC20TransferRecipient_length36_succeeds() public view {
        // Build exactly 36 bytes: selector(4) + zero-padded address(32)
        bytes memory data = abi.encodePacked(TRANSFER_SELECTOR, bytes12(0), bytes20(RECIPIENT));
        assertEq(data.length, 36, "Data should be exactly 36 bytes");

        address recipient = harness.extractERC20TransferRecipient(data);

        assertEq(recipient, RECIPIENT, "Should extract recipient from 36-byte data");
    }

    /// @dev Test case: A non-transfer selector (approve) with valid-length data should revert with
    ///      MalformedTokenTransfer.
    function test_extractERC20TransferRecipient_approveSelector_reverts() public {
        bytes memory data = _encodeApproveCalldata(RECIPIENT, AMOUNT);

        vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
        harness.extractERC20TransferRecipient(data);
    }

    /// @dev Test case: A non-transfer selector (transferFrom) with valid-length data should revert with
    ///      MalformedTokenTransfer.
    function test_extractERC20TransferRecipient_transferFromSelector_reverts() public {
        bytes memory data = _encodeTransferFromCalldata(address(0x1), RECIPIENT, AMOUNT);

        vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
        harness.extractERC20TransferRecipient(data);
    }

    /// @dev Test case: Dirty upper bytes in the address word (data[4:16] non-zero) should be ignored because the
    ///      library reads data[16:36] only.
    function test_extractERC20TransferRecipient_dirtyUpperBytes_ignoresUpperBytes() public view {
        // Build calldata with dirty upper bytes in the address word
        // Standard ABI encoding: selector(4) | 12 zero bytes | 20 address bytes | 32 amount bytes
        // We'll make the 12 "zero" bytes non-zero
        bytes memory data = abi.encodePacked(
            TRANSFER_SELECTOR,
            bytes12(0xFFFFFFFFFFFFFFFFFFFFFFFF), // dirty upper 12 bytes
            bytes20(RECIPIENT),
            bytes32(uint256(AMOUNT))
        );

        address recipient = harness.extractERC20TransferRecipient(data);

        assertEq(recipient, RECIPIENT, "Should extract data[16:36] only, ignoring dirty upper bytes");
    }

    /// @dev Test case: Extra trailing data beyond 68 bytes should not affect recipient extraction.
    function test_extractERC20TransferRecipient_extraTrailingData_extractsCorrectly() public view {
        bytes memory standardData = _encodeTransferCalldata(RECIPIENT, AMOUNT);
        bytes memory extraData = abi.encodePacked(standardData, hex"deadbeefcafebabe1234567890");

        address recipient = harness.extractERC20TransferRecipient(extraData);

        assertEq(recipient, RECIPIENT, "Extra trailing data should not affect extraction");
    }

    /// @dev Test case: Data with only the selector (4 bytes, no parameters) should revert with MalformedTokenTransfer.
    function test_extractERC20TransferRecipient_selectorOnly_reverts() public {
        bytes memory data = abi.encodePacked(TRANSFER_SELECTOR);
        assertEq(data.length, 4, "Data should be exactly 4 bytes");

        vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
        harness.extractERC20TransferRecipient(data);
    }

    /// @dev Test case: Random non-transfer selectors with valid-length data should always revert with
    ///      MalformedTokenTransfer.
    function testFuzz_extractERC20TransferRecipient_randomNonTransferSelector_reverts(bytes4 selector) public {
        // Exclude the actual transfer selector
        vm.assume(selector != TRANSFER_SELECTOR);

        // Build 68-byte data with the random selector
        bytes memory data = abi.encodePacked(selector, bytes32(uint256(uint160(RECIPIENT))), bytes32(AMOUNT));

        vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
        harness.extractERC20TransferRecipient(data);
    }

    /// @dev Test case: A native transfer (empty data) should return address(0) as the token address.
    function test_extractTokenAddress_nativeTransfer_returnsAddressZero() public view {
        bytes memory emptyData = new bytes(0);

        address tokenAddr = harness.extractTokenAddress(TOKEN_ADDRESS, emptyData);

        assertEq(tokenAddr, address(0), "Native transfer should return address(0)");
    }

    /// @dev Test case: An ERC-20 transfer (non-empty data) should return the `to` parameter as the token contract
    ///      address.
    function test_extractTokenAddress_erc20Transfer_returnsTo() public view {
        bytes memory data = _encodeTransferCalldata(RECIPIENT, AMOUNT);

        address tokenAddr = harness.extractTokenAddress(TOKEN_ADDRESS, data);

        assertEq(tokenAddr, TOKEN_ADDRESS, "ERC-20 transfer should return the `to` address");
    }

    /// @dev Test case: Data of 1 byte (non-empty but minimal) should return the `to` address regardless of content.
    function test_extractTokenAddress_singleByteData_returnsTo() public view {
        bytes memory data = hex"ab";

        address tokenAddr = harness.extractTokenAddress(TOKEN_ADDRESS, data);

        assertEq(tokenAddr, TOKEN_ADDRESS, "Any non-empty data should return `to`");
    }

    /// @dev Test case: When to == address(0) with non-empty data, extractTokenAddress should return address(0),
    ///      which is indistinguishable from a native transfer.
    function test_extractTokenAddress_toZeroDataNonEmpty_returnsZero() public view {
        bytes memory data = _encodeTransferCalldata(RECIPIENT, AMOUNT);

        address tokenAddr = harness.extractTokenAddress(address(0), data);

        assertEq(tokenAddr, address(0), "to=address(0) with non-empty data returns address(0)");
    }

    /// @dev Test case: When to == address(0) with empty data, extractTokenAddress should return address(0) via the
    ///      native path.
    function test_extractTokenAddress_toZeroDataEmpty_returnsZeroViaNativePath() public view {
        bytes memory emptyData = new bytes(0);

        address tokenAddr = harness.extractTokenAddress(address(0), emptyData);

        assertEq(tokenAddr, address(0), "to=address(0) with empty data returns address(0) via native path");
    }

    /// @dev Test case: Any random `to` address with random non-empty data should always return `to` as the token
    ///      address.
    function testFuzz_extractTokenAddress_randomToNonEmptyData_alwaysReturnsTo(address to, bytes calldata data)
        public
        view
    {
        vm.assume(data.length > 0);

        address tokenAddr = harness.extractTokenAddress(to, data);

        assertEq(tokenAddr, to, "Non-empty data should always return `to`");
    }

    /// @dev Test case: Any random `to` address with empty data should always return address(0).
    function testFuzz_extractTokenAddress_randomToEmptyData_alwaysReturnsZero(address to) public view {
        bytes memory emptyData = new bytes(0);

        address tokenAddr = harness.extractTokenAddress(to, emptyData);

        assertEq(tokenAddr, address(0), "Empty data should always return address(0) regardless of `to`");
    }

    /// @dev Test case: A native transfer (empty data) should return the `value` parameter as the transfer amount.
    function test_extractTransferAmount_nativeTransfer_returnsValue() public view {
        bytes memory emptyData = new bytes(0);

        uint256 amount = harness.extractTransferAmount(emptyData, 1 ether);

        assertEq(amount, 1 ether, "Native transfer should return the msg.value");
    }

    /// @dev Test case: An ERC-20 transfer should extract the amount from calldata bytes.
    function test_extractTransferAmount_erc20Transfer_extractsFromCalldata() public view {
        bytes memory data = _encodeTransferCalldata(RECIPIENT, 42 ether);

        uint256 amount = harness.extractTransferAmount(data, 0);

        assertEq(amount, 42 ether, "Should extract amount from ERC-20 calldata");
    }

    /// @dev Test case: Extracting a transfer amount of 0 should return 0.
    function test_extractTransferAmount_amountZero_returnsZero() public view {
        bytes memory data = _encodeTransferCalldata(RECIPIENT, 0);

        uint256 amount = harness.extractTransferAmount(data, 0);

        assertEq(amount, 0, "Should return 0 for zero amount");
    }

    /// @dev Test case: Extracting a transfer amount of type(uint256).max should return the maximum value.
    function test_extractTransferAmount_amountMax_returnsMax() public view {
        bytes memory data = _encodeTransferCalldata(RECIPIENT, type(uint256).max);

        uint256 amount = harness.extractTransferAmount(data, 0);

        assertEq(amount, type(uint256).max, "Should return type(uint256).max");
    }

    /// @dev Test case: Data too short to contain an amount should revert with MalformedTokenTransfer.
    function test_extractTransferAmount_dataTooShort_reverts() public {
        // 60 bytes (less than required 68)
        bytes memory shortData = new bytes(60);
        shortData[0] = bytes1(uint8(0xa9)); // Partial transfer selector

        vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
        harness.extractTransferAmount(shortData, 0);
    }

    /// @dev Test case: Data with length 67 (one byte short of the minimum 68) should revert with
    ///  MalformedTokenTransfer.
    function test_extractTransferAmount_length67_reverts() public {
        bytes memory data = new bytes(67);

        vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
        harness.extractTransferAmount(data, 0);
    }

    /// @dev Test case: Data with length 68 (exact minimum: selector + address + amount) should successfully extract
    ///      the amount.
    function test_extractTransferAmount_length68_succeeds() public view {
        bytes memory data = _encodeTransferCalldata(RECIPIENT, 123);
        assertEq(data.length, 68, "Standard transfer calldata should be 68 bytes");

        uint256 amount = harness.extractTransferAmount(data, 0);

        assertEq(amount, 123, "Should extract amount from exact-minimum-length data");
    }

    /// @dev Test case: Data longer than 68 bytes (with trailing data) should extract the amount from data[36:68] only.
    function test_extractTransferAmount_trailingData_extractsCorrectly() public view {
        bytes memory standardData = _encodeTransferCalldata(RECIPIENT, 999);
        bytes memory extraData = abi.encodePacked(standardData, hex"deadbeef1234567890abcdef");

        uint256 amount = harness.extractTransferAmount(extraData, 0);

        assertEq(amount, 999, "Should extract amount from data[36:68] ignoring trailing bytes");
    }

    /// @dev Test case: Data with length in [1, 3] (partial selector, not empty) should revert with
    ///      MalformedTokenTransfer.
    function test_extractTransferAmount_partialSelector_reverts() public {
        for (uint256 len = 1; len <= 3; len++) {
            bytes memory data = new bytes(len);

            vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
            harness.extractTransferAmount(data, 0);
        }
    }

    /// @dev Test case: Data with only the selector (4 bytes, no params) should revert with MalformedTokenTransfer.
    function test_extractTransferAmount_selectorOnly_reverts() public {
        bytes memory data = abi.encodePacked(TRANSFER_SELECTOR);

        vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
        harness.extractTransferAmount(data, 0);
    }

    /// @dev Test case: Data with length 36 (selector + address, no amount word) should revert with
    ///      MalformedTokenTransfer.
    function test_extractTransferAmount_noAmountWord_reverts() public {
        bytes memory data = abi.encodePacked(TRANSFER_SELECTOR, bytes32(uint256(uint160(RECIPIENT))));
        assertEq(data.length, 36, "Data should be 36 bytes");

        vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
        harness.extractTransferAmount(data, 0);
    }

    /// @dev Test case: A native transfer (empty data) with value = 0 should return 0 without validation.
    function test_extractTransferAmount_nativeTransferValueZero_returnsZero() public view {
        bytes memory emptyData = new bytes(0);

        uint256 amount = harness.extractTransferAmount(emptyData, 0);

        assertEq(amount, 0, "Native transfer with value=0 should return 0");
    }

    /// @dev Test case: Any random uint256 amount in valid 68-byte calldata should always be extracted correctly.
    function testFuzz_extractTransferAmount_randomAmount_extractsCorrectly(uint256 expectedAmount) public view {
        bytes memory data = _encodeTransferCalldata(RECIPIENT, expectedAmount);

        uint256 amount = harness.extractTransferAmount(data, 0);

        assertEq(amount, expectedAmount, "Should always extract the correct amount");
    }

    /// @dev Test case: Any random data length in [1, 67] should always revert with MalformedTokenTransfer.
    function testFuzz_extractTransferAmount_shortDataLength_alwaysReverts(uint8 rawLength) public {
        uint256 dataLength = bound(rawLength, 1, 67);

        bytes memory data = new bytes(dataLength);

        vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
        harness.extractTransferAmount(data, 0);
    }

    /// @dev Verifies `TokenTransferUtils.extractERC20TransferRecipient` always returns the encoded recipient for valid
    /// transfer calldata.
    /// @param to Fuzzed recipient encoded into the transfer calldata.
    function testFuzz_extractERC20TransferRecipient_validCalldata_correctRecipient(address to)
        public
        view
    {
        // Setup: encode a valid ERC-20 transfer for the fuzzed recipient.
        bytes memory data = _encodeTransferCalldata(to, AMOUNT);

        // Call: extract the recipient from the encoded transfer calldata.
        address recipient = harness.extractERC20TransferRecipient(data);

        // Verify: the decoded recipient should match the fuzzed transfer target exactly.
        assertEq(recipient, to, "Should extract the correct recipient for any address");
    }

    /// @dev Verifies `TokenTransferUtils.extractTransferAmount` returns the encoded ERC-20 amount for valid transfer
    /// calldata.
    /// @param to Fuzzed recipient encoded into the transfer calldata.
    /// @param expectedAmount Fuzzed amount encoded into the transfer calldata.
    function testFuzz_extractTransferAmount_validCalldata_correctAmount(
        address to,
        uint256 expectedAmount
    ) public view {
        // Setup: encode a valid ERC-20 transfer for the fuzzed amount.
        bytes memory data = _encodeTransferCalldata(to, expectedAmount);

        // Call: extract the amount from the encoded transfer calldata.
        uint256 amount = harness.extractTransferAmount(data, 0);

        // Verify: the ERC-20 path should return the encoded amount exactly.
        assertEq(amount, expectedAmount, "Should extract the correct amount");
    }

    /// @dev Verifies `TokenTransferUtils.isTransactionTokenTransfer` never classifies one transaction as both native
    /// and ERC-20.
    /// @param data Fuzzed calldata paired with the transaction.
    /// @param value Fuzzed native-token value paired with the transaction.
    function testFuzz_isTransactionTokenTransfer_neverBothNativeAndERC20(
        bytes calldata data,
        uint256 value
    ) public view {
        // Setup: evaluate both classification paths for the same fuzzed transaction shape.
        bool isNative = harness.isTransactionNativeTokenTransfer(data, value);
        bool isERC20 = harness.isTransactionERC20TokenTransfer(data, value);

        // Verify: native and ERC-20 transfer classifications must stay mutually exclusive.
        assertFalse(isNative && isERC20, "A transaction cannot be both native and ERC-20 transfer");
    }

    /// @dev Verifies `TokenTransferUtils.isTransactionERC20TokenTransfer` accepts only the exact transfer selector
    /// with zero native value.
    /// @param selector Fuzzed selector encoded into otherwise valid ERC-20-shaped calldata.
    /// @param value Fuzzed native-token value paired with the calldata.
    /// @param to Fuzzed recipient encoded into the calldata payload.
    /// @param amount Fuzzed transfer amount encoded into the calldata payload.
    function testFuzz_isTransactionERC20TokenTransfer_onlyExactTransferSelectorWithZeroValue(
        bytes4 selector,
        uint256 value,
        address to,
        uint256 amount
    ) public view {
        // Setup: build a fixed-length ERC-20-shaped calldata blob using the fuzzed selector and arguments.
        bytes memory data = abi.encodeWithSelector(selector, to, amount);

        // Call: classify the fuzzed transaction shape as an ERC-20 transfer or not.
        bool isTransfer = harness.isTransactionERC20TokenTransfer(data, value);

        // Verify: only the exact `transfer(address,uint256)` selector paired with zero native value is accepted.
        assertEq(
            isTransfer,
            selector == TRANSFER_SELECTOR && value == 0,
            "classification should accept only the exact transfer selector with zero value"
        );
    }

    /// @dev Verifies `TokenTransferUtils.extractERC20TransferRecipient` always reverts for malformed short calldata
    /// lengths.
    /// @param rawLength Fuzzed length constrained below the valid 68-byte ERC-20 transfer encoding.
    function testFuzz_extractERC20TransferRecipient_shortCalldataAlwaysReverts(uint8 rawLength) public {
        // Setup: constrain the calldata length below the valid ERC-20 transfer payload size.
        uint256 dataLength = bound(rawLength, 0, 67);
        bytes memory data = new bytes(dataLength);

        // Call: extract the recipient, expecting `MalformedTokenTransfer` for every short payload.
        vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
        harness.extractERC20TransferRecipient(data);

        // Verify: the revert expectation above proves malformed short payloads never decode successfully.
    }

    /// @dev Verifies `TokenTransferUtils.extractTransferAmount` always reverts for malformed short calldata lengths.
    /// @param rawLength Fuzzed length constrained below the valid 68-byte ERC-20 transfer encoding.
    function testFuzz_extractTransferAmount_shortCalldataAlwaysReverts(uint8 rawLength) public {
        // Setup: constrain the calldata length to malformed non-empty ERC-20-shaped payloads.
        uint256 dataLength = bound(rawLength, 1, 67);
        bytes memory data = new bytes(dataLength);

        // Call: extract the amount, expecting `MalformedTokenTransfer` for every short payload.
        vm.expectRevert(TokenTransferUtils.MalformedTokenTransfer.selector);
        harness.extractTransferAmount(data, 0);

        // Verify: the revert expectation above proves malformed short payloads never decode successfully.
    }
}
