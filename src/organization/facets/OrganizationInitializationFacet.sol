// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../diamond/libraries/LibDiamond.sol";
import "../../diamond/interfaces/IDiamondCut.sol";
import "../OrganizationStorage.sol";
import "../../interfaces/IAdminFacet.sol";

/**
 * @title Organization Initialization Facet
 * @notice Handles post-deployment initialization of OrganizationDiamond contracts
 * @author Den Technologies Inc
 */
contract OrganizationInitializationFacet {
    /**
     * @notice Emitted when organization is successfully initialized
     * @param adminType The admin type set during initialization
     * @param adminAddresses The admin addresses set during initialization
     * @param guardian The guardian address set during initialization
     */
    event OrganizationInitialized(OrganizationStorage.AdminType adminType, address[] adminAddresses, address guardian);

    /**
     * @notice Error thrown when caller is not the authorized deployer
     */
    error UnauthorizedDeployer();

    /**
     * @notice Error thrown when organization is already initialized
     */
    error AlreadyInitialized();

    /**
     * @notice Error thrown when invalid admin configuration is provided
     */
    error InvalidAdminConfiguration();

    /**
     * @notice Error thrown when diamond cut fails
     */
    error DiamondCutFailed();

    /**
     * @notice Initializes the organization diamond with facets and admin configuration
     * @dev Can only be called by the deployer address set during diamond construction
     * @param _diamondCut Array of facet cuts to apply to the diamond
     * @param adminType Type of admin (Member or Group)
     * @param adminAddresses Array of addresses to be added as admin members
     * @param votingThreshold Voting threshold (only used for Group admin type)
     * @param guardian Guardian address for the organization
     */
    function initialize(
        IDiamondCut.FacetCut[] memory _diamondCut,
        OrganizationStorage.AdminType adminType,
        address[] memory adminAddresses,
        uint256 votingThreshold,
        address guardian
    )
        external
    {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Only the authorized deployer can initialize
        if (msg.sender != l.deployerAddress) {
            revert UnauthorizedDeployer();
        }

        // Check if already initialized
        if (isInitialized()) {
            revert AlreadyInitialized();
        }

        // Validate admin configuration
        if (adminAddresses.length == 0) {
            revert InvalidAdminConfiguration();
        }

        if (adminType == OrganizationStorage.AdminType.Group && votingThreshold == 0) {
            revert InvalidAdminConfiguration();
        }

        if (adminType == OrganizationStorage.AdminType.Member && adminAddresses.length > 1) {
            revert InvalidAdminConfiguration();
        }

        // Apply diamond cuts using LibDiamond (internal function, no admin validation needed)
        if (_diamondCut.length > 0) {
            LibDiamond.diamondCut(_diamondCut, address(0), new bytes(0));
        }

        // Set admin configuration - create members and optionally create group
        _setAdminConfiguration(adminType, adminAddresses, votingThreshold);

        // Set guardian
        l.guardian = guardian;

        emit OrganizationInitialized(adminType, adminAddresses, guardian);
    }

    /**
     * @notice Sets the admin configuration by creating members and optionally a group
     * @param adminType Type of admin (Member or Group)
     * @param adminAddresses Array of addresses to be added as admin members
     * @param votingThreshold Voting threshold for group admins
     * @return adminId The ID of the admin (member ID or group ID)
     */
    function _setAdminConfiguration(
        OrganizationStorage.AdminType adminType,
        address[] memory adminAddresses,
        uint256 votingThreshold
    )
        internal
        returns (uint8 adminId)
    {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Case: Individual admin
        if (adminType == OrganizationStorage.AdminType.Member) {
            // Validate admin address
            if (adminAddresses[0] == address(0)) {
                revert InvalidAdminConfiguration();
            }

            // Add member to mappings
            l.memberIdToAddress[1] = adminAddresses[0];
            l.addressToMemberId[adminAddresses[0]] = 1;

            // Initialize the member and group counters
            l.nextMemberId = 2;
            l.nextGroupId = 1;

            // Set admin permission
            l.adminPermission =
                OrganizationStorage.AdminPermission({ adminType: adminType, adminId: 1, votingThreshold: 0 });
        }
        // Case: Group admin
        else {
            // Create a group with all members
            l.groupIdToExists[1] = true;
            l.groupIdToMemberCount[1] = uint256(adminAddresses.length);

            // Initialize the member and group counters
            l.nextMemberId = uint8(adminAddresses.length + 1);
            l.nextGroupId = 2;

            // Create members for all admin addresses
            for (uint256 i = 0; i < adminAddresses.length; ++i) {
                // Validate admin address
                if (adminAddresses[i] == address(0)) {
                    revert InvalidAdminConfiguration();
                }

                uint8 memberId = uint8(i + 1);

                // Add member to mappings
                l.memberIdToAddress[memberId] = adminAddresses[i];
                l.addressToMemberId[adminAddresses[i]] = memberId;
                l.groupIdToMemberIdToInGroup[1][memberId] = true;
            }

            // Set admin permission
            l.adminPermission = OrganizationStorage.AdminPermission({
                adminType: adminType,
                adminId: 1,
                votingThreshold: votingThreshold
            });
        }
    }

    /**
     * @notice Gets the deployer address from diamond storage
     * @return The deployer address
     */
    function getDeployerAddress() external view returns (address) {
        return OrganizationStorage.layout().deployerAddress;
    }

    /**
     * @notice Checks if the organization has been initialized
     * @return True if initialized, false otherwise
     */
    function isInitialized() public view returns (bool) {
        return OrganizationStorage.layout().adminPermission.adminId != 0;
    }
}
