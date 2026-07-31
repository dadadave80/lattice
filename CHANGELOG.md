# Changelog

## [0.4.0](https://github.com/dadadave80/lattice/compare/v0.3.0...v0.4.0) (2026-07-31)


### Features

* **cctp:** add hook receipt NFT demo ([339c490](https://github.com/dadadave80/lattice/commit/339c49089856eefb8561cd7d69db1855926481f2))
* **cctp:** add hook receipt NFT demo ([02681de](https://github.com/dadadave80/lattice/commit/02681de70111398c05944d94a7e1c357eaecede1))


### Documentation

* **cctp:** capture grant demo receipt relay ([f4faf99](https://github.com/dadadave80/lattice/commit/f4faf99ec498a23665964eb989f8a8011b5ca8f6))

## [0.3.0](https://github.com/dadadave80/lattice/compare/v0.2.0...v0.3.0) (2026-07-25)


### ⚠ BREAKING CHANGES

* rename LatticeDiamond to Lattice

### Features

* **demos:** deployment split, unified stack, round trip, interactive tester — CCTP demos runnable by anyone ([eb68012](https://github.com/dadadave80/lattice/commit/eb6801281a3d4b4755f5957a1f8f490431ffd6bd))
* **demos:** interactive tester — 'make demo' picks direction, amount, auth ([23dbd26](https://github.com/dadadave80/lattice/commit/23dbd26a2ffd496f2ee498860028204ccd13e4fc))
* **demos:** parallel balance reads + self-healing loop lock ([cdc9bc0](https://github.com/dadadave80/lattice/commit/cdc9bc02bd31b4b29134e26af8b87afb0503eb28))
* **demos:** parallel balance reads + self-healing loop lock ([989c8bc](https://github.com/dadadave80/lattice/commit/989c8bc451c90858ed46244a478bde3d856285cc))
* **demos:** split deployment from the CCTP demos — one stack serves both, auth for anyone ([03a7e50](https://github.com/dadadave80/lattice/commit/03a7e50050bfe8519a69421b971e82a8d0fd6996))
* **demos:** USDC round trip Arc &lt;-&gt; Base through Lattice diamonds both ways ([59a6f5e](https://github.com/dadadave80/lattice/commit/59a6f5e0f996dc89c9549b7f17145815148524e4))


### Bug Fixes

* **demos:** leg-aware closing banner for --legs back runs ([a8dd270](https://github.com/dadadave80/lattice/commit/a8dd2706b0d709ed19c9f8d0bf018cc68660bd63))
* **demos:** leg-aware closing banner for --legs back runs ([5533601](https://github.com/dadadave80/lattice/commit/5533601df0f447cc2d00de65021d748521111d7e))
* **demos:** roundtrip actor is always the signer; fund gates never wave a flaked read through ([4ba59e5](https://github.com/dadadave80/lattice/commit/4ba59e51cd5892235ae6309c5dbdd8fc76bccbb8))


### Refactors

* rename LatticeDiamond to Lattice ([7a666ce](https://github.com/dadadave80/lattice/commit/7a666ce22b081ad66c125d18e80dc1565340b686))


### Documentation

* add banner, update defi module list in README ([632cfee](https://github.com/dadadave80/lattice/commit/632cfee0b7ad1ec9cd7c6bbad0bea5336bd2469c))
* add banner, update defi module list, skip CI on docs-only PRs ([31ea6d7](https://github.com/dadadave80/lattice/commit/31ea6d7d348178e07475b8b8f83244f44dd178d6))
* **grants:** re-point hook-demo evidence at the 2026-07-20 rerun ([77c0a44](https://github.com/dadadave80/lattice/commit/77c0a44e4b519db71273e01d37d89d8ab6d0aa1c))
* **grants:** re-point hook-demo evidence at the 2026-07-20 rerun ([1e06ca7](https://github.com/dadadave80/lattice/commit/1e06ca70ef530bf45854c5d89114fb75143561d5))

## [0.2.0](https://github.com/dadadave80/lattice/compare/v0.1.0...v0.2.0) (2026-07-20)


### ⚠ BREAKING CHANGES

* Receive facet — bare-ETH acceptance moves from the proxy to a cut
* drop the four remaining security Init contracts — recipe-local inits
* Pausable modifiers + composable init — drop PausableInit
* transient ReentrancyGuard — Solady logic, mixin modifiers, no init
* Initializable mixin + parameterless preInitializer()
* migrate to diamond-lib v0.3.0 — LatticeDiamond + vendored InitializableLib

### Features

* **build:** KEYSTORE= mode — demo auth from the macOS Keychain ([bd30e57](https://github.com/dadadave80/lattice/commit/bd30e57fb522e35e970fc86ad8bed17db5ee7bbf))
* **crosschain:** Arc-hub CCTP demo — one Arc diamond bridging to Sepolia + Base Sepolia ([736bf42](https://github.com/dadadave80/lattice/commit/736bf42e3c1b8b7ac468f4c889683ec7b66ca872))
* **crosschain:** CCTP v2 hooks + maxFee guard on the bridge adapter ([74e8479](https://github.com/dadadave80/lattice/commit/74e84792fc617443feb811fc9ed5eba8c424872f))
* **crosschain:** CCTP v2 hooks + maxFee guard on the bridge adapter ([423a715](https://github.com/dadadave80/lattice/commit/423a71566ae4a12d2e957e53b276ec6fafca1a92))
* **crosschain:** derive the CCTP demo actor from the keystore + auto-detect --slow ([d0d33fd](https://github.com/dadadave80/lattice/commit/d0d33fdb80e3c2a44d86642a73cec5524fbdfbba))
* **crosschain:** derive the demo actor from the keystore + auto-detect --slow ([9544da1](https://github.com/dadadave80/lattice/commit/9544da104ae7c061768a76bb2dac8310816f79b3))
* **crosschain:** live CCTP v2 hook showcase — auto-credit vault ([07a8333](https://github.com/dadadave80/lattice/commit/07a8333ffa6986436703b355348f7a86ad114d28))
* **crosschain:** live CCTP v2 hook showcase — auto-credit vault on Base ([1ad4862](https://github.com/dadadave80/lattice/commit/1ad48626be647b73ebdf97bcb1dd5533679f12d9))
* **crosschain:** live CCTP v2 USDC demo — Sepolia→Arc & Sepolia→Base Sepolia ([f904c67](https://github.com/dadadave80/lattice/commit/f904c675fcdb3ba7b4c309e794f1e68dc0207c22))
* **crosschain:** live CCTP v2 USDC demo script + autonomous crank loop ([5fffa8c](https://github.com/dadadave80/lattice/commit/5fffa8c9bae7b2a545936eaeb3bbea18870b3ae4))
* **crosschain:** narrate the hook demo — make the invisible steps visible ([0648ac7](https://github.com/dadadave80/lattice/commit/0648ac7d684dfe70d3225b710b52e97ea3bf8e90))
* **crosschain:** narrate the hook demo — make the invisible steps visible ([f7fcdae](https://github.com/dadadave80/lattice/commit/f7fcdae53bbf330beb6109a6afd30c9ad5dd1898))
* **crosschain:** render setup progress as per-contract ✓/✗ with a verification spinner ([a500ef1](https://github.com/dadadave80/lattice/commit/a500ef1aa7cfc79d6f6ae426a0ffa66ca047bbed))
* **crosschain:** rework CCTP demo as an Arc-hub — one diamond bridging to Sepolia + Base Sepolia ([ed2f7b4](https://github.com/dadadave80/lattice/commit/ed2f7b4032c017f49640ef5f12668838bc617628))
* **crosschain:** stream per-contract setup progress in the hook demo ([01167dd](https://github.com/dadadave80/lattice/commit/01167dd78dc04394734f76baf8385d405a97241a))
* Initializable mixin + parameterless preInitializer() ([06d66d9](https://github.com/dadadave80/lattice/commit/06d66d90c95ac70f83700e95832fb693297007bd))
* migrate to diamond-lib v0.3.0 — LatticeDiamond + vendored InitializableLib ([e489cae](https://github.com/dadadave80/lattice/commit/e489caefb4b52541ec2b699d3b1135afff043bfc))
* Pausable modifiers + composable init — drop PausableInit ([61c0fdc](https://github.com/dadadave80/lattice/commit/61c0fdcae55b405ba22c41bad896727f8ddc4b47))
* Receive facet — bare-ETH acceptance moves from the proxy to a cut ([e032e82](https://github.com/dadadave80/lattice/commit/e032e82b47c31c6f5cbdcf1a6d137ff803bf0fc3))
* **release:** wire LatticeVersion as the single source of release truth ([2630141](https://github.com/dadadave80/lattice/commit/263014129af9852a7bf537dac66211680b9edb68))
* transient ReentrancyGuard — Solady logic, mixin modifiers, no init ([3de08a8](https://github.com/dadadave80/lattice/commit/3de08a857813b0f116833a67c7dd825a07d6300b))


### Bug Fixes

* **crosschain:** address review — Arc native-gas delivery threshold, idempotent burn, auth guard, journal fee policy ([b554997](https://github.com/dadadave80/lattice/commit/b55499703a65ddbf158882c500074b0a114fb303))
* **crosschain:** apply the 9 verified review findings to the demo UX PR ([8fc6cb5](https://github.com/dadadave80/lattice/commit/8fc6cb55d1ec406c861718c7d8d6fe3d443eb4ca))
* **crosschain:** CCTP demo loop — keystore-free status reads (--sender) + lane RPC preflight + gitignore .pw ([47adc21](https://github.com/dadadave80/lattice/commit/47adc21205e0d65bc2267cf534a0c4235a44fb9a))
* **crosschain:** drive the Arc burn via cast send — revm cannot execute Arc's native-USDC precompile ([2c82c78](https://github.com/dadadave80/lattice/commit/2c82c788c40cd627669df0fe5c509c8cc91ed9e5))
* **crosschain:** hook demo — prompt-free fund check + Sourcify-pinned verification ([0e6739c](https://github.com/dadadave80/lattice/commit/0e6739c81807dd18e70b18a6a9e58ef7e669ddd7))
* **crosschain:** keep CCTP demo status reads keystore-free ([e688a3f](https://github.com/dadadave80/lattice/commit/e688a3fbe2733688dc4513d0b1dc1c5521e17a08))
* **crosschain:** pass FORGE_AUTH to the hook demo's Arc balance read ([0d2e0e9](https://github.com/dadadave80/lattice/commit/0d2e0e9c63b62685d49cf19553f1fc69d8296e2a))
* **crosschain:** pin demo deploy verification to Sourcify ([3282c4a](https://github.com/dadadave80/lattice/commit/3282c4a2424a16c4df772cd005db50b85a78fce6))
* **crosschain:** render the REAL multichain output — chain headers, dispatch spinner, journal-sourced deploy listing ([914ad06](https://github.com/dadadave80/lattice/commit/914ad061e7ded45df17d0274c32498647a0715b5))
* **crosschain:** review — journal lifecycle, burn-adoption hardening, locking, doc truth ([1e8815c](https://github.com/dadadave80/lattice/commit/1e8815c26f217cb0156c9a7ca35e0a53febe84eb))
* **crosschain:** review — net-of-fee hook amount + mutation-hardened tests ([0d964b0](https://github.com/dadadave80/lattice/commit/0d964b0628d1e5cd8eba1df957b19af57508c23b))
* **crosschain:** status read uses --sender; preflight the lane RPC vars ([e47b856](https://github.com/dadadave80/lattice/commit/e47b8565e15dfafd3bbe172288fb2d9997d3e13c))
* **make:** deploy-local — explicit --tc and .env-free execution ([87c7fdd](https://github.com/dadadave80/lattice/commit/87c7fdd1d9fd2146a16abb3b7efc9e6fabe91b41))
* **make:** deploy-local — explicit --tc and .env-free execution ([941db39](https://github.com/dadadave80/lattice/commit/941db397e4fdea69a85f62279230ac811c622f4c))
* **make:** drop the /tmp workaround — .env keystore setting removed instead ([12c052d](https://github.com/dadadave80/lattice/commit/12c052dd481c88c06fde4624d7a13d5de38e396f))
* **release:** digit-free types on x-release-please annotated lines ([c640c0d](https://github.com/dadadave80/lattice/commit/c640c0d8478f902b0c21393856ee15227bd5115e))
* **release:** digit-free types on x-release-please annotated lines ([504c12f](https://github.com/dadadave80/lattice/commit/504c12feea88bfdccdb62b38d3e27e364c1aa76c))
* **release:** forgefmt disable-next-item on the digit-free annotated lines ([2b7965b](https://github.com/dadadave80/lattice/commit/2b7965b32ed8a3d714fd4c1dc4ca77e0aa373064))


### Refactors

* colocate module libs inside their vendor folders ([f7aa2a8](https://github.com/dadadave80/lattice/commit/f7aa2a8ac4d74d36f541c4002e37a1976184c406))
* **crosschain:** fund-check Arc balance via a broadcast-free forge read ([c47ab93](https://github.com/dadadave80/lattice/commit/c47ab93413fcea83398d5a371d039b7ffc59b96f))
* **crosschain:** group protocol adapters per vendor ([c731f9b](https://github.com/dadadave80/lattice/commit/c731f9b2f0cfcf5c5713d1ab3021a23b881ff532))
* drop the four remaining security Init contracts — recipe-local inits ([0c6c23e](https://github.com/dadadave80/lattice/commit/0c6c23ef90909417f342caad3fa7c0d3333bf6e9))
* **interfaces:** group vendored external interfaces per vendor ([49697ee](https://github.com/dadadave80/lattice/commit/49697ee98bf4e7c38b7214adac7676461575b7cc))
* **interfaces:** group vendored external interfaces per vendor ([2625033](https://github.com/dadadave80/lattice/commit/262503384df78e86e575673e8950c26edd189441))
* **oracles:** group oracle adapters per vendor ([aad2119](https://github.com/dadadave80/lattice/commit/aad2119e0da40f1b00b14e344d927eac6079fa33))
* rename DiamondFactory to LatticeFactory; promote factory + registry to src/ root ([706d815](https://github.com/dadadave80/lattice/commit/706d81541ff3a76beefe54c925f7c47218e3e778))
* rename DiamondFactory to LatticeFactory; promote factory + registry to src/ root ([ca785ab](https://github.com/dadadave80/lattice/commit/ca785abe8c6e56a29403eb678d908c31147a1692))


### Documentation

* **crosschain:** correct --slow rationale — the signer is 7702-delegated, not Arc ([ed20133](https://github.com/dadadave80/lattice/commit/ed201335fa1d91671abf04564a81c4ac60659a2c))
* **crosschain:** correct --slow rationale — the SIGNER is 7702-delegated, not Arc ([15c71d1](https://github.com/dadadave80/lattice/commit/15c71d1ff3cb13a4d65004a628b9b209132030bc))
* **crosschain:** fold in the delegation-accuracy fixes (supersedes [#143](https://github.com/dadadave80/lattice/issues/143)) ([0f80f55](https://github.com/dadadave80/lattice/commit/0f80f55e2a1238a78d79e8d0999728a52818fca2))
* **demo:** update stale .env keystore comment ([c15faba](https://github.com/dadadave80/lattice/commit/c15fabac8ad918b40272db54998bc803e5f76174))
* **grants:** Circle Arc application evidence — live CCTP demos, real-attestation fixture ([d981ad8](https://github.com/dadadave80/lattice/commit/d981ad8344e2aaba9e73c1a7c0620cb504868fbb))
* **grants:** Circle Arc application evidence — live demos, fixture, broadcast logs ([b98b22e](https://github.com/dadadave80/lattice/commit/b98b22eeb6914b07e09044b734bc1d304d4686f0))
* **grants:** re-point hook-demo evidence at the 2026-07-19 rerun ([f03eba2](https://github.com/dadadave80/lattice/commit/f03eba2e1b9071c6ed01e193548362173b0c2c44))
* **grants:** re-point hook-demo evidence at the 2026-07-19 rerun ([a606571](https://github.com/dadadave80/lattice/commit/a60657178fab9a35e62bb8c7389308c3499eeeff))
* **grants:** track only -latest broadcast evidence ([3d07ede](https://github.com/dadadave80/lattice/commit/3d07edec7ce25dec592725054153f46b51d69ae3))

## 0.1.0 (2026-07-14)


### Features

* **#118:** ERC-8153 exportSelectors + LatticeRegistry — FFI-free, deploy-once facets ([7351c6c](https://github.com/dadadave80/lattice/commit/7351c6c5618d399b3950d333852d06163c7cc893))
* **accounts:** add smart-account facets — ERC-4337/1271/7821 + ECDSA signer ([#56](https://github.com/dadadave80/lattice/issues/56) v1) ([259eb60](https://github.com/dadadave80/lattice/commit/259eb60ddf311b3be3d428263310cb90450c33ad))
* **accounts:** balance-diff session-key spend accounting ([#58](https://github.com/dadadave80/lattice/issues/58) follow-on) ([07293e7](https://github.com/dadadave80/lattice/commit/07293e7ce2e242a2eb4980136ea3e64b40cf0894))
* **accounts:** balance-diff session-key spend accounting ([#58](https://github.com/dadadave80/lattice/issues/58) follow-on) ([bd4abd1](https://github.com/dadadave80/lattice/commit/bd4abd1af3dc149f1b37db285a9e9323f4bc51c7))
* **accounts:** consume ERC-7579 fallback (type 3) handlers via AccountDiamond ([7e7cc81](https://github.com/dadadave80/lattice/commit/7e7cc81ded6242f02bff0f024395f6c15acdf1d6))
* **accounts:** consume ERC-7579 hook modules ([#58](https://github.com/dadadave80/lattice/issues/58) follow-on, 2 of 3) ([a167852](https://github.com/dadadave80/lattice/commit/a16785267cc820ce9d345e8ea6fb579625fe32c6))
* **accounts:** consume ERC-7579 hook modules ([#58](https://github.com/dadadave80/lattice/issues/58) follow-on, 2 of 3) ([5f4829b](https://github.com/dadadave80/lattice/commit/5f4829b8765d7dab17ec96faad8ce54ac057160a))
* **accounts:** consume ERC-7579 validator modules ([#58](https://github.com/dadadave80/lattice/issues/58) follow-on) ([096ac36](https://github.com/dadadave80/lattice/commit/096ac36cb7f8989f95695fc993a4542ab2339181))
* **accounts:** consume ERC-7579 validator modules ([#58](https://github.com/dadadave80/lattice/issues/58) follow-on) ([bd3c219](https://github.com/dadadave80/lattice/commit/bd3c2190bbe7deae57150d3364e13ff332461617))
* **accounts:** deterministic AccountFactory for counterfactual ERC-4337 deployment ([#58](https://github.com/dadadave80/lattice/issues/58) item 6) ([5b300f7](https://github.com/dadadave80/lattice/commit/5b300f72f9d7600f803e9b1832667e3cc0d2feb3))
* **accounts:** deterministic AccountFactory for counterfactual ERC-4337 deployment ([#58](https://github.com/dadadave80/lattice/issues/58) item 6) ([c031574](https://github.com/dadadave80/lattice/commit/c031574d00c30b1437b3fd5594be3c34982c0051))
* **accounts:** EIP-7702 delegate hardening — self-init, self-owner guard, signed onboarding ([#58](https://github.com/dadadave80/lattice/issues/58) item 7) ([1988b83](https://github.com/dadadave80/lattice/commit/1988b8323f1775976c94224ba6cf481b99f24861))
* **accounts:** ERC-6551 token-bound account facet ([#58](https://github.com/dadadave80/lattice/issues/58) item 8) ([0521d7b](https://github.com/dadadave80/lattice/commit/0521d7b1511b2976f82f4a688cfa509152fd320e))
* **accounts:** ERC-6551 token-bound account facet ([#58](https://github.com/dadadave80/lattice/issues/58) item 8) ([a56d9c2](https://github.com/dadadave80/lattice/commit/a56d9c2957c7e1ba36843a27cb7e7e60cdfe4a88))
* **accounts:** ERC-6900 AccountLoupe view facet ([#74](https://github.com/dadadave80/lattice/issues/74) sub-task 6) ([d7e10da](https://github.com/dadadave80/lattice/commit/d7e10da5a1a574d2631675752d047dbd139b6854))
* **accounts:** ERC-6900 AccountLoupe view facet ([#74](https://github.com/dadadave80/lattice/issues/74)) ([7485bde](https://github.com/dadadave80/lattice/commit/7485bde7c426dcbb5f0831065e6dc7bcaeb1a38c))
* **accounts:** ERC-6900 ERC-1271 signature validation ([#74](https://github.com/dadadave80/lattice/issues/74) sub-task 5) ([d896b14](https://github.com/dadadave80/lattice/commit/d896b1444f2c5cf25b05e158105025d1c85f4597))
* **accounts:** ERC-6900 ERC-1271 signature validation ([#74](https://github.com/dadadave80/lattice/issues/74)) ([2b30489](https://github.com/dadadave80/lattice/commit/2b304890ae4dd9094c5cfb64315ff851b923ed7d))
* **accounts:** ERC-6900 ERC-4337 userOp validation routing ([#74](https://github.com/dadadave80/lattice/issues/74) sub-task 4) ([3f81dad](https://github.com/dadadave80/lattice/commit/3f81dad9474895a54bafd1312c21eea5b6a48297))
* **accounts:** ERC-6900 ERC-4337 userOp validation routing ([#74](https://github.com/dadadave80/lattice/issues/74)) ([fb52336](https://github.com/dadadave80/lattice/commit/fb5233605e2834cbdfcbdedd8c5b94cfa37063da))
* **accounts:** ERC-6900 executor + runtime dispatch pipeline ([#74](https://github.com/dadadave80/lattice/issues/74) sub-task 3) ([c8cfb4c](https://github.com/dadadave80/lattice/commit/c8cfb4c11405173e6996a831b9d871f82c184f23))
* **accounts:** ERC-6900 executor + runtime dispatch pipeline ([#74](https://github.com/dadadave80/lattice/issues/74)) ([c607332](https://github.com/dadadave80/lattice/commit/c6073325fa1a21d04c2a31a12d8059f63ebc145e))
* **accounts:** ERC-6900 factory blueprint + init ([#74](https://github.com/dadadave80/lattice/issues/74) sub-task 7) ([8774bf1](https://github.com/dadadave80/lattice/commit/8774bf13bc923a26e95bbb33b3bb718d3ea0f54f))
* **accounts:** ERC-6900 factory blueprint + init ([#74](https://github.com/dadadave80/lattice/issues/74)) ([169f226](https://github.com/dadadave80/lattice/commit/169f22640eb1c2cbaa960c0b669493679dcf7d18))
* **accounts:** ERC-6900 module-manager storage lib + config facet ([#74](https://github.com/dadadave80/lattice/issues/74) sub-task 2) ([73c497c](https://github.com/dadadave80/lattice/commit/73c497c531eef6627697e13967bc4c47cc1ae67e))
* **accounts:** ERC-6900 module-manager storage lib + config facet ([#74](https://github.com/dadadave80/lattice/issues/74)) ([da131b5](https://github.com/dadadave80/lattice/commit/da131b50a13fcbee3bc200e739776237af3694a0))
* **accounts:** ERC-6900 reference modules + full e2e ([#74](https://github.com/dadadave80/lattice/issues/74) sub-task 8) ([caa91eb](https://github.com/dadadave80/lattice/commit/caa91ebfa0bf6ccae992fb774d05981deb3ddfd3))
* **accounts:** ERC-6900 reference modules + full e2e ([#74](https://github.com/dadadave80/lattice/issues/74)) ([978f399](https://github.com/dadadave80/lattice/commit/978f399314632189b1b1635796711a865759338e))
* **accounts:** ERC-7579 module management — executor modules + introspection ([#58](https://github.com/dadadave80/lattice/issues/58) item 2) ([4627bad](https://github.com/dadadave80/lattice/commit/4627bad456cae168f1acb7e02f3291bd7e6a7ba4))
* **accounts:** ERC-7579 module management — executor modules + introspection ([#58](https://github.com/dadadave80/lattice/issues/58) item 2) ([d18390f](https://github.com/dadadave80/lattice/commit/d18390f403ef8bb102e4a5e96f9a6ed12addf594))
* **accounts:** ERC-7739 defensive rehashing for ERC-1271 ([#58](https://github.com/dadadave80/lattice/issues/58) item 1) ([94ec8bd](https://github.com/dadadave80/lattice/commit/94ec8bdd744452d5395754ea1d3ef6d3279b4b61))
* **accounts:** ERC-7739 defensive rehashing for ERC-1271 ([#58](https://github.com/dadadave80/lattice/issues/58) item 1) ([f9908d8](https://github.com/dadadave80/lattice/commit/f9908d867a065c16f9a536ce85598499a858c09a))
* **accounts:** finalize default EntryPoint (v0.9) + live-fork integration test ([#58](https://github.com/dadadave80/lattice/issues/58) item 9) ([2598315](https://github.com/dadadave80/lattice/commit/25983150c76c79dcca2132f825320dca3f52fe46))
* **accounts:** finalize default EntryPoint (v0.9) + live-fork integration test ([#58](https://github.com/dadadave80/lattice/issues/58) item 9) ([0e0964c](https://github.com/dadadave80/lattice/commit/0e0964c8fdff948f73f876105b8148668aba53a1))
* **accounts:** P256 + WebAuthn passkey owners; rename SignerECDSA -&gt; AccountSigner ([#58](https://github.com/dadadave80/lattice/issues/58) item 3) ([7eb8582](https://github.com/dadadave80/lattice/commit/7eb858235e0c5876cd38fe06670baf469dc8e14e))
* **accounts:** P256 + WebAuthn passkey owners; rename SignerECDSA → AccountSigner ([#58](https://github.com/dadadave80/lattice/issues/58) item 3) ([379f26a](https://github.com/dadadave80/lattice/commit/379f26a7552265bc6da144257fb373ca8bfabbc2))
* **accounts:** session-key facet — scoped, expiring keys via signed-opData ([#58](https://github.com/dadadave80/lattice/issues/58) item 4) ([bc99bbd](https://github.com/dadadave80/lattice/commit/bc99bbd1baf9e54f353f21a4eccedb68e5517a28))
* **accounts:** session-key spend limits ([#58](https://github.com/dadadave80/lattice/issues/58) item 4 follow-on) ([758b626](https://github.com/dadadave80/lattice/commit/758b6269cc0ab1bb5ef6fcd2aeeb66471fe5439d))
* **accounts:** session-key spend limits ([#58](https://github.com/dadadave80/lattice/issues/58) item 4 follow-on) ([e4d9769](https://github.com/dadadave80/lattice/commit/e4d97693e3faca72ce33c6e11087f3dea5ff196e))
* **accounts:** signed-opData authorization + session keys for ERC-7821 ([#58](https://github.com/dadadave80/lattice/issues/58) items 5 & 4) ([861e518](https://github.com/dadadave80/lattice/commit/861e5189854c67259e7e5f6abfb98f461a82c4ac))
* **accounts:** signed-opData authorization for ERC-7821 executor ([#58](https://github.com/dadadave80/lattice/issues/58) item 5) ([73d6c51](https://github.com/dadadave80/lattice/commit/73d6c51257e0309911409eb152aad154c9678c42))
* **accounts:** smart-account facets — ERC-4337/1271/7821 + ECDSA signer ([#56](https://github.com/dadadave80/lattice/issues/56) v1) ([bb070bd](https://github.com/dadadave80/lattice/commit/bb070bda23c98284236c0614fb0361134c20bb2a))
* **accounts:** vendor ERC-6900 interfaces + packed-type lib ([#74](https://github.com/dadadave80/lattice/issues/74) sub-task 1) ([af61f55](https://github.com/dadadave80/lattice/commit/af61f552d5aaeb347eff067556d4dcc3698d4461))
* **accounts:** vendor ERC-6900 interfaces + packed-type lib ([#74](https://github.com/dadadave80/lattice/issues/74)) ([319a823](https://github.com/dadadave80/lattice/commit/319a8231e88485cadc4002e131a31779b03a788d))
* **accounts:** WebAuthn compact signature codec ([#58](https://github.com/dadadave80/lattice/issues/58) follow-on) ([2a0f0b5](https://github.com/dadadave80/lattice/commit/2a0f0b589323d4d615997d0c3daa87452bc23d7d))
* **accounts:** WebAuthn compact signature codec ([#58](https://github.com/dadadave80/lattice/issues/58) follow-on) ([a0839d9](https://github.com/dadadave80/lattice/commit/a0839d9f031c1f312d8b77086708f2c61d592cf5))
* **crosschain:** AcrossBridgeAdapter — intent/optimistic token bridge over SpokePool.deposit ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 8) ([8dd1e07](https://github.com/dadadave80/lattice/commit/8dd1e077b0cdcc8d486c7b0324204f65ae5b5a4e))
* **crosschain:** AcrossBridgeAdapter — intent/optimistic token bridge over SpokePool.deposit ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 8) ([2ae62cd](https://github.com/dadadave80/lattice/commit/2ae62cde66ba8f799605fa1ae1b5ecf967876bd9))
* **crosschain:** add Axelar ERC-7786 gateway adapter ([#27](https://github.com/dadadave80/lattice/issues/27)) ([d062136](https://github.com/dadadave80/lattice/commit/d062136f2244ce578024298047b7ec8e4d18805d))
* **crosschain:** add CCIP V2/CCV receiver to the gateway adapter ([#52](https://github.com/dadadave80/lattice/issues/52)) ([968be47](https://github.com/dadadave80/lattice/commit/968be47cabe6589d99a384615e58ec395a4a29d3))
* **crosschain:** add Chainlink CCIP ERC-7786 gateway adapter ([#52](https://github.com/dadadave80/lattice/issues/52)) ([9b277c8](https://github.com/dadadave80/lattice/commit/9b277c8b1827156dd0118ac6e32dd89b2ba814a9))
* **crosschain:** add Chainlink CCIP ERC-7786 gateway adapter ([#52](https://github.com/dadadave80/lattice/issues/52)) ([8720565](https://github.com/dadadave80/lattice/commit/87205651a9dae138271be369c690399a2aebb01e))
* **crosschain:** add ERC7786OpenBridge N-of-M aggregator ([#27](https://github.com/dadadave80/lattice/issues/27)) ([710225e](https://github.com/dadadave80/lattice/commit/710225eda5f5f180b418a91730dc1a8fc79812a4))
* **crosschain:** add L1&lt;-&gt;L2 canonical CrossDomainMessenger ERC-7786 gateway ([#77](https://github.com/dadadave80/lattice/issues/77)) ([d7a32d1](https://github.com/dadadave80/lattice/commit/d7a32d189c92d3cdbde17c8e166766d0a8cc7be1))
* **crosschain:** add Wormhole ERC-7786 gateway adapter ([#27](https://github.com/dadadave80/lattice/issues/27)) ([21b4238](https://github.com/dadadave80/lattice/commit/21b42385a7c8d697f0056e4a52f564d19493a569))
* **crosschain:** Aurora enablement — real M=2 via LayerZero + Hyperlane in one addEvmChain call ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 11) ([75acf88](https://github.com/dadadave80/lattice/commit/75acf884adfc21bf25aaccf62ffac8316ca0c085))
* **crosschain:** Aurora enablement — real M=2 via LayerZero + Hyperlane in one addEvmChain call ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 11) ([c23179a](https://github.com/dadadave80/lattice/commit/c23179a7ffc53cb2b1ffc81e5c7ffca14fded109))
* **crosschain:** Axelar ERC-7786 gateway adapter ([#27](https://github.com/dadadave80/lattice/issues/27) — gateway 1/3) ([eb9dfe4](https://github.com/dadadave80/lattice/commit/eb9dfe4e4b9841cd5f14f4b3bdeabe04086aa950))
* **crosschain:** ChainRegistry — one-action add-chain fan-out + OpenBridge M-of-N coverage awareness ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 10) ([ea48e5c](https://github.com/dadadave80/lattice/commit/ea48e5c17484147eccbd493efba882410f9beaae))
* **crosschain:** ChainRegistry — one-action add-chain fan-out + OpenBridge M-of-N coverage awareness ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 10) ([ac112a8](https://github.com/dadadave80/lattice/commit/ac112a8c4a2a15cc4f84f911ccee1b1d0f8d95b4))
* **crosschain:** ERC-7786 cross-chain module — link, fungible bridges, governance handler ([#27](https://github.com/dadadave80/lattice/issues/27)) ([8d0f022](https://github.com/dadadave80/lattice/commit/8d0f022e70b328943b5a62ded8745a56e57352da))
* **crosschain:** ERC-7786 cross-chain module (link + bridges + governance) ([4643b4b](https://github.com/dadadave80/lattice/commit/4643b4bfba29fe1a8f453ceb0976c8a45ab6f4c2))
* **crosschain:** HyperbridgeGatewayAdapter — ISMP proof-verified 7th gateway with ERC-20 fee token ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 16) ([0d51c83](https://github.com/dadadave80/lattice/commit/0d51c830419f08de7529ed8c8ffa88c4f6158cb6))
* **crosschain:** HyperbridgeGatewayAdapter — ISMP proof-verified 7th gateway with ERC-20 fee token ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 16) ([8b88462](https://github.com/dadadave80/lattice/commit/8b884620bd6b21b04ae52845dee739a663282847))
* **crosschain:** HyperlaneGatewayAdapter — 6th ERC-7786 gateway over Mailbox dispatch/handle ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 13) ([d65a0ac](https://github.com/dadadave80/lattice/commit/d65a0ac51b2311d1f321b541c80291c1bca3b196))
* **crosschain:** HyperlaneGatewayAdapter — 6th ERC-7786 gateway over Mailbox dispatch/handle ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 13) ([fa36d95](https://github.com/dadadave80/lattice/commit/fa36d9556ded0a76d378d7890722031bfa30d342))
* **crosschain:** L2ToL2CrossDomainMessengerGatewayAdapter — OP Superchain ERC-7786 gateway ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 3) ([3c4463e](https://github.com/dadadave80/lattice/commit/3c4463e832375c7f1e2a5b4321e23701ba7173e5))
* **crosschain:** land Wormhole + ERC7786OpenBridge gateway adapters on dev ([#27](https://github.com/dadadave80/lattice/issues/27)) ([d36b5ba](https://github.com/dadadave80/lattice/commit/d36b5ba820313d39290a45d830f33f651b6cbccb))
* **crosschain:** LayerZeroGatewayAdapter — ERC-7786 gateway over EndpointV2 ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 2) ([198fd08](https://github.com/dadadave80/lattice/commit/198fd089546b5b357fa684ce6593b7db2301de56))
* **crosschain:** LayerZeroGatewayAdapter — ERC-7786 gateway over EndpointV2 ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 2) ([52e2b1a](https://github.com/dadadave80/lattice/commit/52e2b1a49b855600e0d9976fe8b59ec84166df09))
* **crosschain:** non-EVM ERC-7930 addressing + CCTP USDC token bridge ([#77](https://github.com/dadadave80/lattice/issues/77) sub-tasks 1+5) ([89a7b20](https://github.com/dadadave80/lattice/commit/89a7b2055879aaeb0dfb42162bb3a4df2883d1bd))
* **crosschain:** non-EVM ERC-7930 bytes32 addressing + CCTP USDC token bridge ([#77](https://github.com/dadadave80/lattice/issues/77) sub-tasks 1+5) ([aa3260f](https://github.com/dadadave80/lattice/commit/aa3260f887cfb3bcaea443e38e63c00987da6ec1))
* **crosschain:** OP Superchain ERC-7786 gateways — L2↔L2 interop + L1↔L2 canonical ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 3) ([6621ebd](https://github.com/dadadave80/lattice/commit/6621ebd14d7160534690326628c45081adfeb544))
* **crosschain:** StargateBridgeAdapter — pooled-liquidity token rail over IStargate.sendToken ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 14) ([43ee8cd](https://github.com/dadadave80/lattice/commit/43ee8cd9f87a49e889ce38f882b48ce991bc302d))
* **crosschain:** StargateBridgeAdapter — pooled-liquidity token rail over IStargate.sendToken ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 14) ([343f7ac](https://github.com/dadadave80/lattice/commit/343f7aca072b8f0b9ab83a9cc1b6e979627e0d70))
* **crosschain:** StarknetGatewayAdapter — L1↔L2 non-EVM connector + felt252 ERC-7930 addressing ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 9) ([9281c84](https://github.com/dadadave80/lattice/commit/9281c84cd442ced74b7e88355f5b76dd50fafc70))
* **crosschain:** StarknetGatewayAdapter — L1↔L2 non-EVM connector + felt252 ERC-7930 addressing ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 9) ([a215d9c](https://github.com/dadadave80/lattice/commit/a215d9c5488a097bf875b00c800664fd56f6774e))
* **crosschain:** SuperchainETHBridge interop adapter ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 6, retargeted) ([c1d957b](https://github.com/dadadave80/lattice/commit/c1d957b22b3e03a7b682dc580e1ceea750e77ff3))
* **crosschain:** SuperchainETHBridge interop adapter ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 6, retargeted) ([f662028](https://github.com/dadadave80/lattice/commit/f6620283f9f3c93a98ef3bcbc0ba25b312f54a77))
* **crosschain:** ZetaChainGatewayAdapter — hub-routed ERC-7786 gateway ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 4) ([a720343](https://github.com/dadadave80/lattice/commit/a7203437c4eadc887bffde506948eeccf71e487b))
* **crosschain:** ZetaChainGatewayAdapter — hub-routed ERC-7786 gateway over GatewayEVM ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 4) ([abd69f2](https://github.com/dadadave80/lattice/commit/abd69f2bd7361ec66b0761ececf340f01816d333))
* **defi:** AggregatorExecAdapter — allow-listed arbitrary-call swap/bridge exec (LiFi) ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 7) ([355f0d6](https://github.com/dadadave80/lattice/commit/355f0d60587f725984d2f6b0a379329eef640e5c))
* **defi:** AggregatorExecAdapter — allow-listed arbitrary-call swap/bridge exec (LiFi) ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 7) ([ce19866](https://github.com/dadadave80/lattice/commit/ce19866e991a51cc2bf620b239b7a2f74d78b895))
* **defi:** ENS-named self-governed ERC-4626 vault recipe + Sepolia deploy runbook ([bd2a549](https://github.com/dadadave80/lattice/commit/bd2a549fe21adea8a1d76344971cdba220073a8b))
* **defi:** ENS-named self-governed ERC-4626 vault recipe + Sepolia runbook ([352c6c3](https://github.com/dadadave80/lattice/commit/352c6c383f9a74fb96550161bb5ee6f54aaf887b))
* **defi:** Relay enablement — solver-intent execution as AggregatorExec allow-list config ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 15) ([93fb2b9](https://github.com/dadadave80/lattice/commit/93fb2b9b8d86b489d4476e2e06d620a148335ea8))
* **defi:** Relay enablement — solver-intent execution as AggregatorExec allow-list config ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 15) ([7afcccd](https://github.com/dadadave80/lattice/commit/7afcccdcbbf73bc2099311e1c773b51227cf5584))
* **defi:** self-cranking governance demo in the vault ENS recipe ([d1af01a](https://github.com/dadadave80/lattice/commit/d1af01a91199e7f13de1600bd8af194850c2a3be))
* **defi:** self-cranking governance demo in the vault ENS recipe ([3cfaff2](https://github.com/dadadave80/lattice/commit/3cfaff206c37782688ecac31445073b326207c51))
* **defi:** self-governed ERC-4626 vault recipe — vote-weighted shares govern the vault via Governor + Timelock ([81532c6](https://github.com/dadadave80/lattice/commit/81532c65692c7beb2bf6dfa1632a682915656d47))
* **defi:** self-governed ERC-4626 vault recipe (Governor + Timelock over vote-weighted shares) ([dd5e8fd](https://github.com/dadadave80/lattice/commit/dd5e8fdd59261912ed811bec7e04f01d298581f3))
* **defi:** self-healing governance demo + autonomous crank loop ([52e1c34](https://github.com/dadadave80/lattice/commit/52e1c34a6a09cc225cea01c403c6a79460552a13))
* **diamond:** ERC-8153 exportSelectors() across all 94 facets + FFI-free cut path ([#118](https://github.com/dadadave80/lattice/issues/118)) ([cb4cede](https://github.com/dadadave80/lattice/commit/cb4cede7e9ceff6a22b8e23a399619b361694b00))
* **ens:** add ENSResolver (forward resolution) + ENSSubnameIssuer (NameWrapper) ([92c1061](https://github.com/dadadave80/lattice/commit/92c1061f0736fe70a6789b2eff75d8b1d3775016))
* **ens:** add ENSReverseClaimer for diamond self-claimed ENS names ([0e2eb53](https://github.com/dadadave80/lattice/commit/0e2eb53017dd9d7fd645abbedf4dd804b418cfb4))
* **ens:** forward resolution (ENSResolver) + subname issuance (ENSSubnameIssuer) ([3523f2e](https://github.com/dadadave80/lattice/commit/3523f2e4259a4632507c21a7c1bd5b15c2fc0ea1))
* **factory:** DiamondFactory — one-tx diamond assembly from registry-resolved cuts ([#120](https://github.com/dadadave80/lattice/issues/120) part 1) ([45d4ef4](https://github.com/dadadave80/lattice/commit/45d4ef4620e9f60eb9d941f3c598b02fee2ec2d8))
* **factory:** DiamondFactory — one-tx diamond assembly from registry-resolved cuts ([#120](https://github.com/dadadave80/lattice/issues/120)) ([cec601f](https://github.com/dadadave80/lattice/commit/cec601f7259874318d8cd09f425a54aeb60deeec))
* **factory:** require loupe coverage in fresh deploys + lib facets in the release catalog ([b8d4382](https://github.com/dadadave80/lattice/commit/b8d4382384deb0e5bf0c9b9fdfe9479a1e8d5e72))
* **factory:** require loupe coverage in fresh deploys + lib facets in the release catalog ([fa90799](https://github.com/dadadave80/lattice/commit/fa90799dd020848844dfba45984fd5e12b598499))
* **governance:** add SafeDiamondCut multisig-gated cut ([e064b9c](https://github.com/dadadave80/lattice/commit/e064b9c896603024534c7395129d0239a9968c35))
* **governance:** add SafeHarborAdopter for on-chain SEAL Safe Harbor adoption ([a9fadce](https://github.com/dadadave80/lattice/commit/a9fadce43e39c56c1924497088b1c4f38ee2ad7a))
* **governance:** SafeHarborAdopter — on-chain SEAL Safe Harbor adoption ([61ffa48](https://github.com/dadadave80/lattice/commit/61ffa48cf29765dc0e6a193451eb8739695dde10))
* **markets:** add Seaport MarketplaceZone facet ([#25](https://github.com/dadadave80/lattice/issues/25) v1) ([c659658](https://github.com/dadadave80/lattice/commit/c659658490949d6d68e842afc89190972aa360c6))
* **markets:** add Seaport MarketplaceZone facet ([#25](https://github.com/dadadave80/lattice/issues/25) v1) ([6bec3c6](https://github.com/dadadave80/lattice/commit/6bec3c6eb27d1e6adfed0d8afccbb372a4b59246))
* **oracles:** add 6 price-oracle adapters (API3, Chronicle, DIA, Band, Tellor, RedStone) ([5297053](https://github.com/dadadave80/lattice/commit/529705366bc853da4bd7bdcf09822f5a6a601365))
* **oracles:** add API3 dAPI price-oracle adapter ([e0b43df](https://github.com/dadadave80/lattice/commit/e0b43df7f95cba931085ae46916612679120b81d)), closes [#29](https://github.com/dadadave80/lattice/issues/29)
* **oracles:** add API3 QRNG randomness adapter ([#36](https://github.com/dadadave80/lattice/issues/36)) ([d3754e6](https://github.com/dadadave80/lattice/commit/d3754e6a743e6cdb4215c37edadb176fac7b080d))
* **oracles:** add Band Protocol price-oracle adapter ([fc091a1](https://github.com/dadadave80/lattice/commit/fc091a18ab54c44efd02a5e82287e9d4e0e4cf84)), closes [#32](https://github.com/dadadave80/lattice/issues/32)
* **oracles:** add Chainlink Automation (keepers) adapter ([#38](https://github.com/dadadave80/lattice/issues/38)) ([ec0e99b](https://github.com/dadadave80/lattice/commit/ec0e99bb6b1f65d17672c335d8d9af46ff8d6dc7))
* **oracles:** add Chainlink CRE workflow-report receiver adapter ([#39](https://github.com/dadadave80/lattice/issues/39)) ([2349742](https://github.com/dadadave80/lattice/commit/2349742ce321b1faddb8c5277e8a636f42b50cab))
* **oracles:** add Chainlink CRE workflow-report receiver adapter ([#39](https://github.com/dadadave80/lattice/issues/39)) ([5c07085](https://github.com/dadadave80/lattice/commit/5c070855d8f2fd21790e6be49f07f38e7a6ade81))
* **oracles:** add Chronicle price-oracle adapter ([b87acba](https://github.com/dadadave80/lattice/commit/b87acba7107433d51d59766972ccc815119075e2)), closes [#30](https://github.com/dadadave80/lattice/issues/30)
* **oracles:** add DIA price-oracle adapter ([91bb57b](https://github.com/dadadave80/lattice/commit/91bb57b1dd95cd53638be9bb50b4c6826c108538)), closes [#33](https://github.com/dadadave80/lattice/issues/33)
* **oracles:** add Gelato Automate (Web3 Functions) adapter ([#37](https://github.com/dadadave80/lattice/issues/37)) ([dcfb7ea](https://github.com/dadadave80/lattice/commit/dcfb7ead46db5cb0d56452c71d9131eda495dd72))
* **oracles:** add Gelato VRF randomness adapter ([#35](https://github.com/dadadave80/lattice/issues/35)) ([839300b](https://github.com/dadadave80/lattice/commit/839300b4d8980581b54259a3e6a45c9728627100))
* **oracles:** add pull-based Pyth price-oracle adapter ([6969152](https://github.com/dadadave80/lattice/commit/69691527675bfc5d50a1d34c29b448b135950860))
* **oracles:** add pull-based Pyth price-oracle adapter ([35e67e2](https://github.com/dadadave80/lattice/commit/35e67e2da2c578a4b1b93423aeac837135e76abf)), closes [#14](https://github.com/dadadave80/lattice/issues/14)
* **oracles:** add Pyth Entropy randomness adapter ([#34](https://github.com/dadadave80/lattice/issues/34)) ([1d68cfe](https://github.com/dadadave80/lattice/commit/1d68cfea20574f53fd7089226f4501acf9e78ae4))
* **oracles:** add randomness (Pyth Entropy, Gelato VRF, API3 QRNG) + automation (Gelato Automate, Chainlink Automation) adapters ([479c06e](https://github.com/dadadave80/lattice/commit/479c06ee59882f97f30040e9be65cfdfc90673c2))
* **oracles:** add RedStone (Push) price-oracle adapter ([8ae5723](https://github.com/dadadave80/lattice/commit/8ae572371f1366672bd726b343e8bed0dcc55931)), closes [#28](https://github.com/dadadave80/lattice/issues/28)
* **oracles:** add Tellor price-oracle adapter ([f8f7a48](https://github.com/dadadave80/lattice/commit/f8f7a4809a5c12cd169240f05cd050dd2114239d)), closes [#31](https://github.com/dadadave80/lattice/issues/31)
* **privacy:** add CommitReveal primitive ([2d3c104](https://github.com/dadadave80/lattice/commit/2d3c104879ab1cfcc614d55f3e21659277b81534))
* **privacy:** add CommitReveal primitive ([9615785](https://github.com/dadadave80/lattice/commit/96157856e84dc491a3e61a5e8fdd0eebefe51c1a))
* **privacy:** add ERC-5564 announcer + ERC-6538 registry stealth-address facets ([486a768](https://github.com/dadadave80/lattice/commit/486a768e0b398c22db3050c602857e5666ef6919))
* **privacy:** add generic Groth16 verifier facet ([3548520](https://github.com/dadadave80/lattice/commit/354852008f5c376d4d909ada41a4cde3d2be17ce))
* **privacy:** add generic PLONK verifier facet ([cf7bbf8](https://github.com/dadadave80/lattice/commit/cf7bbf89098ac5da53b3d947a27dc5456e25f57c))
* **privacy:** add IncrementalMerkleTree + NullifierRegistry libraries ([b2ec059](https://github.com/dadadave80/lattice/commit/b2ec05920a25bf355c07baf7e0dfa6929d361f5f))
* **privacy:** add PrivateVoting (anonymous 1p1v) facet ([0a5c2f2](https://github.com/dadadave80/lattice/commit/0a5c2f29ce0c13f25ba649046bc47f5647287ab9))
* **privacy:** add Semaphore anonymous-membership / signaling facet ([d93cde4](https://github.com/dadadave80/lattice/commit/d93cde4f62d8dea707b7ad3b369e198b2c862296))
* **privacy:** add ShieldedPool (Tornado-style private ERC-20 transfers) facet ([1e91335](https://github.com/dadadave80/lattice/commit/1e9133501d7c4778add83ab7c3a059568564f222))
* **privacy:** generic Groth16 verifier facet ([cb74ef6](https://github.com/dadadave80/lattice/commit/cb74ef634cd9cca51db888ace1f4e0622dd053ac))
* **privacy:** generic PLONK verifier facet ([7e3db66](https://github.com/dadadave80/lattice/commit/7e3db66e1bba71b72c0139c8c0adbeadde0e35c4))
* **privacy:** PrivateVoting — anonymous 1-person-1-vote facet ([9c121fe](https://github.com/dadadave80/lattice/commit/9c121fee086b358cd32d5450d44804e8b683fb96))
* **privacy:** Semaphore anonymous-membership / signaling facet ([732de45](https://github.com/dadadave80/lattice/commit/732de45658a242cb43075edbb9231b1fe76b8c8d))
* **privacy:** ShieldedPool — Tornado-style private ERC-20 transfers ([410d5bd](https://github.com/dadadave80/lattice/commit/410d5bd9f4d320382eb6e0f6325b999be761c5f0))
* **privacy:** ZK foundation — Poseidon Merkle tree + nullifier registry ([24e67f2](https://github.com/dadadave80/lattice/commit/24e67f2c062a19ca7d9cb1518734fd43c8327226))
* **registry:** CreateX deterministic release tooling + deployment docs ([#120](https://github.com/dadadave80/lattice/issues/120) part 2) ([0acbae9](https://github.com/dadadave80/lattice/commit/0acbae994cc83c38907d8a0aaed2fcf4cc2ac9bd))
* **registry:** CreateX deterministic release tooling + deployment docs ([#120](https://github.com/dadadave80/lattice/issues/120)) ([aef771b](https://github.com/dadadave80/lattice/commit/aef771b4ab462ebd11da8f0fb0861954db1a18eb))
* **registry:** LatticeRegistry — two-tier immutable on-chain facet registry ([#118](https://github.com/dadadave80/lattice/issues/118) phase 1) ([63b58ff](https://github.com/dadadave80/lattice/commit/63b58ff31a691d5c7e0b2fda859b77ee0cea0d56))
* **registry:** string-name convenience overloads for direct callers ([#118](https://github.com/dadadave80/lattice/issues/118)) ([86ce179](https://github.com/dadadave80/lattice/commit/86ce179d8d93c122f15fdea4bc597a4d8e5e2a4e))
* **test:** access + security facet tests on real diamonds via ready-to-deploy scripts (wave 2 of [#89](https://github.com/dadadave80/lattice/issues/89)) ([1a89fb8](https://github.com/dadadave80/lattice/commit/1a89fb870a8c70da74e59de7d31392009fb63719))
* **test:** crosschain + privacy facet tests on real diamonds — completes [#89](https://github.com/dadadave80/lattice/issues/89) (wave 5) ([8bdbb49](https://github.com/dadadave80/lattice/commit/8bdbb49ba7bf3ab5d25374780576b6da0ba4e88b))
* **test:** facet tests against a real diamond via ready-to-deploy scripts (ERC-20 pilot) ([ba1f7d0](https://github.com/dadadave80/lattice/commit/ba1f7d05a4cfaa934a842b3e04efbc6c73af5538))
* **test:** governance facet tests on real diamonds via ready-to-deploy scripts (wave 3 of [#89](https://github.com/dadadave80/lattice/issues/89)) ([9391640](https://github.com/dadadave80/lattice/commit/939164096380330f21e0d3fa511b69c5f6bbe737))
* **test:** migrate access + security facet tests to real diamonds via ready-to-deploy scripts ([#89](https://github.com/dadadave80/lattice/issues/89)) ([b969741](https://github.com/dadadave80/lattice/commit/b969741a2bbad6e8c1721ef343df1737c71f4ebc))
* **test:** migrate crosschain + privacy facet tests to real diamonds via ready-to-deploy scripts ([#89](https://github.com/dadadave80/lattice/issues/89)) ([af7b7c7](https://github.com/dadadave80/lattice/commit/af7b7c723c8b8fd94dfcfdaa01dafbbeccd3a75a))
* **test:** migrate governance diamond-cut + safe-harbor facet tests to real diamonds ([#89](https://github.com/dadadave80/lattice/issues/89)) ([25f0e6a](https://github.com/dadadave80/lattice/commit/25f0e6a229487b9b58ad3f97f6970d0fe3f87957))
* **test:** migrate oracle + defi adapter facet tests to real diamonds via ready-to-deploy scripts ([#89](https://github.com/dadadave80/lattice/issues/89)) ([b4cd2f1](https://github.com/dadadave80/lattice/commit/b4cd2f1e571dfb329c6165c1c8f757f298572e4f))
* **test:** migrate token-family facet tests to real diamonds via ready-to-deploy scripts ([#89](https://github.com/dadadave80/lattice/issues/89)) ([b8c4df6](https://github.com/dadadave80/lattice/commit/b8c4df68397a31c053f53e40ee410f24520c4799))
* **test:** oracle + defi adapter facet tests on real diamonds (wave 4 of [#89](https://github.com/dadadave80/lattice/issues/89)) ([6cf346b](https://github.com/dadadave80/lattice/commit/6cf346b18706a67ca1656e265895ceda1ecebe92))
* **test:** run ERC20 facet test against a real diamond via ready-to-deploy scripts ([#89](https://github.com/dadadave80/lattice/issues/89)) ([b1c2553](https://github.com/dadadave80/lattice/commit/b1c255374e8e226581f88b64fff00a321800dd3d))
* **test:** token-family facet tests on real diamonds via ready-to-deploy scripts (wave 1 of [#89](https://github.com/dadadave80/lattice/issues/89)) ([8a5c9d3](https://github.com/dadadave80/lattice/commit/8a5c9d3b99c4cebf29fad5a4b89305209f2653b4))
* **tokens:** add ERC-7802 crosschain-native ERC-20 token ([#27](https://github.com/dadadave80/lattice/issues/27)) ([c2d7f76](https://github.com/dadadave80/lattice/commit/c2d7f76afa111eef7c411c59222ee7ec9c12bea6))
* **tokens:** add ERC20Crosschain self-bridging ERC-20 ([#27](https://github.com/dadadave80/lattice/issues/27)) ([fb70ceb](https://github.com/dadadave80/lattice/commit/fb70cebfbdd3d5ffb0a2712b187657c9a44405f6))
* **tokens:** ERC-7802 crosschain-native ERC-20 token ([#27](https://github.com/dadadave80/lattice/issues/27)) → dev ([71c6e31](https://github.com/dadadave80/lattice/commit/71c6e31720d09b749101bac9b7d187581a306e8f))
* **tokens:** ERC20 extensions + de-inheritance for diamond composability + CI guard ([37e5ddf](https://github.com/dadadave80/lattice/commit/37e5ddfcb42934db48c935d9560dce93eef07db1))
* **tokens:** ERC20 Pausable + FlashMint extensions (OZ v5.6.1 parity) ([34794ea](https://github.com/dadadave80/lattice/commit/34794ea58a0bd11e67353171969dab0c0019901f))
* **tokens:** ERC20Crosschain self-bridging ERC-20 ([#27](https://github.com/dadadave80/lattice/issues/27) follow-up) ([add838a](https://github.com/dadadave80/lattice/commit/add838a572daff5a9d517e66acc328995b2811c5))
* **tokens:** ERC20Wrapper extension (OZ v5.6.1 parity) ([6afb80d](https://github.com/dadadave80/lattice/commit/6afb80dc887365a93c08d43dc6fa0dfde051ce34))


### Bug Fixes

* **accounts:** store AccountSigner _signerType as uint8 for a reproducible storage layout ([a937241](https://github.com/dadadave80/lattice/commit/a9372412f3df6826dd16f7f7ecd353b915158af1))
* **config:** enable optimizer in the default profile ([0a5e0a8](https://github.com/dadadave80/lattice/commit/0a5e0a82ac981acd21acf183d45c73c7b2c60dab))
* **diamond:** make recipe diamonds upgradeable and introspectable ([2f333c9](https://github.com/dadadave80/lattice/commit/2f333c9c775a75b88c959d628b0799037d74af95))
* **diamond:** make recipe diamonds upgradeable and introspectable ([4f20cbf](https://github.com/dadadave80/lattice/commit/4f20cbf2d5fa0fa66cd0b533ee66bb052eea99f8))
* **recipes:** loupe + upgrade authority in every deploy recipe ([ce62eb1](https://github.com/dadadave80/lattice/commit/ce62eb1fc075580b8f389ab008138107b8b8719f))
* **recipes:** loupe + upgrade authority in every deploy recipe ([de83be7](https://github.com/dadadave80/lattice/commit/de83be73e9aeb9032eb8612021c41384d0b96250))


### Refactors

* align every registerInterface with the precomputed ERC-165 map-slot standard ([5506c9e](https://github.com/dadadave80/lattice/commit/5506c9efbf627a0dd88b5c0c7a16b5eb184706f0))
* **diamond:** de-inherit 5 facets that inherited another facet into composable facets + recipes ([26fcca8](https://github.com/dadadave80/lattice/commit/26fcca819b6925f7ffece59788666860c79c985f))
* **diamond:** de-inherit 5 facets that inherited another facet into composable facets + recipes ([6df9a06](https://github.com/dadadave80/lattice/commit/6df9a06a3a2897bb7b139eb5d34aad95c835178e))
* domain-mirror interfaces, flavor-split accounts, per-standard tokens ([9cdaa29](https://github.com/dadadave80/lattice/commit/9cdaa29a505b11e6f5de279f94a6905584bb7dc0))
* domain-mirror interfaces, flavor-split accounts, per-standard tokens ([cb3d8a5](https://github.com/dadadave80/lattice/commit/cb3d8a5aa2faaf42282a0f24722f5003c52dd38c))
* **script:** migrate 84 recipes to the ERC-8153 address-only cut API ([#118](https://github.com/dadadave80/lattice/issues/118)) ([ebe40e4](https://github.com/dadadave80/lattice/commit/ebe40e4114769f07f62717717dcaaf0535c9bbe5))
* **script:** move DeployAccount/DeployAccount6900 to script/base/accounts/ ([6e0c9a3](https://github.com/dadadave80/lattice/commit/6e0c9a323ce8b8a28c3613c36c93106a020b8b74))
* **script:** organize deploy recipes into per-domain subfolders mirroring src/ ([8b11a24](https://github.com/dadadave80/lattice/commit/8b11a24ef1b1d06c022242cc6b03c3d669685b57))
* **test,script:** reorg tests & scripts to the Testing/Deployment standards ([7fd15a7](https://github.com/dadadave80/lattice/commit/7fd15a7410dd06bc5c06b0d625803d41940ccfc8))
* **test,script:** reorg tests & scripts to the Testing/Deployment standards ([#87](https://github.com/dadadave80/lattice/issues/87)) ([5fda95b](https://github.com/dadadave80/lattice/commit/5fda95bbd0daf298b8bc797aa612a0a4e480ebcf))
* **tokens:** de-bundle ERC20Permit from EIP712/Nonces; compose via blueprint ([8bed7ee](https://github.com/dadadave80/lattice/commit/8bed7eed63feb00b4ccdc3fab9a91fc20a4b7895))
* **tokens:** de-inherit ERC20 extensions from the base facet for composability ([b228a66](https://github.com/dadadave80/lattice/commit/b228a666ce19378c40846c8d12440962e32c4c11))
* **tokens:** move ERC20Init to src/tokens/ERC20 ([#89](https://github.com/dadadave80/lattice/issues/89)) ([bc541da](https://github.com/dadadave80/lattice/commit/bc541da370f0b22dd6fe9e8cace83730f91e73bc))


### Documentation

* attribute every externally derived integration + codify attribution/registerInterface rules in CLAUDE.md ([f28d9cf](https://github.com/dadadave80/lattice/commit/f28d9cf317c509272ed380bcebec3724b564e67c))
* attribute every externally derived integration + codify repo rules in CLAUDE.md ([bae253f](https://github.com/dadadave80/lattice/commit/bae253f74a1e985372ce8dfcb89962f4f84df79c))
* **crosschain:** adapter-suite reference + fork smoke tests + registry catch-up ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 12) ([c7bd1e4](https://github.com/dadadave80/lattice/commit/c7bd1e4baf5ec12efd0d237811e0e111a2cd8914))
* **crosschain:** adapter-suite reference + fork smoke tests + registry catch-up ([#77](https://github.com/dadadave80/lattice/issues/77) sub-task 12) ([1bb1fbd](https://github.com/dadadave80/lattice/commit/1bb1fbd130e8776302a3fc945d3ed1cd236f6d00))
* ERC-6900 as an alternative account flavor to ERC-7579 ([#74](https://github.com/dadadave80/lattice/issues/74) sub-task 9) ([6077880](https://github.com/dadadave80/lattice/commit/6077880e4c051008e9cbcdf754e6f65375b72acc))
* ERC-6900 as an alternative account flavor to ERC-7579 ([#74](https://github.com/dadadave80/lattice/issues/74)) ([2b15d21](https://github.com/dadadave80/lattice/commit/2b15d21553fc2800ba83e154d2b0c54407d27a98))
* fix dead Chainlink [@author](https://github.com/author) links (monorepo → chainlink-evm) + CRE ReceiverTemplate clarification ([24a4f16](https://github.com/dadadave80/lattice/commit/24a4f1652674523f75f787d49e7679a2a4bdcc4a))
* milestone 1 proof — live deployment section, PROGRESS.md, broadcast evidence ([1af3aa2](https://github.com/dadadave80/lattice/commit/1af3aa29e791d27640985420f4b5174c47c93184))
* milestone 1 proof — live deployment section, PROGRESS.md, broadcast evidence ([6e0f07a](https://github.com/dadadave80/lattice/commit/6e0f07a577d8e05f175ab80cd820dfb55ddc62b0))
* **oracles:** fix dead CRE source links, clarify direct-IReceiver vs ReceiverTemplate ([8123e7d](https://github.com/dadadave80/lattice/commit/8123e7d51ba87732af89173b26da10d6dcc6ad39))
* refresh project status in readme ([3d9ba92](https://github.com/dadadave80/lattice/commit/3d9ba92e3757d2ed1da08a50f007fc5e02f0fb04))
* repoint remaining dead Chainlink [@author](https://github.com/author) links to chainlink-evm ([2d8f415](https://github.com/dadadave80/lattice/commit/2d8f4150efa497d9c75377e56b5f466c2c011b87))
