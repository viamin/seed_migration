# Changelog

## [1.2.6](https://github.com/viamin/seed_migration/compare/seed-migration-v1.2.5...seed-migration/v1.2.6) (2025-09-29)


### Bug Fixes

* Replace rescue Exception with rescue StandardError ([2e65bb6](https://github.com/viamin/seed_migration/commit/2e65bb6e919544d048cc2f64cdc39af12f3b1d11))


### Improvements

* Enhance seed migration to track migration versions and warn about unregistered models with existing data ([#14](https://github.com/viamin/seed_migration/issues/14)) ([1d9b373](https://github.com/viamin/seed_migration/commit/1d9b3734b4f8ccbd8f1835c06ea5980d3158b8bb))
* Improve model processing order by sorting registered models based on migration timestamps and enhance migration file checks for model references ([#15](https://github.com/viamin/seed_migration/issues/15)) ([2b1aaea](https://github.com/viamin/seed_migration/commit/2b1aaea64640792307ccc6995cff98c3adf7b5af))
* Preserve model processing order by extracting existing model order from seeds.rb and enhancing migration handling for registered and unregistered models ([#16](https://github.com/viamin/seed_migration/issues/16)) ([87d18e9](https://github.com/viamin/seed_migration/commit/87d18e957c4e1259d273eae9778c578427ee0c89))
* Refactor registrar to use Array instead of Set, update logger method to accept existing logger instance, and enhance tests for seed data preservation and unregistered models ([#13](https://github.com/viamin/seed_migration/issues/13)) ([7675f8d](https://github.com/viamin/seed_migration/commit/7675f8d24bb5c09972f2d963fdbe38d6b1e5f1b4))
