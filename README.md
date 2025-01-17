## Exclusive Delegate Resolver

**A contract to resolve a single canonical delegated owner for a given ERC721 token**

## Documentation

This contract is designed to be used in conjunction with a delegate registry to resolve the most specific delegation that matches the rights, with specificity being determined by delegation type in order of ERC721 > CONTRACT > ALL. ERC20 and ERC1155 are not supported. If multiple delegations of the same specificity match the rights, the most recent one is respected. If no delegation matches the rights, global delegations (bytes24(0) are considered, but MUST have an expiration greater than 0 to avoid conflicts with pre-existing delegations). If no delegation matches the rights and there are no empty delegations, the owner is returned. Expirations are supported by extracting a uint40 from the final 40 bits of a given delegation's rights value. If the expiration is past, the delegation is not considered to match the request.

### Deploy

The resolver is deployed at the following addresses:

 - Ethereum: 0x0000000000007129AF73C46C9F01a3fB4FF61A02
 - Base: 0x0000000000007129AF73C46C9F01a3fB4FF61A02
 - ApeChain: 0x0000000000007129AF73C46C9F01a3fB4FF61A02

Don't see your chain? Feel free to deploy your own!

Deploys on EVM equivalent chains can be run with the following command on any chain the canonical ImmutableCreate2Factory and Delegatexyz are deployed:

```shell
$ forge script DeployEVM --rpc-url <your_rpc_url> --private-key <your_private_key>
```

The Resolver will be deployed at `0x0000000000007129AF73C46C9F01a3fB4FF61A02`.

For ZkEVM, run the ZkEVM variant:

```shell
$ forge script DeployZkEVM --rpc-url <your_rpc_url> --private-key <your_private_key> 
```

The Resolver will be deployed at `0x0000000078CC4Cc1C14E27c0fa35ED6E5E58825D`.

### Test

Tests can be run with the following command:

```shell
$ forge test
```
