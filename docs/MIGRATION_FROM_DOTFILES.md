# Migration from dotfiles keychain scripts

1. Install `kxxx`.
2. Copy old entries from `nil.secrets`:

```bash
kxxx migrate service --from nil.secrets --to kxxx.secrets --dry-run
kxxx migrate service --from nil.secrets --to kxxx.secrets --apply
```

3. Replace `KEYCHAIN_REF:nil.secrets:*` with `KEYCHAIN_REF:kxxx.secrets:*`.
4. Replace old aliases/functions with `kxxx` commands.
