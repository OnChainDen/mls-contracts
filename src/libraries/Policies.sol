// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Policies
 * @notice Core data structures for policy-based transaction authorization
 * @dev Policies define "if-then" rules that govern what transactions can be executed
 *      through smart accounts in an organization. Each policy specifies:
 *      - Who can initiate transactions (initiator)
 *      - Who must approve them (approvers)
 *      - What types of transactions are allowed (transfers, interactions, signatures)
 *      - Which accounts, destinations, and functions are permitted
 *      - Optional time-based and amount-based limits
 *
 *      Policies are stored as leaves in a merkle tree (only the root is stored on-chain).
 *      Full policy data is provided in calldata and verified via merkle proofs.
 * @author Den Technologies Inc
 */
library Policies {
    // ================================
    // ENUMS
    // ================================

    /**
     * @notice Defines whether a policy auto-approves transactions or requires manual approval
     * @dev AutoApprove: Transaction proceeds if initiator is authorized
     *      RequireManualApproval: Additional signatures from approvers are required
     */
    enum PolicyType {
        AutoApprove, // No additional approval needed beyond the initiator
        RequireManualApproval // Requires threshold approvals from designated group/member

    }

    /**
     * @notice Defines whether an approver/initiator is a group or individual member
     * @dev Used for both initiator and approver configurations
     */
    enum ApproverType {
        Group, // Refers to a group of members (threshold applies)
        Member // Refers to a single member

    }

    /**
     * @notice Categorizes the type of transaction a policy applies to
     * @dev Helps filter policies based on what kind of operation is being performed
     */
    enum TransactionType {
        Any, // Policy applies to all transaction types
        TokenTransfers, // Policy only applies to ERC20/native token transfers
        ContractInteractions, // Policy only applies to arbitrary contract calls
        Signatures // Policy only applies to ERC-1271 signature validations

    }

    /**
     * @notice Defines how destination addresses are filtered for a policy
     * @dev Controls which addresses can receive funds or be called
     */
    enum DestinationType {
        Any, // Any destination address is allowed
        WhitelistedOnly, // Only addresses in the organization's whitelist
        NonWhitelistedOnly, // Only addresses NOT in the organization's whitelist
        CustomList // Only addresses in the policy's custom destination merkle tree

    }

    /**
     * @notice Defines rate limiting behavior for a policy
     * @dev Controls how transaction frequency/amounts are limited
     */
    enum PolicyLimitation {
        None, // No limit on transactions
        SingleTransaction, // Only one transaction allowed (useful for one-time approvals)
        TimeInterval // Limit resets after a time period (e.g., daily/weekly limits)

    }

    /**
     * @notice Defines how time-based limits are scoped across entities
     * @dev When tracking usage for time-based limits, determines if limits are:
     *      - Shared across all entities (AcrossAll)
     *      - Tracked separately per entity (PerEntity)
     */
    enum TimeIntervalScope {
        AcrossAll, // Single shared limit across all accounts/destinations/initiators
        PerEntity // Separate limit tracked per account/destination/initiator

    }

    // ================================
    // PARAMETER CONSTRAINT TYPES
    // ================================

    /**
     * @notice Supported parameter types for function call constraints
     * @dev Used to specify how to interpret calldata parameters when validating
     *      function calls against policy constraints
     */
    enum ParamType {
        Uint, // Unsigned integer (uint8 to uint256)
        Int, // Signed integer (int8 to int256)
        Address, // Ethereum address (20 bytes)
        Bool, // Boolean value
        FixedBytes, // Fixed-size bytes (bytes1 to bytes32)
        Bytes, // Dynamic bytes
        String, // Dynamic string
        Array, // Dynamic array
        Struct // Tuple/struct type

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
    enum ConstraintType {
        Any, // Any value is accepted (no constraint)
        Exact, // Value must exactly match the specified value
        Range, // Value must be within min/max bounds (for numeric types)
        List // Value must be one of the allowed values in a list
    }

    /**
     * @notice Defines a constraint on a single function parameter
     * @dev Used to restrict what values can be passed to specific function parameters
     * @param paramType The type of the parameter being constrained
     * @param constraintType How the constraint should be evaluated
     * @param slotsToSkip Number of 32-byte slots to skip in calldata to reach this param
     * @param comparisonData ABI-encoded data used for comparison based on constraintType
     */
    struct ParameterConstraint {
        ParamType paramType;
        ConstraintType constraintType;
        uint8 slotsToSkip; // Number of 32-byte slots this parameter occupies (must be >= 1)
        bytes comparisonData;
    }

    // ================================
    // POLICY STRUCTS
    // ================================

    /**
     * @notice Approval configuration - defines who must approve transactions
     * @dev Specifies the approval requirements for a policy
     * @param policyType Whether transactions auto-approve or require manual approval
     * @param approverType Whether approver is a group or individual member
     * @param approverId The ID of the member or group that must approve
     * @param approvalThreshold Required number of approvals (for groups)
     */
    struct ApprovalConfig {
        PolicyType policyType;
        ApproverType approverType;
        uint8 approverId;
        uint8 approvalThreshold;
    }

    /**
     * @notice Initiator configuration - defines who can initiate transactions
     * @dev Specifies who is authorized to create and sign the initial transaction request
     * @param anyInitiator If true, any member can initiate (ignores other fields)
     * @param initiatorType Whether initiator must be from a group or specific member
     * @param initiatorId The ID of the member or group authorized to initiate
     */
    struct InitiatorConfig {
        bool anyInitiator;
        ApproverType initiatorType;
        uint8 initiatorId;
    }

    /**
     * @notice Token transfer constraints - defines token and amount restrictions
     * @dev Used to limit which tokens can be transferred and maximum amounts
     * @param anyToken If true, any token is allowed (ignores tokenAddress)
     * @param tokenAddress Specific token address (only used if !anyToken)
     * @param hasAmountThreshold If true, enforce the amount limit
     * @param amountThreshold Maximum amount per transaction or time period
     */
    struct TokenFilter {
        bool anyToken;
        address tokenAddress;
        bool hasAmountThreshold;
        uint256 amountThreshold;
    }

    /**
     * @notice Time-based limit configuration - defines rate limiting rules
     * @dev Controls how frequently transactions can occur and cumulative limits
     * @param limitation The type of limitation (None, SingleTransaction, TimeInterval)
     * @param timeIntervalHours Duration of the time window in hours (for TimeInterval)
     * @param timeIntervalLimit Maximum cumulative amount/count per time window
     * @param initiatorScope How limits are scoped per initiator
     * @param sourceScope How limits are scoped per source account
     * @param destinationScope How limits are scoped per destination address
     */
    struct TimeLimitConfig {
        PolicyLimitation limitation;
        uint16 timeIntervalHours;
        uint256 timeIntervalLimit;
        TimeIntervalScope initiatorScope;
        TimeIntervalScope sourceScope;
        TimeIntervalScope destinationScope;
    }

    /**
     * @notice Main policy configuration - the complete set of policy rules
     * @dev This struct contains all the configuration that defines a policy's behavior.
     *      Replaces the previous packed uint256 approach for improved readability.
     * @param transactionType What types of transactions this policy applies to
     * @param anySourceAccount If true, policy applies to all accounts
     * @param anyFunction If true, any function selector is allowed
     * @param destinationType How destination addresses are filtered
     * @param approval Approval requirements configuration
     * @param initiator Initiator authorization configuration
     * @param token Token and amount constraints
     * @param timeLimit Rate limiting configuration
     */
    struct PolicyConfig {
        TransactionType transactionType;
        bool anySourceAccount;
        bool anyFunction;
        DestinationType destinationType;
        ApprovalConfig approval;
        InitiatorConfig initiator;
        TokenFilter token;
        TimeLimitConfig timeLimit;
    }

    /**
     * @notice Merkle roots for policy-specific address and function lists
     * @dev These roots allow policies to reference large lists of addresses/functions
     *      without storing them on-chain. The actual lists are provided in calldata
     *      and verified via merkle proofs.
     * @param sourceAccountsRoot Root of merkle tree containing allowed source accounts
     * @param customDestinationsRoot Root of merkle tree containing allowed destinations
     * @param allowedFunctionsRoot Root of merkle tree containing allowed function selectors
     */
    struct PolicyRoots {
        bytes32 sourceAccountsRoot;
        bytes32 customDestinationsRoot;
        bytes32 allowedFunctionsRoot;
    }

    /**
     * @notice Complete policy representation combining config and merkle roots
     * @dev This is the full policy structure that gets hashed and stored in the
     *      organization's policy merkle tree
     * @param config The policy configuration rules
     * @param roots Merkle roots for address/function lists
     */
    struct Policy {
        PolicyConfig config;
        PolicyRoots roots;
    }

    // ================================
    // VALIDATION PROOFS
    // ================================

    /**
     * @notice All proofs needed to validate a transaction against a policy
     * @dev Bundled together to simplify function signatures and reduce stack depth
     * @param policy The full policy data (verified against policyProof)
     * @param policyProof Merkle proof that this policy exists in the organization
     * @param sourceAccountProof Proof that source account is allowed by policy
     * @param destinationProof Proof that destination is allowed by policy
     * @param functionProof Proof that function selector is allowed by policy
     * @param constraints ABI-encoded parameter constraints for function calls
     */
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

    /**
     * @notice Structure for function selector leaves in the allowed functions merkle tree
     * @dev Each allowed function has a selector and optional parameter constraints
     * @param selector The 4-byte function selector
     * @param constraintsHash Hash of the parameter constraints for this function
     */
    struct FunctionLeaf {
        bytes4 selector;
        bytes32 constraintsHash;
    }
}
