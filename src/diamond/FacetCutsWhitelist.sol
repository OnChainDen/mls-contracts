// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IFacetCutsWhitelist } from "./interfaces/IFacetCutsWhitelist.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract FacetCutsWhitelist is IFacetCutsWhitelist, Ownable {
    // Storage for whitelisted facet sets by contract type and set ID
    mapping(ContractType => mapping(uint256 => WhitelistedFacetSet)) private whitelistedSets;

    // Counter for generating unique set IDs per contract type
    mapping(ContractType => uint256) private nextSetId;

    constructor(address initialOwner) Ownable(initialOwner) { }

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
        onlyOwner
        returns (uint256 setId)
    {
        require(facetAddresses.length == functionSelectors.length, "FacetCutsWhitelist: Array length mismatch");
        require(facetAddresses.length > 0, "FacetCutsWhitelist: Empty facet set");

        setId = nextSetId[contractType]++;
        WhitelistedFacetSet storage set = whitelistedSets[contractType][setId];

        // Mark the set as active
        set.isActive = true;

        // Store all facet addresses
        for (uint256 i = 0; i < facetAddresses.length; i++) {
            address facetAddress = facetAddresses[i];
            require(facetAddress != address(0), "FacetCutsWhitelist: Zero address facet");

            set.facetAddresses.push(facetAddress);

            // Store function selectors for this facet
            bytes4[] memory selectors = functionSelectors[i];
            require(selectors.length > 0, "FacetCutsWhitelist: Empty selectors for facet");

            for (uint256 j = 0; j < selectors.length; j++) {
                set.facetFunctionSelectors[facetAddress].push(selectors[j]);
            }
        }

        emit FacetSetWhitelisted(contractType, setId, facetAddresses);
    }

    /**
     * @notice Deactivate a whitelisted facet set
     * @param contractType The type of contract (Account or Organization)
     * @param setId The identifier of the set to deactivate
     */
    function deactivateFacetSet(ContractType contractType, uint256 setId) external onlyOwner {
        require(whitelistedSets[contractType][setId].isActive, "FacetCutsWhitelist: Set not active");
        whitelistedSets[contractType][setId].isActive = false;
        emit FacetSetDeactivated(contractType, setId);
    }

    /**
     * @notice Validate that a diamond's current facets match a whitelisted set exactly
     * @param contractType The type of contract being validated
     * @param setId The identifier of the whitelisted set to validate against
     * @param facetAddresses Current facet addresses in the diamond
     * @param functionSelectors Current function selectors for each facet
     * @return isValid Whether the current facets match the whitelisted set exactly
     */
    function validateFacetSet(
        ContractType contractType,
        uint256 setId,
        address[] calldata facetAddresses,
        bytes4[][] calldata functionSelectors
    )
        external
        view
        returns (bool isValid)
    {
        require(facetAddresses.length == functionSelectors.length, "FacetCutsWhitelist: Array length mismatch");

        WhitelistedFacetSet storage whitelistedSet = whitelistedSets[contractType][setId];

        // Check if the set exists and is active
        if (!whitelistedSet.isActive) {
            return false;
        }

        // Check if the number of facets matches
        if (facetAddresses.length != whitelistedSet.facetAddresses.length) {
            return false;
        }

        // For each current facet, check if it exists in the whitelist with exact selectors
        for (uint256 i = 0; i < facetAddresses.length; ++i) {
            address facetAddress = facetAddresses[i];
            bytes4[] memory currentSelectors = functionSelectors[i];
            bytes4[] storage whitelistedSelectors = whitelistedSet.facetFunctionSelectors[facetAddress];

            // Check if this facet exists in the whitelist
            if (whitelistedSelectors.length == 0) {
                return false;
            }

            // Check if all selectors match (order doesn't matter)
            if (!_arraysContainSameElements(currentSelectors, whitelistedSelectors)) {
                return false;
            }
        }

        // Verify that each whitelisted facet is present in current facets
        for (uint256 i = 0; i < whitelistedSet.facetAddresses.length; ++i) {
            address whitelistedFacet = whitelistedSet.facetAddresses[i];
            bool found = false;

            for (uint256 j = 0; j < facetAddresses.length; ++j) {
                if (facetAddresses[j] == whitelistedFacet) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Check if a facet set is active
     * @param contractType The type of contract
     * @param setId The identifier of the set
     * @return isActive Whether the set is active
     */
    function isFacetSetActive(ContractType contractType, uint256 setId) external view returns (bool isActive) {
        return whitelistedSets[contractType][setId].isActive;
    }

    /**
     * @notice Get the next set ID for a contract type
     * @param contractType The type of contract
     * @return The next set ID that will be assigned
     */
    function getNextSetId(ContractType contractType) external view returns (uint256) {
        return nextSetId[contractType];
    }

    /**
     * @notice Get facet addresses for a whitelisted set
     * @param contractType The type of contract
     * @param setId The identifier of the set
     * @return facetAddresses Array of facet addresses in the set
     */
    function getWhitelistedFacetAddresses(
        ContractType contractType,
        uint256 setId
    )
        external
        view
        returns (address[] memory facetAddresses)
    {
        return whitelistedSets[contractType][setId].facetAddresses;
    }

    /**
     * @notice Get function selectors for a specific facet in a whitelisted set
     * @param contractType The type of contract
     * @param setId The identifier of the set
     * @param facetAddress The address of the facet
     * @return selectors Array of function selectors for the facet
     */
    function getWhitelistedFacetSelectors(
        ContractType contractType,
        uint256 setId,
        address facetAddress
    )
        external
        view
        returns (bytes4[] memory selectors)
    {
        return whitelistedSets[contractType][setId].facetFunctionSelectors[facetAddress];
    }

    /**
     * @notice Helper function to check if two arrays contain the same elements (order doesn't matter)
     * @param array1 First array
     * @param array2 Second array
     * @return Whether the arrays contain the same elements
     */
    function _arraysContainSameElements(bytes4[] memory array1, bytes4[] storage array2) private view returns (bool) {
        if (array1.length != array2.length) {
            return false;
        }

        // For each element in array1, check if it exists in array2
        for (uint256 i = 0; i < array1.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < array2.length; j++) {
                if (array1[i] == array2[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }

        return true;
    }
}
