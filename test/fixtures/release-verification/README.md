# Source verification fixtures

The executable `curl` and `sleep` mocks are used only by `script/test-release-verification.sh`.
They read queued local files, never open a socket, and check that the verifier transport excludes
ambient credentials. They model exact, partial, pending, failed, rate-limited and malformed responses.

The two files under `historical/` are minimal read-only Sourcify v2 responses fetched on 2026-11-06
for historical Lattice Sepolia deployments, with only match identity, bytecodes, compiler facts and
constructor ABI retained:

- [Factory](https://sourcify.dev/server/v2/contract/11155111/0x9e49fb5cdbb09ecf65513f7c690909e093170037?fields=creationBytecode,runtimeBytecode,compilation,abi)
- [Registry](https://sourcify.dev/server/v2/contract/11155111/0x563f372b4E970fe9976cFFeec614d07a2c353684?fields=creationBytecode,runtimeBytecode,compilation,abi)

Their creation bytecodes include constructor arguments (96 and 32 bytes respectively), also exposed
as `creationBytecode.transformationValues.constructorArguments`. Tests reject hashing only the
constructor-free creation code. These deployments used Osaka and are API-conformance examples;
they are not current Cancun release goldens, a canonical-owner decision or chain readiness evidence.
The library self-address patch case is explicit synthetic data, separate from those historical records.

API semantics: [official Sourcify v2 reference](https://docs.sourcify.dev/docs/api/) and
[OpenAPI schema](https://sourcify.dev/server/api-docs/swagger.json). No public verification submission
was made to create these fixtures.
