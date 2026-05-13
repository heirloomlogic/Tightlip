# Multi-Environment Configs

Declare staging and production secrets in one file and select between them per build.

## When to Use Sectioned Configs

Reach for sectioned configs when the same property names need different values across environments — staging keys for development builds, production keys for release builds, perhaps a `qa` set for a release-candidate lane.

A flat config has no environment concept. If you have one set of values, stay flat.

## Format

Each top-level identifier followed by `:` (with no value) is an environment section. Lines within a section are indented exactly 2 spaces:

```yaml
# Secrets.yml
staging:
  revenueCatAPIKey: STAGING_REVENUECAT_API_KEY
  hmacSigningKey:   STAGING_HMAC_KEY

production:
  revenueCatAPIKey: PROD_REVENUECAT_API_KEY
  hmacSigningKey:   PROD_HMAC_KEY
```

**All sections must declare the same set of property names.** Mismatched property sets fail at parse time — this prevents a release build from accidentally referencing a property that only exists in staging.

The active section is chosen at build time. For the rules — `TIGHTLIP_ENV`, Xcode `CONFIGURATION`, the auto-inference behavior — see <doc:EnvironmentSelection>.

## Naming Convention for Env Vars

Devs working on several apps on the same machine see bare names like `REVENUECAT_API_KEY` collide. Prefix every env var with an app-specific tag — `<APP_PREFIX>_<SECRET>` in screaming snake case (e.g. `ACME_REVENUECAT_API_KEY`). Tightlip doesn't enforce this; the convention just keeps configs across projects from stepping on each other.

The Swift-side property name (`revenueCatAPIKey`) stays clean either way — only the env-var side gets the prefix.

## See Also

- <doc:EnvironmentSelection>
- <doc:ConfigGrammar>
