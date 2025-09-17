// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFacetCutsWhitelist {
    enum ContractType {
        Account,
        Organization
    }

    struct WhitelistedFacetSet {
        // Map from facet address to function selectors for that facet
        mapping(address => bytes4[]) facetFunctionSelectors;
        // Array of all facet addresses in this set
        address[] facetAddresses;
        // Whether this set is active
        bool isActive;
    }

    event FacetSetWhitelisted(ContractType contractType, uint256 setId, address[] facetAddresses);
    event FacetSetDeactivated(ContractType contractType, uint256 setId);

    /**
     * @notice Add a new whitelisted facet set for a contract type
     * @param contractType The type of contract (Account or Organization)
     * @param facetAddresses Array of facet addresses in this set
     * @param functionSelectors Array of arrays, each containing function selectors for corresponding facet
     * @return setId The unique identifier for this facet set
     */
    function addWhitelistedFacetSet(
        ContractType contractType,
        address[] calldata facetAddresses,
        bytes4[][] calldata functionSelectors
    )
        external
        returns (uint256 setId);

    /**
     * @notice Deactivate a whitelisted facet set
     * @param contractType The type of contract (Account or Organization)
     * @param setId The identifier of the set to deactivate
     */
    function deactivateFacetSet(ContractType contractType, uint256 setId) external;

    /**
     * @notice Validate that a diamond's current facets match a whitelisted set exactly
     * @param contractType The type of contract being validated
     * @param setId The identifier of the whitelisted set to validate against
     * @param currentFacetAddresses Current facet addresses in the diamond
     * @param currentFunctionSelectors Current function selectors for each facet
     * @return isValid Whether the current facets match the whitelisted set exactly
     */
    function validateFacetSet(
        ContractType contractType,
        uint256 setId,
        address[] calldata currentFacetAddresses,
        bytes4[][] calldata currentFunctionSelectors
    )
        external
        view
        returns (bool isValid);

    /**
     * @notice Check if a facet set is active
     * @param contractType The type of contract
     * @param setId The identifier of the set
     * @return isActive Whether the set is active
     */
    function isFacetSetActive(ContractType contractType, uint256 setId) external view returns (bool isActive);
}
