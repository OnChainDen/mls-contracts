// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Policies {
    enum PolicyType {
        AutoApprove,
        RequireManualApproval
    }

    enum ApproverType {
        Group,
        Member
    }

    enum TransactionType {
        Any,
        TokenTransfers,
        ContractInteractions
    }

    enum DestinationType {
        Any,
        WhitelistedOnly,
        NonWhitelistedOnly,
        CustomList
    }

    enum PolicyLimitation {
        None,
        SingleTransaction,
        TimeInterval
    }

    enum TimeIntervalScope {
        AcrossAll,
        PerEntity
    }

    // ================================
    // PARAMETER CONSTRAINT TYPES
    // ================================

    /// @notice Types of function parameters that can be constrained
    enum ParamType {
        Uint, // uint8, uint16, ..., uint256 (and enums)
        Int, // int8, int16, ..., int256
        Address, // address
        Bool, // bool
        FixedBytes, // bytes1, bytes2, ..., bytes32 (static, stored inline)
        Bytes, // bytes (dynamic, stored as offset)
        String, // string (dynamic, stored as offset)
        Array, // dynamic or fixed-size arrays
        Struct // structs or tuples

    }

    /// @notice Types of constraints that can be applied to parameters
    enum ConstraintType {
        Any, // Wildcard - any value is accepted
        Exact, // Must match exactly (for all types except Array/Struct)
        Range, // Must be within range [min, max] inclusive (for Uint/Int only)
        List // Must be one of the allowed values (for Address only)

    }

    /// @notice A constraint on a single function parameter
    /// @dev The comparisonData field is ABI-encoded based on paramType and constraintType:
    ///      - Any: empty bytes (no comparison needed)
    ///      - Exact + Uint: abi.encode(uint256 value)
    ///      - Exact + Int: abi.encode(int256 value)
    ///      - Exact + Address: abi.encode(address value)
    ///      - Exact + Bool: abi.encode(bool value)
    ///      - Exact + FixedBytes: abi.encode(bytes32 value) - value is left-padded for bytes1-bytes31
    ///      - Exact + Bytes: abi.encode(bytes32 keccak256Hash) - hash of expected dynamic bytes
    ///      - Exact + String: abi.encode(bytes32 keccak256Hash) - hash of expected string
    ///      - Range + Uint: abi.encode(uint256 min, uint256 max)
    ///      - Range + Int: abi.encode(int256 min, int256 max)
    ///      - List + Address: abi.encode(address[] allowedAddresses)
    ///
    /// @dev The slotsToSkip field specifies how many 32-byte slots this parameter occupies (must be >= 1):
    ///      - Basic types (uint, int, address, bool, bytes1-32): 1 slot
    ///      - Dynamic types (string, bytes, T[]): 1 slot (contains offset)
    ///      - Static arrays T[k]: k slots (stored inline)
    ///      - Static structs with N fields: N slots (stored inline)
    ///      - Dynamic structs: 1 slot (contains offset)
    struct ParameterConstraint {
        ParamType paramType;
        ConstraintType constraintType;
        uint8 slotsToSkip; // Number of 32-byte slots this parameter occupies (must be >= 1)
        bytes comparisonData;
    }

    struct FunctionSelector {
        bytes4 selector;
        bytes parameterConstraints; // ABI-encoded ParameterConstraint[] array
    }

    struct Policy {
        // Core policy behavior
        PolicyType policyType;
        // Approver configuration (only used when policyType == RequireManualApproval)
        ApproverType approverType;
        uint8 approverId; // ID of the group or member who can approve
        uint256 approvalThreshold; // Number of approvals needed (only used when approverType == Group)
        // Transaction source filtering
        bool anySourceAccount; // If true, applies to transactions from any account
        address[] sourceAccountAddresses; // Specific account addresses (only used when anySourceAccount == false)
        // Transaction initiator filtering
        bool anyInitiator; // If true, applies to transactions initiated by anyone
        ApproverType initiatorType; // Whether initiator filter is by Group or Member
        uint8 initiatorId; // ID of the specific group or member (only used when anyInitiator == false)
        // Transaction type filtering
        TransactionType transactionType;
        // Token filtering (only used when transactionType == TokenTransfers)
        bool anyToken; // If true, applies to transfers of any token
        address tokenAddress; // Specific token address (use address(0) for native token)
        // Amount threshold filtering (only used when transactionType == TokenTransfers)
        bool hasAmountThreshold; // If true, policy only applies when amount < amountThreshold
        uint256 amountThreshold; // Maximum amount for policy to apply
        // Transaction destination filtering
        DestinationType destinationType;
        address[] customDestinations; // Custom list of addresses (only used when destinationType == CustomList)
        // Function filtering (only used when transactionType == ContractInteractions)
        bool anyFunction; // If true, applies to calls to any function
        FunctionSelector[] allowedFunctions; // Specific functions that can be called
        // Policy usage limitations
        PolicyLimitation limitation;
        uint256 timeIntervalHours; // Hours in time interval (only used when limitation == TimeInterval)
        TimeIntervalScope timeIntervalInitiatorScope; // Whether time limits are per-initiator or global
        TimeIntervalScope timeIntervalSourceScope; // Whether time limits are per-source-account or global
        TimeIntervalScope timeIntervalDestinationScope; // Whether time limits are per-destination or global
    }
}
