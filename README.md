## Exclusive Delegate Resolver

**A contract to resolve a single canonical delegated owner for a given ERC721 token**

## Documentation

This contract is designed to be used in conjunction with a delegate registry to resolve the most specific delegation that matches the rights, with specificity being determined by delegation type in order of ERC721 > CONTRACT > ALL. ERC20 and ERC1155 are not supported. If multiple delegations of the same specificity match the rights, the most recent one is respected. If no delegation matches the rights, global delegations (bytes24(0) are considered, but MUST have an expiration greater than 0 to avoid conflicts with pre-existing delegations). If no delegation matches the rights and there are no empty delegations, the owner is returned. Expirations are supported by extracting a uint40 from the final 40 bits of a given delegation's rights value. If the expiration is past, the delegation is not considered to match the request.

### Deploy

The resolver is deployed at the following addresses:

- Ethereum Mainnet: `0x000000000000F2aA95168C61B2230b07Eb6dB00f`
- ApeChain Mainnet: `0x000000000000F2aA95168C61B2230b07Eb6dB00f`
- Arbitrum Sepolia: `0x000000000000F2aA95168C61B2230b07Eb6dB00f`
- Base Sepolia: `0x000000000000F2aA95168C61B2230b07Eb6dB00f`

Don't see your chain? Feel free to deploy your own!

Deploys can be run with the following command on any chain the canonical ImmutableCreate2Factory and DelegateCash are deployed:

```shell
$ forge script Deploy --rpc-url <your_rpc_url> --private-key <your_private_key>
```

The Resolver will be deployed at `0x000000000000F2aA95168C61B2230b07Eb6dB00f` assuming EVM equivalence.

If your chain does not have EVM equivalence, make sure to edit the address for DelegateCash in `src/ExclusiveDelegateResolver.sol`, and for ImmutableCreate2Factory in `script/Deploy.s.sol`.

### Test

Tests can be run with the following command:

```shell
$ forge test
```
