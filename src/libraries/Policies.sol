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
    // COMPACT POLICY STRUCT
    // ================================

    /// @notice Packed configuration word #1 (fits in ~4 bytes, padded to 32)
    /// This packs many small fields together to reduce stack pressure
    /// Layout:
    ///   bits 0-7:   flags (anySourceAccount, anyInitiator, anyToken, hasAmountThreshold, anyFunction)
    ///   bits 8-15:  policyType (1), approverType (1), initiatorType (1), destinationType (2), limitation (2),
    /// transactionType (2) = 9 bits packed
    ///   bits 16-23: approverId
    ///   bits 24-31: approvalThreshold
    ///   bits 32-39: initiatorId
    ///   bits 40-55: timeIntervalHours
    ///   bits 56-63: timeIntervalScopes (initiator 2, source 2, destination 2) = 6 bits

    /// @notice Policy representation - optimized for stack efficiency
    /// Uses two structs to break up the fields
    struct PolicyConfig {
        // Packed config word containing:
        // - flags (5 bits for booleans)
        // - policyType, approverType, initiatorType, destinationType, limitation, transactionType (small enums)
        // - IDs and thresholds
        uint256 packed;
        // Time interval limit
        uint256 timeIntervalLimit;
        // Token config
        address tokenAddress;
        uint256 amountThreshold;
    }

    struct PolicyRoots {
        bytes32 sourceAccountsRoot;
        bytes32 customDestinationsRoot;
        bytes32 allowedFunctionsRoot;
    }

    struct Policy {
        PolicyConfig config;
        PolicyRoots roots;
    }

    // ================================
    // PACKING CONSTANTS
    // ================================

    // Flag positions (bits 0-4)
    uint256 constant FLAG_ANY_SOURCE_ACCOUNT = 1 << 0;
    uint256 constant FLAG_ANY_INITIATOR = 1 << 1;
    uint256 constant FLAG_ANY_TOKEN = 1 << 2;
    uint256 constant FLAG_HAS_AMOUNT_THRESHOLD = 1 << 3;
    uint256 constant FLAG_ANY_FUNCTION = 1 << 4;

    // Field positions
    uint256 constant SHIFT_POLICY_TYPE = 8;
    uint256 constant SHIFT_APPROVER_TYPE = 9;
    uint256 constant SHIFT_INITIATOR_TYPE = 10;
    uint256 constant SHIFT_DEST_TYPE = 11;
    uint256 constant SHIFT_LIMITATION = 13;
    uint256 constant SHIFT_TX_TYPE = 15;
    uint256 constant SHIFT_APPROVER_ID = 17;
    uint256 constant SHIFT_APPROVAL_THRESHOLD = 25;
    uint256 constant SHIFT_INITIATOR_ID = 33;
    uint256 constant SHIFT_TIME_HOURS = 41;
    uint256 constant SHIFT_TIME_SCOPES = 57;

    // Masks
    uint256 constant MASK_1BIT = 0x1;
    uint256 constant MASK_2BIT = 0x3;
    uint256 constant MASK_8BIT = 0xFF;
    uint256 constant MASK_16BIT = 0xFFFF;
    uint256 constant MASK_6BIT = 0x3F;

    // ================================
    // PACK/UNPACK HELPERS
    // ================================

    function packConfig(
        bool _anySourceAccount,
        bool _anyInitiator,
        bool _anyToken,
        bool _hasAmountThreshold,
        bool _anyFunction,
        PolicyType _policyType,
        ApproverType _approverType,
        ApproverType _initiatorType,
        DestinationType _destType,
        PolicyLimitation _limitation,
        TransactionType _txType,
        uint8 _approverId,
        uint8 _approvalThreshold,
        uint8 _initiatorId,
        uint16 _timeIntervalHours,
        TimeIntervalScope _initiatorScope,
        TimeIntervalScope _sourceScope,
        TimeIntervalScope _destScope
    )
        internal
        pure
        returns (uint256 packed)
    {
        // Pack flags
        if (_anySourceAccount) packed |= FLAG_ANY_SOURCE_ACCOUNT;
        if (_anyInitiator) packed |= FLAG_ANY_INITIATOR;
        if (_anyToken) packed |= FLAG_ANY_TOKEN;
        if (_hasAmountThreshold) packed |= FLAG_HAS_AMOUNT_THRESHOLD;
        if (_anyFunction) packed |= FLAG_ANY_FUNCTION;

        // Pack enums and small values
        packed |= uint256(_policyType) << SHIFT_POLICY_TYPE;
        packed |= uint256(_approverType) << SHIFT_APPROVER_TYPE;
        packed |= uint256(_initiatorType) << SHIFT_INITIATOR_TYPE;
        packed |= uint256(_destType) << SHIFT_DEST_TYPE;
        packed |= uint256(_limitation) << SHIFT_LIMITATION;
        packed |= uint256(_txType) << SHIFT_TX_TYPE;
        packed |= uint256(_approverId) << SHIFT_APPROVER_ID;
        packed |= uint256(_approvalThreshold) << SHIFT_APPROVAL_THRESHOLD;
        packed |= uint256(_initiatorId) << SHIFT_INITIATOR_ID;
        packed |= uint256(_timeIntervalHours) << SHIFT_TIME_HOURS;

        // Pack time scopes (2 bits each)
        uint256 scopes = uint256(_initiatorScope) | (uint256(_sourceScope) << 2) | (uint256(_destScope) << 4);
        packed |= scopes << SHIFT_TIME_SCOPES;
    }

    // Unpack helpers
    function anySourceAccount(Policy memory policy) internal pure returns (bool) {
        return (policy.config.packed & FLAG_ANY_SOURCE_ACCOUNT) != 0;
    }

    function anyInitiator(Policy memory policy) internal pure returns (bool) {
        return (policy.config.packed & FLAG_ANY_INITIATOR) != 0;
    }

    function anyToken(Policy memory policy) internal pure returns (bool) {
        return (policy.config.packed & FLAG_ANY_TOKEN) != 0;
    }

    function hasAmountThreshold(Policy memory policy) internal pure returns (bool) {
        return (policy.config.packed & FLAG_HAS_AMOUNT_THRESHOLD) != 0;
    }

    function anyFunction(Policy memory policy) internal pure returns (bool) {
        return (policy.config.packed & FLAG_ANY_FUNCTION) != 0;
    }

    function policyType(Policy memory policy) internal pure returns (PolicyType) {
        return PolicyType((policy.config.packed >> SHIFT_POLICY_TYPE) & MASK_1BIT);
    }

    function approverType(Policy memory policy) internal pure returns (ApproverType) {
        return ApproverType((policy.config.packed >> SHIFT_APPROVER_TYPE) & MASK_1BIT);
    }

    function initiatorType(Policy memory policy) internal pure returns (ApproverType) {
        return ApproverType((policy.config.packed >> SHIFT_INITIATOR_TYPE) & MASK_1BIT);
    }

    function destinationType(Policy memory policy) internal pure returns (DestinationType) {
        return DestinationType((policy.config.packed >> SHIFT_DEST_TYPE) & MASK_2BIT);
    }

    function limitation(Policy memory policy) internal pure returns (PolicyLimitation) {
        return PolicyLimitation((policy.config.packed >> SHIFT_LIMITATION) & MASK_2BIT);
    }

    function transactionType(Policy memory policy) internal pure returns (TransactionType) {
        return TransactionType((policy.config.packed >> SHIFT_TX_TYPE) & MASK_2BIT);
    }

    function approverId(Policy memory policy) internal pure returns (uint8) {
        return uint8((policy.config.packed >> SHIFT_APPROVER_ID) & MASK_8BIT);
    }

    function approvalThreshold(Policy memory policy) internal pure returns (uint8) {
        return uint8((policy.config.packed >> SHIFT_APPROVAL_THRESHOLD) & MASK_8BIT);
    }

    function initiatorId(Policy memory policy) internal pure returns (uint8) {
        return uint8((policy.config.packed >> SHIFT_INITIATOR_ID) & MASK_8BIT);
    }

    function timeIntervalHours(Policy memory policy) internal pure returns (uint16) {
        return uint16((policy.config.packed >> SHIFT_TIME_HOURS) & MASK_16BIT);
    }

    function timeIntervalInitiatorScope(Policy memory policy) internal pure returns (TimeIntervalScope) {
        uint256 scopes = (policy.config.packed >> SHIFT_TIME_SCOPES) & MASK_6BIT;
        return TimeIntervalScope(scopes & MASK_2BIT);
    }

    function timeIntervalSourceScope(Policy memory policy) internal pure returns (TimeIntervalScope) {
        uint256 scopes = (policy.config.packed >> SHIFT_TIME_SCOPES) & MASK_6BIT;
        return TimeIntervalScope((scopes >> 2) & MASK_2BIT);
    }

    function timeIntervalDestinationScope(Policy memory policy) internal pure returns (TimeIntervalScope) {
        uint256 scopes = (policy.config.packed >> SHIFT_TIME_SCOPES) & MASK_6BIT;
        return TimeIntervalScope((scopes >> 4) & MASK_2BIT);
    }

    // Calldata versions for efficiency
    function anySourceAccountCalldata(Policy calldata policy) internal pure returns (bool) {
        return (policy.config.packed & FLAG_ANY_SOURCE_ACCOUNT) != 0;
    }

    function anyInitiatorCalldata(Policy calldata policy) internal pure returns (bool) {
        return (policy.config.packed & FLAG_ANY_INITIATOR) != 0;
    }

    function anyTokenCalldata(Policy calldata policy) internal pure returns (bool) {
        return (policy.config.packed & FLAG_ANY_TOKEN) != 0;
    }

    function hasAmountThresholdCalldata(Policy calldata policy) internal pure returns (bool) {
        return (policy.config.packed & FLAG_HAS_AMOUNT_THRESHOLD) != 0;
    }

    function anyFunctionCalldata(Policy calldata policy) internal pure returns (bool) {
        return (policy.config.packed & FLAG_ANY_FUNCTION) != 0;
    }

    function policyTypeCalldata(Policy calldata policy) internal pure returns (PolicyType) {
        return PolicyType((policy.config.packed >> SHIFT_POLICY_TYPE) & MASK_1BIT);
    }

    function approverTypeCalldata(Policy calldata policy) internal pure returns (ApproverType) {
        return ApproverType((policy.config.packed >> SHIFT_APPROVER_TYPE) & MASK_1BIT);
    }

    function initiatorTypeCalldata(Policy calldata policy) internal pure returns (ApproverType) {
        return ApproverType((policy.config.packed >> SHIFT_INITIATOR_TYPE) & MASK_1BIT);
    }

    function destinationTypeCalldata(Policy calldata policy) internal pure returns (DestinationType) {
        return DestinationType((policy.config.packed >> SHIFT_DEST_TYPE) & MASK_2BIT);
    }

    function limitationCalldata(Policy calldata policy) internal pure returns (PolicyLimitation) {
        return PolicyLimitation((policy.config.packed >> SHIFT_LIMITATION) & MASK_2BIT);
    }

    function transactionTypeCalldata(Policy calldata policy) internal pure returns (TransactionType) {
        return TransactionType((policy.config.packed >> SHIFT_TX_TYPE) & MASK_2BIT);
    }

    function approverIdCalldata(Policy calldata policy) internal pure returns (uint8) {
        return uint8((policy.config.packed >> SHIFT_APPROVER_ID) & MASK_8BIT);
    }

    function approvalThresholdCalldata(Policy calldata policy) internal pure returns (uint8) {
        return uint8((policy.config.packed >> SHIFT_APPROVAL_THRESHOLD) & MASK_8BIT);
    }

    function initiatorIdCalldata(Policy calldata policy) internal pure returns (uint8) {
        return uint8((policy.config.packed >> SHIFT_INITIATOR_ID) & MASK_8BIT);
    }

    function timeIntervalHoursCalldata(Policy calldata policy) internal pure returns (uint16) {
        return uint16((policy.config.packed >> SHIFT_TIME_HOURS) & MASK_16BIT);
    }

    function timeIntervalInitiatorScopeCalldata(Policy calldata policy) internal pure returns (TimeIntervalScope) {
        uint256 scopes = (policy.config.packed >> SHIFT_TIME_SCOPES) & MASK_6BIT;
        return TimeIntervalScope(scopes & MASK_2BIT);
    }

    function timeIntervalSourceScopeCalldata(Policy calldata policy) internal pure returns (TimeIntervalScope) {
        uint256 scopes = (policy.config.packed >> SHIFT_TIME_SCOPES) & MASK_6BIT;
        return TimeIntervalScope((scopes >> 2) & MASK_2BIT);
    }

    function timeIntervalDestinationScopeCalldata(Policy calldata policy) internal pure returns (TimeIntervalScope) {
        uint256 scopes = (policy.config.packed >> SHIFT_TIME_SCOPES) & MASK_6BIT;
        return TimeIntervalScope((scopes >> 4) & MASK_2BIT);
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
