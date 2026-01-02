// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Policies {
    // ================================
    // ENUMS
    // ================================

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
        ContractInteractions,
        Signatures
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

    enum ParamType {
        Uint,
        Int,
        Address,
        Bool,
        FixedBytes,
        Bytes,
        String,
        Array,
        Struct
    }

    enum ConstraintType {
        Any,
        Exact,
        Range,
        List
    }

    struct ParameterConstraint {
        ParamType paramType;
        ConstraintType constraintType;
        uint8 slotsToSkip;
        bytes comparisonData;
    }

    // ================================
    // POLICY STRUCTS
    // ================================

    /// @notice Approval configuration - who needs to approve transactions
    struct ApprovalConfig {
        PolicyType policyType; // AutoApprove or RequireManualApproval
        ApproverType approverType; // Group or Member
        uint8 approverId; // Member or Group ID
        uint8 approvalThreshold; // Required approvals for group
    }

    /// @notice Initiator configuration - who can initiate transactions
    struct InitiatorConfig {
        bool anyInitiator; // If true, anyone can initiate
        ApproverType initiatorType; // Group or Member
        uint8 initiatorId; // Member or Group ID
    }

    /// @notice Token transfer constraints
    struct TokenFilter {
        bool anyToken; // If true, any token allowed
        address tokenAddress; // Specific token (if !anyToken)
        bool hasAmountThreshold; // If true, enforce amount limit
        uint256 amountThreshold; // Max amount per tx/period
    }

    /// @notice Time-based limit configuration
    struct TimeLimitConfig {
        PolicyLimitation limitation; // None, SingleTransaction, TimeInterval
        uint16 timeIntervalHours; // Time window in hours
        uint256 timeIntervalLimit; // Limit per time window
        TimeIntervalScope initiatorScope; // AcrossAll or PerEntity
        TimeIntervalScope sourceScope; // AcrossAll or PerEntity
        TimeIntervalScope destinationScope; // AcrossAll or PerEntity
    }

    /// @notice Main policy configuration (replaces packed uint256)
    struct PolicyConfig {
        TransactionType transactionType; // Any, TokenTransfers, ContractInteractions, Signatures
        bool anySourceAccount; // Source account filter flag
        bool anyFunction; // Function filter flag
        DestinationType destinationType; // Destination filter type
        ApprovalConfig approval;
        InitiatorConfig initiator;
        TokenFilter token;
        TimeLimitConfig timeLimit;
    }

    /// @notice Merkle roots for policy-specific address lists
    struct PolicyRoots {
        bytes32 sourceAccountsRoot;
        bytes32 customDestinationsRoot;
        bytes32 allowedFunctionsRoot;
    }

    /// @notice Complete policy representation
    struct Policy {
        PolicyConfig config;
        PolicyRoots roots;
    }

    // ================================
    // VALIDATION PROOFS
    // ================================

    struct ValidationProofs {
        Policy policy;
        bytes32[] policyProof;
        bytes32[] sourceAccountProof;
        bytes32[] destinationProof;
        bytes32[] functionProof;
        bytes constraints;
    }

    // ================================
    // FUNCTION LEAF STRUCTURE
    // ================================

    struct FunctionLeaf {
        bytes4 selector;
        bytes32 constraintsHash;
    }
}
