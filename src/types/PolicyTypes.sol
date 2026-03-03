// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Policy Types
 * @notice Core data structures for policy-based transaction authorization
 * @dev Policies define "if-then" rules that govern what transactions can be executed
 *      through smart accounts in an organization. Each policy specifies:
 *      - Who can initiate transactions (initiator)
 *      - Who must approve them (approvers)
 *      - What types of transactions are allowed (transfers, interactions, signatures)
 *      - Which accounts, destinations, and functions are permitted
 *      - Optional rate limits and amount-based limits
 *
 *      Policies are stored as leaves in a merkle tree (only the root is stored on-chain).
 *      Full policy data is provided in calldata and verified via merkle proofs.
 *
 *      Members and Groups are stored in onchain mappings. Membership is verified via direct storage reads.
 * @author Den Technologies Inc
 */

/**
 * @dev Defines whether a policy auto-approves transactions or requires manual approval.
 *      AutoApprove: Transaction proceeds if initiator is authorized.
 *      RequireManualApproval: Additional signatures from approvers are required
 */
enum PolicyType {
    AutoApprove, // No additional approval needed beyond the initiator
    RequireManualApproval // Requires threshold approvals from designated group/member
}

/**
 * @dev Defines whether an approver/initiator is a group or individual member.
 *      Used for both initiator and approver configurations.
 */
enum ApproverType {
    Group, // Refers to a group of members (threshold applies)
    Member // Refers to a single member
}

/**
 * @dev Categorizes the type of transaction a policy applies to.
 *      Helps filter policies based on what kind of operation is being performed.
 */
enum TransactionType {
    Any, // Policy applies to all transaction types
    TokenTransfers, // Policy only applies to ERC20/native token transfers
    ContractInteractions, // Policy only applies to arbitrary contract calls
    Signatures // Policy only applies to ERC-1271 signature validations
}

/**
 * @dev Defines how destination addresses are filtered for a policy.
 *      Controls which addresses can receive funds or be called.
 */
enum DestinationType {
    Any, // Any destination address is allowed
    CustomList // Only addresses in the policy's custom destination merkle tree
}

/**
 * @dev Defines rate limiting behavior for a policy.
 *      Controls how transaction frequency/amounts are limited.
 */
enum RateLimitType {
    None, // No limit on transactions
    TimeInterval // Limit resets after a time period (e.g., daily/weekly limits)
}

/**
 * @dev Defines how rate limits are scoped across entities.
 *      When tracking usage for rate limits, determines if limits are:
 *      - Shared across all entities (AcrossAll)
 *      - Tracked separately per entity (PerEntity)
 */
enum RateLimitScope {
    AcrossAll, // Single shared limit across all accounts/destinations/initiators
    PerEntity // Separate limit tracked per account/destination/initiator
}

/**
 * @dev Supported parameter types for function call constraints.
 *      Used to specify how to interpret calldata parameters when validating
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

/// @dev A constraint on a single function parameter
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
///      - OneOf + Address: abi.encode(bytes32 merkleRoot) - root of allowed addresses merkle tree
///
/// @dev The paramCalldataHeadSlotCount field specifies how many 32-byte head slots this parameter occupies
///      (must be >= 1). In ABI encoding, the "head" contains values for static types or offset pointers for
///      dynamic types:
///      - Basic types (uint, int, address, bool, bytes1-32): 1 head slot
///      - Dynamic types (string, bytes, T[]): 1 head slot (contains offset to tail data)
///      - Static arrays T[k]: k head slots (stored inline)
///      - Static structs with N fields: N head slots (stored inline)
///      - Dynamic structs: 1 head slot (contains offset to tail data)
enum ConstraintType {
    Any, // Any value is accepted (no constraint)
    Exact, // Value must exactly match the specified value
    Range, // Value must be within min/max bounds (for numeric types)
    OneOf // Value must be one of the allowed values in a list
}

/**
 * @dev Defines a constraint on a single function parameter.
 *      Used to restrict what values can be passed to specific function parameters.
 * @param paramType The type of the parameter being constrained
 * @param constraintType How the constraint should be evaluated
 * @param paramCalldataHeadSlotCount Number of 32-byte head slots this parameter occupies in calldata (must be >= 1)
 * @param comparisonData ABI-encoded data used for comparison based on constraintType
 * @param paramValueInListProof Merkle proof for OneOf constraints (empty for other constraint types)
 */
struct ParameterConstraint {
    ParamType paramType;
    ConstraintType constraintType;
    uint8 paramCalldataHeadSlotCount; // Number of 32-byte head slots this parameter occupies (must be >= 1)
    bytes comparisonData;
    bytes32[] paramValueInListProof; // Merkle proof for OneOf constraints (empty otherwise)
}

/**
 * @dev Approval configuration - defines who must approve transactions.
 *      Specifies the approval requirements for a policy.
 *      Uses address for Member approver and uint256 groupId for Group approver.
 * @param policyType Whether transactions auto-approve or require manual approval
 * @param approverType Whether approver is a group or individual member
 * @param approverMember The address of the member that must approve (when approverType == Member)
 * @param approverGroupId The ID of the group that must approve (when approverType == Group)
 * @param approvalThreshold Required number of approvals (for groups)
 */
// Struct packing is not beneficial here: this struct is only passed via calldata/memory
// and never stored on-chain directly (only its hash as part of a merkle root).
// ABI encoding uses full 32-byte slots regardless, so we prioritize readability.
// solhint-disable-next-line gas-struct-packing
struct ApprovalConfig {
    PolicyType policyType;
    ApproverType approverType;
    address approverMember; // Used when approverType == Member
    uint256 approverGroupId; // Used when approverType == Group
    uint8 approvalThreshold;
}

/**
 * @dev Initiator configuration - defines who can initiate transactions.
 *      Specifies who is authorized to create and sign the initial transaction request.
 *      Uses address for Member initiator and uint256 groupId for Group initiator.
 * @param anyInitiator If true, any member can initiate (ignores other fields)
 * @param initiatorType Whether initiator must be from a group or specific member
 * @param initiatorMember The address of the member authorized to initiate (when initiatorType == Member)
 * @param initiatorGroupId The ID of the group authorized to initiate (when initiatorType == Group)
 */
// Struct packing is not beneficial here: this struct is only passed via calldata/memory
// and never stored on-chain directly (only its hash as part of a merkle root).
// ABI encoding uses full 32-byte slots regardless, so we prioritize readability.
// solhint-disable-next-line gas-struct-packing
struct InitiatorConfig {
    bool anyInitiator;
    ApproverType initiatorType;
    address initiatorMember; // Used when initiatorType == Member
    uint256 initiatorGroupId; // Used when initiatorType == Group
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
 * @dev Rate limit configuration - defines rate limiting rules.
 *      Controls how frequently transactions can occur and cumulative limits.
 * @param limitType The type of rate limit (None or TimeInterval)
 * @param timeIntervalHours Duration of the time window in hours (for TimeInterval)
 * @param windowAnchorTimestamp Unix timestamp that anchors interval boundaries.
 *        Window 0 starts at this timestamp; subsequent windows repeat every `timeIntervalHours`.
 *        Use UTC-aligned values (for example, Monday 00:00 UTC) to match business schedules.
 * @param timeIntervalLimit Maximum cumulative amount/count per time window
 * @param initiatorScope How limits are scoped per initiator
 * @param sourceScope How limits are scoped per source account
 * @param destinationScope How limits are scoped per destination address
 */
struct RateLimitConfig {
    RateLimitType limitType;
    uint16 timeIntervalHours;
    uint64 windowAnchorTimestamp;
    uint256 timeIntervalLimit;
    RateLimitScope initiatorScope;
    RateLimitScope sourceScope;
    RateLimitScope destinationScope;
}

/**
 * @dev Main policy configuration - the complete set of policy rules.
 *      This struct contains all the configuration that defines a policy's behavior.
 *      Replaces the previous packed uint256 approach for improved readability.
 * @param transactionType What types of transactions this policy applies to
 * @param anySourceAccount If true, policy applies to all accounts
 * @param anyFunction If true, any function selector is allowed
 * @param destinationType How destination addresses are filtered
 * @param approval Approval requirements configuration
 * @param initiator Initiator authorization configuration
 * @param token Token and amount constraints
 * @param rateLimit Rate limiting configuration
 */
struct PolicyConfig {
    TransactionType transactionType;
    bool anySourceAccount;
    bool anyFunction;
    DestinationType destinationType;
    ApprovalConfig approval;
    InitiatorConfig initiator;
    TokenFilter token;
    RateLimitConfig rateLimit;
}

/**
 * @dev Merkle roots for policy-specific address and function lists.
 *      These roots allow policies to reference large lists of addresses/functions
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

/**
 * @notice All proofs and data needed to validate a transaction against a policy
 * @dev Bundled together to simplify function signatures and reduce stack depth.
 *      Policy existence is verified via merkle proof. Initiator/approver membership is
 *      verified via direct storage reads (mappings). Group IDs for initiator and approver
 *      verification are obtained from the policy's config (InitiatorConfig and ApprovalConfig).
 * @param policy The full policy data (verified against policyProof)
 * @param policyProof Merkle proof that this policy exists in the organization
 * @param sourceAccountProof Proof that source account is allowed by policy
 * @param destinationProof Proof that destination is allowed by policy
 * @param functionProof Proof that function selector is allowed by policy
 * @param constraints ABI-encoded parameter constraints for function calls (includes proofs for OneOf constraints)
 */
struct ValidationProofs {
    Policy policy;
    bytes32[] policyProof;
    bytes32[] sourceAccountProof;
    bytes32[] destinationProof;
    bytes32[] functionProof;
    bytes constraints;
}
