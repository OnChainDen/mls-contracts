// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {ISafeExecutorModule} from "../../src/interfaces/ISafeExecutorModule.sol";
import {SafeExecutorModule} from "../../src/safe-module/SafeExecutorModule.sol";

/**
 * @title MockSafe
 * @notice A mock Safe contract for testing the SafeExecutorModule
 * @dev Implements only the execTransactionFromModule function needed for testing.
 *      Tracks calls for verification and allows configuring success/failure responses.
 */
contract MockSafe {
    /// @notice Tracks the last call made via execTransactionFromModule
    address public lastCallTo;
    uint256 public lastCallValue;
    bytes public lastCallData;
    uint8 public lastCallOperation;
    uint256 public callCount;

    /// @notice Controls whether execTransactionFromModule returns success or failure
    bool public shouldSucceed = true;

    /// @notice Storage slot for testing state changes
    uint256 public storageValue;

    /// @notice Simulates Safe's execTransactionFromModule
    /// @param to Target address
    /// @param value ETH value (should always be 0 for our module)
    /// @param data Calldata
    /// @param operation 0 = Call, 1 = DelegateCall (should always be 0 for our module)
    /// @return success Whether the execution succeeded
    function execTransactionFromModule(address to, uint256 value, bytes memory data, uint8 operation)
        external
        returns (bool success)
    {
        // Track the call
        lastCallTo = to;
        lastCallValue = value;
        lastCallData = data;
        lastCallOperation = operation;
        callCount++;

        if (!shouldSucceed) {
            return false;
        }

        // Actually execute the call (for integration tests)
        (success,) = to.call(data);
        return success;
    }

    /// @notice Configure mock to return failure
    function setFailMode(bool fail) external {
        shouldSucceed = !fail;
    }

    /// @notice Reset call tracking
    function resetCalls() external {
        lastCallTo = address(0);
        lastCallValue = 0;
        lastCallData = "";
        lastCallOperation = 0;
        callCount = 0;
    }

    /// @notice Function that can be called to test blocking calls to Safe
    function addOwnerWithThreshold(address, uint256) external pure {
        // This should never be callable via the module
    }

    /// @notice Function that can be called to test blocking calls to Safe
    function enableModule(address) external pure {
        // This should never be callable via the module
    }
}

/**
 * @title MockTarget
 * @notice A mock target contract for testing module execution
 */
contract MockTarget {
    uint256 public value;
    address public lastCaller;

    event ValueSet(uint256 newValue, address caller);

    function setValue(uint256 newValue) external {
        value = newValue;
        lastCaller = msg.sender;
        emit ValueSet(newValue, msg.sender);
    }

    function revertingFunction() external pure {
        revert("MockTarget: intentional revert");
    }

    function getValuePlusOne() external view returns (uint256) {
        return value + 1;
    }
}

/**
 * @title SafeExecutorModuleTest
 * @notice Comprehensive tests for the SafeExecutorModule contract
 * @dev Tests cover:
 *      - Constructor validation and initialization
 *      - Authorization checks
 *      - Target address restrictions (Safe, module)
 *      - Execution success and failure handling
 *      - Integration with mock Safe contract
 *
 * @author Den Technologies Inc
 */
contract SafeExecutorModuleTest is Test {
    MockSafe public mockSafe;
    MockTarget public mockTarget;
    SafeExecutorModule public module;

    address public authorizedExecutor;
    address public unauthorizedUser;

    /// @dev Set up test environment before each test
    function setUp() public {
        // Create test addresses
        authorizedExecutor = makeAddr("authorizedExecutor");
        unauthorizedUser = makeAddr("unauthorizedUser");

        // Deploy mock contracts
        mockSafe = new MockSafe();
        mockTarget = new MockTarget();

        // Deploy the module
        module = new SafeExecutorModule(address(mockSafe), authorizedExecutor);
    }

    // ============================================================
    // Constructor Tests
    // ============================================================

    function test_constructor_setsImmutables() public view {
        assertEq(module.SAFE(), address(mockSafe), "Safe address should be set correctly");
        assertEq(module.AUTHORIZED_EXECUTOR(), authorizedExecutor, "Executor address should be set correctly");
    }

    function test_constructor_revertsOnZeroSafe() public {
        vm.expectRevert(ISafeExecutorModule.SafeAddressCannotBeZero.selector);
        new SafeExecutorModule(address(0), authorizedExecutor);
    }

    function test_constructor_revertsOnZeroExecutor() public {
        vm.expectRevert(ISafeExecutorModule.ExecutorAddressCannotBeZero.selector);
        new SafeExecutorModule(address(mockSafe), address(0));
    }

    function test_constructor_revertsOnBothZero() public {
        vm.expectRevert(ISafeExecutorModule.SafeAddressCannotBeZero.selector);
        new SafeExecutorModule(address(0), address(0));
    }

    // ============================================================
    // Authorization Tests
    // ============================================================

    function test_executeOnBehalf_revertsUnauthorizedCaller() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISafeExecutorModule.UnauthorizedCaller.selector, unauthorizedUser, authorizedExecutor
            )
        );
        module.executeOnBehalf(address(mockTarget), data);
    }

    function test_executeOnBehalf_onlyAuthorizedExecutorCanCall() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Unauthorized user should fail
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        module.executeOnBehalf(address(mockTarget), data);

        // Authorized executor should succeed
        vm.prank(authorizedExecutor);
        bool success = module.executeOnBehalf(address(mockTarget), data);
        assertTrue(success, "Authorized executor should succeed");
    }

    // ============================================================
    // Target Address Restriction Tests
    // ============================================================

    function test_executeOnBehalf_revertsCallToSafe() public {
        // Try to call the Safe itself (e.g., addOwnerWithThreshold)
        bytes memory data = abi.encodeWithSelector(MockSafe.addOwnerWithThreshold.selector, makeAddr("newOwner"), 2);

        vm.prank(authorizedExecutor);
        vm.expectRevert(abi.encodeWithSelector(ISafeExecutorModule.CannotCallSafe.selector, address(mockSafe)));
        module.executeOnBehalf(address(mockSafe), data);
    }

    function test_executeOnBehalf_revertsCallToModule() public {
        // Try to call the module itself
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(authorizedExecutor);
        vm.expectRevert(abi.encodeWithSelector(ISafeExecutorModule.CannotCallModule.selector, address(module)));
        module.executeOnBehalf(address(module), data);
    }

    function test_executeOnBehalf_canCallOtherContracts() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(authorizedExecutor);
        bool success = module.executeOnBehalf(address(mockTarget), data);

        assertTrue(success, "Should be able to call other contracts");
        assertEq(mockSafe.callCount(), 1, "Safe should have received one call");
        assertEq(mockSafe.lastCallTo(), address(mockTarget), "Call should be to mockTarget");
    }

    // ============================================================
    // Execution Tests
    // ============================================================

    function test_executeOnBehalf_succeeds() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 123);

        vm.prank(authorizedExecutor);
        bool success = module.executeOnBehalf(address(mockTarget), data);

        assertTrue(success, "Execution should succeed");
        assertEq(mockTarget.value(), 123, "Target value should be updated");
        assertEq(mockTarget.lastCaller(), address(mockSafe), "Caller should be the Safe");
    }

    function test_executeOnBehalf_revertsOnSafeFailure() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Set mock Safe to fail
        mockSafe.setFailMode(true);

        vm.prank(authorizedExecutor);
        vm.expectRevert(ISafeExecutorModule.ExecutionFailed.selector);
        module.executeOnBehalf(address(mockTarget), data);
    }

    function test_executeOnBehalf_passesZeroValue() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), data);

        assertEq(mockSafe.lastCallValue(), 0, "Value should always be zero");
    }

    function test_executeOnBehalf_passesCallOperation() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), data);

        assertEq(mockSafe.lastCallOperation(), 0, "Operation should be Call (0), not DelegateCall (1)");
    }

    function test_executeOnBehalf_passesCorrectData() public {
        uint256 expectedValue = 999;
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, expectedValue);

        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), data);

        assertEq(mockSafe.lastCallData(), data, "Data should be passed correctly");
    }

    // ============================================================
    // Integration Tests
    // ============================================================

    function test_moduleExecution_stateChanges() public {
        // Initial state
        assertEq(mockTarget.value(), 0, "Initial value should be 0");

        // Execute via module
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), data);

        // Verify state change
        assertEq(mockTarget.value(), 42, "Value should be updated to 42");
    }

    function test_moduleExecution_multipleCallsInSequence() public {
        // First call
        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), abi.encodeWithSelector(MockTarget.setValue.selector, 10));
        assertEq(mockTarget.value(), 10, "First call should set value to 10");

        // Second call
        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), abi.encodeWithSelector(MockTarget.setValue.selector, 20));
        assertEq(mockTarget.value(), 20, "Second call should set value to 20");

        // Third call
        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), abi.encodeWithSelector(MockTarget.setValue.selector, 30));
        assertEq(mockTarget.value(), 30, "Third call should set value to 30");

        // Verify call count
        assertEq(mockSafe.callCount(), 3, "Safe should have received 3 calls");
    }

    function test_moduleExecution_callerIsSafe() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), data);

        // The target should see the Safe as the caller (not the module or executor)
        assertEq(mockTarget.lastCaller(), address(mockSafe), "Target should see Safe as caller");
    }

    // ============================================================
    // Safe Management Function Blocking Tests
    // ============================================================

    function test_cannotModifySafe_addOwnerWithThreshold() public {
        bytes memory data = abi.encodeWithSelector(MockSafe.addOwnerWithThreshold.selector, makeAddr("newOwner"), 2);

        vm.prank(authorizedExecutor);
        vm.expectRevert(abi.encodeWithSelector(ISafeExecutorModule.CannotCallSafe.selector, address(mockSafe)));
        module.executeOnBehalf(address(mockSafe), data);
    }

    function test_cannotModifySafe_enableModule() public {
        bytes memory data = abi.encodeWithSelector(MockSafe.enableModule.selector, makeAddr("newModule"));

        vm.prank(authorizedExecutor);
        vm.expectRevert(abi.encodeWithSelector(ISafeExecutorModule.CannotCallSafe.selector, address(mockSafe)));
        module.executeOnBehalf(address(mockSafe), data);
    }

    // ============================================================
    // Fuzz Tests
    // ============================================================

    function testFuzz_executeOnBehalf_anyTargetExceptSafeAndModule(address target) public {
        // Skip invalid targets
        vm.assume(target != address(mockSafe));
        vm.assume(target != address(module));
        vm.assume(target != address(0));

        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(authorizedExecutor);
        // Should not revert due to target restrictions (may revert for other reasons like no code)
        try module.executeOnBehalf(target, data) {
        // Success is fine
        }
            catch {
            // Failure is also fine (target may not be a contract)
            // The important thing is it didn't revert with CannotCallSafe or CannotCallModule
        }

        // Verify the call was forwarded to the Safe
        assertEq(mockSafe.lastCallTo(), target, "Call should be forwarded to the target");
    }

    function testFuzz_executeOnBehalf_anyValueInData(uint256 value) public {
        // Test that any value can be passed through the module
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, value);

        vm.prank(authorizedExecutor);
        bool success = module.executeOnBehalf(address(mockTarget), data);

        assertTrue(success, "Execution should succeed");
        assertEq(mockTarget.value(), value, "Value should be set correctly");
    }

    function testFuzz_constructor_anyValidAddresses(address safe, address executor) public {
        vm.assume(safe != address(0));
        vm.assume(executor != address(0));

        SafeExecutorModule newModule = new SafeExecutorModule(safe, executor);

        assertEq(newModule.SAFE(), safe, "Safe should be set");
        assertEq(newModule.AUTHORIZED_EXECUTOR(), executor, "Executor should be set");
    }
}
