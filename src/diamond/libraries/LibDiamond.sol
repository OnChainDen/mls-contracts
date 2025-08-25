// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Author: Nick Mudge
 * EIP-2535 Diamond Standard: https://eips.ethereum.org/EIPS/eip-2535
 *
 * Modified for Solidity ^0.8.24 and enhanced with guardian protection
 */
import "../interfaces/IDiamondCut.sol";
import "../../storage/OrganizationStorage.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../../libraries/SignatureUtils.sol";

library LibDiamond {
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    struct FacetAddressAndPosition {
        address facetAddress;
        uint16 functionSelectorPosition; // position in facetFunctionSelectors.functionSelectors array
    }

    struct FacetFunctionSelectors {
        bytes4[] functionSelectors;
        uint16 facetAddressPosition; // position of facetAddress in facetAddresses array
    }

    struct DiamondStorage {
        // maps function selector to the facet address and
        // the position of the selector in the facetFunctionSelectors.selectors array
        mapping(bytes4 => FacetAddressAndPosition) selectorToFacetAndPosition;
        // maps facet addresses to function selectors
        mapping(address => FacetFunctionSelectors) facetFunctionSelectors;
        // facet addresses
        address[] facetAddresses;
        // Used to query if a contract implements an interface.
        // Used to implement ERC-165.
        mapping(bytes4 => bool) supportedInterfaces;
        // owner of the contract (for compatibility, but guardian protection takes precedence)
        address contractOwner;
    }

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setContractOwner(address _newOwner) internal {
        DiamondStorage storage ds = diamondStorage();
        address previousOwner = ds.contractOwner;
        ds.contractOwner = _newOwner;
        emit OwnershipTransferred(previousOwner, _newOwner);
    }

    function contractOwner() internal view returns (address contractOwner_) {
        contractOwner_ = diamondStorage().contractOwner;
    }

    function enforceIsContractOwner() internal view {
        require(msg.sender == diamondStorage().contractOwner, "LibDiamond: Must be contract owner");
    }

    /**
     * @notice Enforces that the caller is the guardian address
     */
    function enforceIsGuardian() internal view {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();
        require(msg.sender == l.guardian, "LibDiamond: Must be guardian");
    }

    /**
     * @notice Validates admin authorization for diamond cutting operations
     * @param operationData The ABI-encoded operation data
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection
     * @param signatures The signatures from admin(s) authorizing this operation
     */
    function validateAdminAuthorization(
        bytes memory operationData,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        internal
    {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Compute deterministic nonce from operation data and salt
        uint256 nonce = uint256(
            keccak256(
                abi.encode(
                    address(this), OrganizationStorage.AdminOperationType.DiamondCut, keccak256(operationData), salt
                )
            )
        );

        // Validate and check nonce for replay protection
        require(!l.usedAdminNonces[nonce], "LibDiamond: Admin nonce already used");

        // Validate chain ID for cross-chain replay protection
        require(chainId == block.chainid, "LibDiamond: Invalid chain ID");

        // Get operation hash for signature verification
        bytes32 operationHash =
            getAdminOperationHash(OrganizationStorage.AdminOperationType.DiamondCut, operationData, salt, chainId);

        bool isAuthorized = false;

        // Case: Admin is an individual member
        if (l.adminPermission.adminType == OrganizationStorage.AdminType.Member) {
            isAuthorized = hasValidAdminMemberSignature(signatures, operationHash);
        }
        // Case: Admin is a group
        else if (l.adminPermission.adminType == OrganizationStorage.AdminType.Group) {
            uint256 validSignatures = getValidAdminGroupSignatures(signatures, operationHash);
            isAuthorized = validSignatures >= l.adminPermission.votingThreshold;
        }

        // Revert if not authorized
        require(isAuthorized, "LibDiamond: Insufficient authorization for diamond cut");

        // Mark nonce as used after successful validation
        l.usedAdminNonces[nonce] = true;
    }

    /**
     * @notice Gets the operation hash for admin signature verification
     * @param operationType The type of admin operation
     * @param operationData The ABI-encoded operation data
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection
     * @return The operation hash
     */
    function getAdminOperationHash(
        OrganizationStorage.AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 chainId
    )
        internal
        view
        returns (bytes32)
    {
        return MessageHashUtils.toEthSignedMessageHash(
            keccak256(abi.encode(address(this), operationType, keccak256(operationData), salt, chainId))
        );
    }

    /**
     * @notice Checks if there is a valid signature from the admin member
     * @param signatures The signatures to verify
     * @param operationHash The hash of the admin operation
     * @return True if there is a valid signature from the admin member, false otherwise
     */
    function hasValidAdminMemberSignature(
        bytes memory signatures,
        bytes32 operationHash
    )
        internal
        view
        returns (bool)
    {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Check that we have exactly one signature (65 bytes: r: 32, s: 32, v: 1)
        if (signatures.length != 65) return false;

        // Extract the signature
        bytes memory signature = SignatureUtils.extractSignature(signatures, 0);

        // Get the admin member's address
        address adminMember = l.memberIdToAddress[l.adminPermission.adminId];

        // Verify signature using ERC-1271
        return SignatureChecker.isValidSignatureNow(adminMember, operationHash, signature);
    }

    /**
     * @notice Gets the number of valid signatures from admin group members
     * @param signatures The signatures to verify
     * @param operationHash The hash of the admin operation
     * @return The number of valid signatures from admin group members
     */
    function getValidAdminGroupSignatures(
        bytes memory signatures,
        bytes32 operationHash
    )
        internal
        view
        returns (uint256)
    {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Case: No signatures provided
        if (signatures.length == 0) return 0;

        // Each signature is 65 bytes (r: 32, s: 32, v: 1)
        uint8 signatureCount = uint8(signatures.length / 65);
        uint256 validSignatures = 0;

        // Track last signer to prevent duplicates (similar to Safe contracts)
        address lastSigner = address(0);

        // Iterate over signatures to count valid ones from admin group members
        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);

            // Try to recover signer from signature and operation hash
            bytes32 r;
            bytes32 s;
            uint8 v;

            assembly {
                r := mload(add(signature, 32))
                s := mload(add(signature, 64))
                v := byte(0, mload(add(signature, 96)))
            }

            if (v < 27) {
                v += 27;
            }

            if (v != 27 && v != 28) {
                continue;
            }

            address signer = ecrecover(operationHash, v, r, s);

            // Skip if signer is invalid
            if (signer == address(0)) continue;

            // Check for duplicate signers - signers must be unique and in ascending order
            // This prevents both duplicate signatures and replay attacks
            if (signer <= lastSigner) continue;

            // Update last signer for next iteration
            lastSigner = signer;

            // Verify the signature using ERC-1271 (this provides additional validation)
            if (!SignatureChecker.isValidSignatureNow(signer, operationHash, signature)) {
                continue;
            }

            // Check if signer is a member of the admin group
            if (l.groupIdToMemberIdToInGroup[l.adminPermission.adminId][l.addressToMemberId[signer]]) {
                ++validSignatures;
            }
        }

        return validSignatures;
    }

    event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);

    // Internal function version of diamondCut with guardian and admin protection
    function diamondCut(
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _init,
        bytes memory _calldata,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        internal
    {
        // Enforce guardian protection
        enforceIsGuardian();

        // Validate admin authorization
        bytes memory operationData = abi.encode(_diamondCut, _init, _calldata);
        validateAdminAuthorization(operationData, salt, chainId, signatures);

        // Perform the diamond cut
        for (uint256 facetIndex; facetIndex < _diamondCut.length; facetIndex++) {
            IDiamondCut.FacetCutAction action = _diamondCut[facetIndex].action;
            if (action == IDiamondCut.FacetCutAction.Add) {
                addFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            } else if (action == IDiamondCut.FacetCutAction.Replace) {
                replaceFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            } else if (action == IDiamondCut.FacetCutAction.Remove) {
                removeFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            } else {
                revert("LibDiamondCut: Incorrect FacetCutAction");
            }
        }
        emit DiamondCut(_diamondCut, _init, _calldata);
        initializeDiamondCut(_init, _calldata);
    }

    function addFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
        DiamondStorage storage ds = diamondStorage();
        require(_facetAddress != address(0), "LibDiamondCut: Add facet can't be address(0)");
        uint16 selectorPosition = uint16(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);
        // add new facet address if it does not exist
        if (selectorPosition == 0) {
            enforceHasContractCode(_facetAddress, "LibDiamondCut: New facet has no code");
            ds.facetFunctionSelectors[_facetAddress].facetAddressPosition = uint16(ds.facetAddresses.length);
            ds.facetAddresses.push(_facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            require(oldFacetAddress == address(0), "LibDiamondCut: Can't add function that already exists");
            ds.facetFunctionSelectors[_facetAddress].functionSelectors.push(selector);
            ds.selectorToFacetAndPosition[selector].facetAddress = _facetAddress;
            ds.selectorToFacetAndPosition[selector].functionSelectorPosition = selectorPosition;
            selectorPosition++;
        }
    }

    function replaceFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
        DiamondStorage storage ds = diamondStorage();
        require(_facetAddress != address(0), "LibDiamondCut: Add facet can't be address(0)");
        uint16 selectorPosition = uint16(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);
        // add new facet address if it does not exist
        if (selectorPosition == 0) {
            enforceHasContractCode(_facetAddress, "LibDiamondCut: New facet has no code");
            ds.facetFunctionSelectors[_facetAddress].facetAddressPosition = uint16(ds.facetAddresses.length);
            ds.facetAddresses.push(_facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            require(oldFacetAddress != _facetAddress, "LibDiamondCut: Can't replace function with same function");
            removeFunction(oldFacetAddress, selector);
            // add function
            ds.selectorToFacetAndPosition[selector].functionSelectorPosition = selectorPosition;
            ds.facetFunctionSelectors[_facetAddress].functionSelectors.push(selector);
            ds.selectorToFacetAndPosition[selector].facetAddress = _facetAddress;
            selectorPosition++;
        }
    }

    function removeFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
        DiamondStorage storage ds = diamondStorage();
        // if function does not exist then do nothing and return
        require(_facetAddress == address(0), "LibDiamondCut: Remove facet address must be address(0)");
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            removeFunction(oldFacetAddress, selector);
        }
    }

    function removeFunction(address _facetAddress, bytes4 _selector) internal {
        DiamondStorage storage ds = diamondStorage();
        require(_facetAddress != address(0), "LibDiamondCut: Can't remove function that doesn't exist");
        // an immutable function is a function defined directly in a diamond
        require(_facetAddress != address(this), "LibDiamondCut: Can't remove immutable function");
        // replace selector with last selector, then delete last selector
        uint256 selectorPosition = ds.selectorToFacetAndPosition[_selector].functionSelectorPosition;
        uint256 lastSelectorPosition = ds.facetFunctionSelectors[_facetAddress].functionSelectors.length - 1;
        // if not the same then replace _selector with lastSelector
        if (selectorPosition != lastSelectorPosition) {
            bytes4 lastSelector = ds.facetFunctionSelectors[_facetAddress].functionSelectors[lastSelectorPosition];
            ds.facetFunctionSelectors[_facetAddress].functionSelectors[selectorPosition] = lastSelector;
            ds.selectorToFacetAndPosition[lastSelector].functionSelectorPosition = uint16(selectorPosition);
        }
        // delete the last selector
        ds.facetFunctionSelectors[_facetAddress].functionSelectors.pop();
        delete ds.selectorToFacetAndPosition[_selector];

        // if no more selectors for facet address then delete the facet address
        if (lastSelectorPosition == 0) {
            // replace facet address with last facet address and delete last facet address
            uint256 lastFacetAddressPosition = ds.facetAddresses.length - 1;
            uint256 facetAddressPosition = ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;
            if (facetAddressPosition != lastFacetAddressPosition) {
                address lastFacetAddress = ds.facetAddresses[lastFacetAddressPosition];
                ds.facetAddresses[facetAddressPosition] = lastFacetAddress;
                ds.facetFunctionSelectors[lastFacetAddress].facetAddressPosition = uint16(facetAddressPosition);
            }
            ds.facetAddresses.pop();
            delete ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;
        }
    }

    function initializeDiamondCut(address _init, bytes memory _calldata) internal {
        if (_init == address(0)) {
            require(_calldata.length == 0, "LibDiamondCut: _init is address(0) but_calldata is not empty");
        } else {
            require(_calldata.length > 0, "LibDiamondCut: _calldata is empty but _init is not address(0)");
            if (_init != address(this)) {
                enforceHasContractCode(_init, "LibDiamondCut: _init address has no code");
            }
            (bool success, bytes memory error) = _init.delegatecall(_calldata);
            if (!success) {
                if (error.length > 0) {
                    // bubble up the error
                    revert(string(error));
                } else {
                    revert("LibDiamondCut: _init function reverted");
                }
            }
        }
    }

    function enforceHasContractCode(address _contract, string memory _errorMessage) internal view {
        uint256 contractSize;
        assembly {
            contractSize := extcodesize(_contract)
        }
        require(contractSize > 0, _errorMessage);
    }
}
