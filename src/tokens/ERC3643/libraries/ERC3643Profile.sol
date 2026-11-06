// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ERC3643Profile
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Generated admission data for the reviewed immutable token profile.
/// @dev Only initialization code imports this file. Regenerate with script/erc3643-profile.sh --update.
library ERC3643Profile {
    bytes32 internal constant HOST_CODEHASH = 0x9e321300fcd84703dfb5f8a8e71bfd539508afa280019d99007582b1d643ca47;
    bytes32 internal constant INPUT_HASH = 0xdf3140d7becb1a782041e1e16182eeb3e8505348cbb911d6eb09d654cd3ecc59;
    uint256 internal constant REQUIRED_MASK = 1023;
    uint256 internal constant TEMPORARY_INDEX = 10;

    function expected(bytes32 hash) internal pure returns (uint256, bytes memory) {
        // ERC3643
        if (hash == 0x566193c2e52e983687c2bec6dd6327015bbf0c59bd29c61b247679ade99269bd) {
            return (
                0,
                hex"dd62ed3e095ea7b370a082314a6cc67742a47abcfc7e5fa8685731071a7af37988d695b24710362d9dc29fac6290865d313ce5679fc1d0e7125c4a33158b1a57134e18f4e583983640c10f1906fdde03aba637058456cb595c975abb9285948ac69c09cff8981789cbf3f861c47f00273d1ddc5bb84c824695d89b4118160ddda9059cbb23b872dd1fe56f7d3f4ba83a54fd4d50"
            );
        }
        // ERC3643AgentRole
        if (hash == 0x62dc24601bb6e2bdf7a70f0c9c7d51795cc85aa6a1139b4210a6f895d8548079) {
            return (1, hex"84e798421ffbb06497a6278e");
        }
        // ERC3643IdentityRegistry
        if (hash == 0xdae748e3005f22923a0f6d6233476bf10b8601cac89f19886ef384a3904744ba) {
            return (
                2,
                hex"653dc9f15dbe47e8a8d29d1df0eb5e54f11abfd87e42683bb9209e33b4f3fcb7454a03e0670af6a926d941aee744d7893b3e12f43b239a7f8e098ca1"
            );
        }
        // ERC3643IdentityRegistryStorage
        if (hash == 0xb6f61e6ef1fd07db0151f68881da91d67cb1458f37b9fab0b66478427170e160) {
            return (3, hex"a53410dd690a49f9bf9eb959e805cf869f3418d5cf191bcd7988d3a5727e13bc97a012f7");
        }
        // ERC3643TrustedIssuersRegistry
        if (hash == 0xdd8bad5548e28aecbd9ca8d9b09f1d8c76f2757b1f3adeaa52bcc3aa2e956ba9) {
            return (4, hex"9f63ea98c28fb278d9dd24c552c111d134a89987ef2ed1a4b93d28eb04bc7e84");
        }
        // ERC3643ClaimTopicsRegistry
        if (hash == 0x4440b2375523962d517062d5831c0f40d22c530bccdb8f1123602b7a4d076c89) {
            return (5, hex"c7b22551df09d60408297846");
        }
        // ERC3643Compliance
        if (hash == 0x247b6af689384d7c6e4db9c59e644b50e8ca7868518f217fd5906c0485465734) {
            return (6, hex"3ff5aa02e46638e65f8dead38d2ea7726a3edf288baf29b440db3b50");
        }
        // OwnableFacet
        if (hash == 0x160ef74251c526892ed798aa5df23c7b3cb17288346c687717f14c582a08648f) {
            return (7, hex"54d1f13df04e283e8da5cb5bfee81cf4715018a625692962f2fde38b");
        }
        // ERC165Facet
        if (hash == 0xf12558854f384dfea0918955b7e68ee9499f232c143dcfc0e2e600a9557d36fa) return (8, hex"01ffc9a7");
        // DiamondLoupeFacet
        if (hash == 0x2a9b56e940584f162b3783ee2a46ca0a9c073dd16f51c9d2d664c459f078cdc1) {
            return (9, hex"cdffacc652ef6b2cadfca15e7a0ed627");
        }
        // ERC20TemporaryApproval
        if (hash == 0x55161ef35c12984abfbd4dd640f2528701831ed04f50dfd665a50c1fe4d8a681) return (10, hex"42232a4c");
        return (type(uint256).max, hex"");
    }
}
