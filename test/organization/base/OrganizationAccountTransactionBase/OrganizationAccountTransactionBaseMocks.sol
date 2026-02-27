// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IAccount} from "interfaces/IAccount.sol";

interface OrganizationNonceReader {
    function getUsedNonce(uint256 nonce) external view returns (bool);
}

/**
 * @dev Lightweight account mock used by `OrganizationAccountTransactionBase` suites.
 *      Persists call arguments and optionally executes/reverts the requested downstream call.
 */
contract MockAccountForOrganizationTransaction is IAccount {
    /// @dev Bound organization that is allowed to call `executeTransaction`.
    address public immutable organization;

    /// @dev Controls whether `executeTransaction` reverts before attempting the downstream call.
    bool public shouldRevertExecution;

    /// @dev Enables CEI assertion that nonce is already consumed before account call entry.
    bool public assertNonceConsumedOnEntry;

    /// @dev Captured calldata from the latest execution call.
    address public lastTo;
    uint256 public lastValue;
    bytes public lastData;
    uint256 public lastNonce;
    uint256 public lastPolicyId;
    uint256 public executionCount;

    constructor(address organization_) {
        organization = organization_;
    }

    /**
     * @dev Configures explicit execution failure for negative-path tests.
     */
    function setShouldRevertExecution(bool shouldRevertExecution_) external {
        shouldRevertExecution = shouldRevertExecution_;
    }

    /**
     * @dev Enables/disables nonce-consumed assertion at execution entry.
     */
    function setAssertNonceConsumedOnEntry(bool assertNonceConsumedOnEntry_) external {
        assertNonceConsumedOnEntry = assertNonceConsumedOnEntry_;
    }

    /// @inheritdoc IAccount
    receive() external payable override {
        emit MLSWalletAccountNativeTokenReceived(msg.sender, msg.value);
    }

    /// @inheritdoc IAccount
    function executeTransaction(address to, uint256 value, bytes calldata data, uint256 nonce, uint256 policyId)
        external
        override
    {
        if (msg.sender != organization) {
            revert OnlyOrganization();
        }

        if (assertNonceConsumedOnEntry && !OrganizationNonceReader(organization).getUsedNonce(nonce)) {
            revert TransactionExecutionFailed();
        }

        executionCount++;
        lastTo = to;
        lastValue = value;
        lastData = data;
        lastNonce = nonce;
        lastPolicyId = policyId;

        if (shouldRevertExecution) {
            revert TransactionExecutionFailed();
        }

        (bool success,) = to.call{value: value}(data);
        if (!success) {
            revert TransactionExecutionFailed();
        }

        emit TransactionExecuted({to: to, value: value, data: data, nonce: nonce, policyId: policyId});
    }

    /// @inheritdoc IAccount
    function getOrganizationAddress() external view override returns (address) {
        return organization;
    }

    /// @dev ERC-1271 placeholder implementation for interface completeness.
    function isValidSignature(bytes32, bytes calldata) external pure override returns (bytes4) {
        return 0xffffffff;
    }
}

/**
 * @dev Simple payable receiver for native-transfer assertions.
 */
contract MockNativeReceiver {
    /// @dev Last ETH amount received through `receive`.
    uint256 public totalReceived;

    receive() external payable {
        totalReceived += msg.value;
    }
}

/**
 * @dev Minimal ERC-20 used by account-transaction base integration checks.
 */
contract MockERC20ForAccountTransaction {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/**
 * @dev Contract-interaction target used to assert calldata/value forwarding.
 */
contract MockInteractionTarget {
    uint256 public calls;
    uint256 public lastValue;
    bytes public lastCallData;
    address public lastCaller;
    uint256 public total;

    function ping(uint256 amount) external payable {
        calls++;
        lastValue = msg.value;
        lastCallData = msg.data;
        lastCaller = msg.sender;
        total += amount;
    }
}

/**
 * @dev Reverting destination used by rollback-path tests.
 */
contract MockRevertingDestination {
    error ForcedRevert();

    function fail() external pure {
        revert ForcedRevert();
    }
}

/**
 * @dev ERC-1271 signer that validates signatures only when a specific nonce is already consumed.
 *      Used to assert nonce-consumption ordering during validation flows.
 */
contract MockERC1271NonceConsumedSigner is IERC1271 {
    /// @dev Organization contract exposing nonce-usage state.
    address public immutable organization;

    /// @dev Nonce that must be consumed for signatures to be considered valid.
    uint256 public observedNonce;

    constructor(address organization_) {
        organization = organization_;
    }

    /**
     * @dev Sets the nonce observed during signature checks.
     */
    function setObservedNonce(uint256 observedNonce_) external {
        observedNonce = observedNonce_;
    }

    /**
     * @dev Returns ERC-1271 magic value only if the observed nonce is already consumed.
     */
    function isValidSignature(bytes32, bytes memory) external view override returns (bytes4) {
        if (OrganizationNonceReader(organization).getUsedNonce(observedNonce)) {
            return IERC1271.isValidSignature.selector;
        }
        return bytes4(0xffffffff);
    }
}
