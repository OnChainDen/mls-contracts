// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../account/OnchainCustodyAccountDiamond.sol";
import "../../account/AccountInit.sol";
import "../../diamond/interfaces/IDiamondCut.sol";
import "../../diamond/Diamond.sol";
import { IAdminFacet, AdminOperationType } from "../../interfaces/IAdminFacet.sol";

/**
 * @title Organization Account Factory Facet
 * @notice Handles creation of account diamonds with admin authorization
 * @author Den Technologies Inc
 */
contract OrganizationAccountFactoryFacet {
    /**
     * @notice Emitted when a new account diamond is deployed
     * @param accountAddress The address of the deployed account diamond
     * @param organizationAddress The address of the organization that deployed it
     * @param salt The salt used for CREATE2 deployment
     */
    event AccountDeployed(address indexed accountAddress, address indexed organizationAddress, bytes32 indexed salt);

    /**
     * @notice Error thrown when deployment fails
     */
    error AccountDeploymentFailed();

    /**
     * @notice Error thrown when the deployed address does not match the computed address
     */
    error AccountDeploymentAddressMismatch();

    /**
     * @notice Error thrown when account initialization fails
     */
    error AccountInitializationFailed();

    /**
     * @notice Deploys a new OnchainCustodyAccountDiamond at a deterministic address
     * @dev Uses CREATE2 to ensure the same address across different chains
     * @dev Requires admin authorization through signatures
     * @param create2Salt The salt for CREATE2 deployment
     * @param _diamondCut The initial diamond cuts to apply during account deployment
     * @param whitelistSetId The ID of the whitelisted facet set to validate against
     * @param accountInit The AccountInit contract address for initialization
     * @param adminSignatureSalt A user-provided salt for admin nonce computation
     * @param signatures The signatures from admin authorizing this operation
     * @return accountAddress The address of the deployed account diamond
     */
    function deployAccount(
        bytes32 create2Salt,
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _facetWhitelistAddress,
        uint256 whitelistSetId,
        address accountInit,
        uint256 adminSignatureSalt,
        bytes memory signatures
    )
        external
        returns (address accountAddress)
    {
        // Validate admin authorization for account deployment
        bytes memory operationData =
            abi.encode(create2Salt, keccak256(abi.encode(_diamondCut)), accountInit, whitelistSetId);

        IAdminFacet(address(this)).validateAdminAuthorization(
            AdminOperationType.DeployAccount, operationData, adminSignatureSalt, signatures
        );

        // Deploy the account diamond using CREATE2
        bytes memory bytecode = abi.encodePacked(
            type(OnchainCustodyAccountDiamond).creationCode,
            abi.encode(_diamondCut, address(this), _facetWhitelistAddress, whitelistSetId)
        );

        assembly {
            accountAddress := create2(0, add(bytecode, 0x20), mload(bytecode), create2Salt)
        }

        // Check if deployment was successful
        if (accountAddress == address(0)) {
            revert AccountDeploymentFailed();
        }

        // Check if the deployed address matches the computed address
        if (accountAddress != computeAccountAddress(create2Salt, _diamondCut, _facetWhitelistAddress, whitelistSetId)) {
            revert AccountDeploymentAddressMismatch();
        }

        emit AccountDeployed(accountAddress, address(this), create2Salt);
    }

    /**
     * @notice Computes the address where an account diamond would be deployed
     * @param salt The salt for CREATE2 deployment
     * @param _diamondCut The initial diamond cuts to apply during deployment
     * @param whitelistSetId The ID of the whitelisted facet set to validate against
     * @return The computed address
     */
    function computeAccountAddress(
        bytes32 salt,
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _facetWhitelistAddress,
        uint256 whitelistSetId
    )
        public
        view
        returns (address)
    {
        bytes memory bytecode = abi.encodePacked(
            type(OnchainCustodyAccountDiamond).creationCode,
            abi.encode(_diamondCut, address(this), _facetWhitelistAddress, whitelistSetId)
        );

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));

        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Gets the organization address (this contract)
     * @return The organization address
     */
    function getOrganizationAddress() external view returns (address) {
        return address(this);
    }
}
