// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice A canonical final owner expectation, independent of recipe data and the materializer.
struct ExpectedRecipeRoute {
    bytes4 selector;
    string owner;
}

/// @title RecipeSeamExpectations
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Fixed source-reviewed selector owners for all 21 canonical seam groups, including inherited ENS.
/// @dev Keyed by the test's explicit recipe context, never by the observed facet set or spec.allowedOwners.
///      Changing a cut and its declared permitted owner together must still fail these expectations.
///      The 12 seam builders have 47 distinct recipe/selector pairs. ENS inherits the vault's 16 pairs;
///      repeated exclusions of one selector from different source facets share its single final owner.
library RecipeSeamExpectations {
    /// @notice Returns ordinary selector seams only; canonical recipes without seams return an empty array.
    function forRecipe(string memory recipe) internal pure returns (ExpectedRecipeRoute[] memory routes) {
        bytes32 name = keccak256(bytes(recipe));
        if (name == keccak256("DeployGovernedVault") || name == keccak256("DeployGovernedVaultENS")) {
            return _governedVault();
        }
        if (name == keccak256("DeployERC4626")) return _single("decimals()", "ERC4626");
        if (name == keccak256("DeployERC20Wrapper")) return _single("decimals()", "ERC20Wrapper");
        if (name == keccak256("DeployERC721URIStorage")) return _single("tokenURI(uint256)", "ERC721URIStorage");
        if (name == keccak256("DeployERC1155URIStorage")) return _single("uri(uint256)", "ERC1155URIStorage");
        if (name == keccak256("DeployERC20Pausable")) return _erc20Movement("ERC20Pausable", false);
        if (name == keccak256("DeployERC20Votes")) return _erc20Movement("ERC20Votes", true);
        if (name == keccak256("DeployERC721Pausable")) return _erc721Movement("ERC721Pausable", false);
        if (name == keccak256("DeployERC721Enumerable")) return _erc721Movement("ERC721Enumerable", false);
        if (name == keccak256("DeployERC721Votes")) return _erc721Movement("ERC721Votes", true);
        if (name == keccak256("DeployERC1155Pausable")) {
            routes = new ExpectedRecipeRoute[](2);
            routes[0] = _route("safeTransferFrom(address,address,uint256,uint256,bytes)", "ERC1155Pausable");
            routes[1] = _route("safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)", "ERC1155Pausable");
            return routes;
        }
        if (name == keccak256("DeployVaultCore")) {
            routes = new ExpectedRecipeRoute[](8);
            routes[0] = _route("decimals()", "ERC4626");
            routes[1] = _route("totalAssets()", "VaultCore");
            routes[2] = _route("maxDeposit(address)", "VaultCore");
            routes[3] = _route("maxMint(address)", "VaultCore");
            routes[4] = _route("deposit(uint256,address)", "VaultCore");
            routes[5] = _route("mint(uint256,address)", "VaultCore");
            routes[6] = _route("withdraw(uint256,address,address)", "VaultCore");
            routes[7] = _route("redeem(uint256,address,address)", "VaultCore");
            return routes;
        }
        return new ExpectedRecipeRoute[](0);
    }

    function _governedVault() private pure returns (ExpectedRecipeRoute[] memory routes) {
        routes = new ExpectedRecipeRoute[](16);
        routes[0] = _route("name()", "GovernedVault");
        routes[1] = _route("decimals()", "ERC4626");
        routes[2] = _route("transfer(address,uint256)", "GovernedVault");
        routes[3] = _route("transferFrom(address,address,uint256)", "GovernedVault");
        routes[4] = _route("totalAssets()", "VaultCore");
        routes[5] = _route("maxDeposit(address)", "VaultCore");
        routes[6] = _route("maxMint(address)", "VaultCore");
        routes[7] = _route("deposit(uint256,address)", "GovernedVault");
        routes[8] = _route("mint(uint256,address)", "GovernedVault");
        routes[9] = _route("withdraw(uint256,address,address)", "GovernedVault");
        routes[10] = _route("redeem(uint256,address,address)", "GovernedVault");
        routes[11] = _route("delegate(address)", "ERC20Votes");
        routes[12] = _route("delegateBySig(address,uint256,uint256,uint8,bytes32,bytes32)", "ERC20Votes");
        routes[13] = _route("clock()", "GovernedVault");
        routes[14] = _route("CLOCK_MODE()", "GovernedVault");
        routes[15] = _route("castVoteBySig(uint256,uint8,address,bytes)", "GovernedVault");
    }

    function _erc20Movement(string memory owner, bool votes)
        private
        pure
        returns (ExpectedRecipeRoute[] memory routes)
    {
        routes = new ExpectedRecipeRoute[](votes ? 4 : 2);
        routes[0] = _route("transfer(address,uint256)", owner);
        routes[1] = _route("transferFrom(address,address,uint256)", owner);
        if (votes) {
            routes[2] = _route("delegate(address)", owner);
            routes[3] = _route("delegateBySig(address,uint256,uint256,uint8,bytes32,bytes32)", owner);
        }
    }

    function _erc721Movement(string memory owner, bool votes)
        private
        pure
        returns (ExpectedRecipeRoute[] memory routes)
    {
        routes = new ExpectedRecipeRoute[](votes ? 5 : 3);
        routes[0] = _route("transferFrom(address,address,uint256)", owner);
        routes[1] = _route("safeTransferFrom(address,address,uint256)", owner);
        routes[2] = _route("safeTransferFrom(address,address,uint256,bytes)", owner);
        if (votes) {
            routes[3] = _route("delegate(address)", owner);
            routes[4] = _route("delegateBySig(address,uint256,uint256,uint8,bytes32,bytes32)", owner);
        }
    }

    function _single(string memory signature, string memory owner)
        private
        pure
        returns (ExpectedRecipeRoute[] memory routes)
    {
        routes = new ExpectedRecipeRoute[](1);
        routes[0] = _route(signature, owner);
    }

    function _route(string memory signature, string memory owner) private pure returns (ExpectedRecipeRoute memory) {
        return ExpectedRecipeRoute(bytes4(keccak256(bytes(signature))), owner);
    }
}
