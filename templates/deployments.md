# XSYMBOLX Token Deployments

> **After each deployment, replace the placeholder values in the relevant section with the actual artefact IDs printed by `scripts/publish.sh`.**

## Testnet

| Field | Value |
| ------------------ | ------- |
| Package ID | `FILL_IN_AFTER_DEPLOY` |
| TreasuryCap ID | `FILL_IN_AFTER_DEPLOY` |
| MetadataCap ID | `FILL_IN_AFTER_DEPLOY` |
| Currency object ID | `FILL_IN_AFTER_DEPLOY` |
| UpgradeCap ID (burned) | `FILL_IN_AFTER_DEPLOY` |
| Immutability confirmed | Yes (Y/N) |
| Blob ID | `FILL_IN_AFTER_DEPLOY` |
| Blob Object ID | `FILL_IN_AFTER_DEPLOY` |
| Blob URL | `FILL_IN_AFTER_DEPLOY` |
| Deployer Address | `FILL_IN_AFTER_DEPLOY` |
| Treasury Address | `FILL_IN_AFTER_DEPLOY` |
| Deployed | `FILL_IN_AFTER_DEPLOY` |
| Epochs purchased | 50 |

## Mainnet

| Field | Value |
| ------------------ | ------- |
| Package ID | `FILL_IN_AFTER_DEPLOY` |
| TreasuryCap ID | `FILL_IN_AFTER_DEPLOY` |
| MetadataCap ID | `FILL_IN_AFTER_DEPLOY` |
| Currency object ID | `FILL_IN_AFTER_DEPLOY` |
| UpgradeCap ID (burned) | `FILL_IN_AFTER_DEPLOY` |
| Immutability confirmed | Yes (Y/N) |
| Blob ID | `FILL_IN_AFTER_DEPLOY` |
| Blob Object ID | `FILL_IN_AFTER_DEPLOY` |
| Blob URL | `FILL_IN_AFTER_DEPLOY` |
| Deployer Address | `FILL_IN_AFTER_DEPLOY` |
| Treasury Address | `FILL_IN_AFTER_DEPLOY` |
| Deployed | `FILL_IN_AFTER_DEPLOY` |
| Epochs purchased | 200 |

## Notes

- `TreasuryCap` and `MetadataCap` are both transferred to the **deployer** address at publish time (`init()`'s `ctx.sender()`), not directly to governance. Transfer them to their intended custodians according to your deployment runbook.
- `UpgradeCap` is burned via `0x2::package::make_immutable` when `scripts/publish.sh` is run with `--confirm-immutable` (interactive CONFIRM prompt otherwise). This is irreversible — confirm the deployment is final before accepting. Verify immutability with `sui client object <PACKAGE_ID> --json | jq -r .data.owner` → `"Immutable"`.
- Blob Object ID (not Blob ID) is required for lifetime extension.

## Blob lifetime monitoring

Testnet: extend before fewer than 10 epochs remain.
Mainnet: extend before fewer than 50 epochs remain.

```bash
walrus extend --blob-obj-id <BLOB_OBJECT_ID> --epochs-extended <N> --context <testnet|mainnet>
```

## Downstream Move.toml reference

```toml
[addresses]
XMODULENAMEX = "<PACKAGE_ID>"  # use network-appropriate value
```
