# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SeedMigration is a Rails gem that provides data migrations similar to schema migrations. It manages changes to seed data and auto-generates `db/seeds.rb` files containing model creation statements.

## Key Commands

### Testing
```bash
# Run full test suite (requires database setup)
RAILS_ENV=test bundle exec rake app:db:reset
bundle exec rspec spec

# Run specific test
bundle exec rspec spec/path/to/specific_spec.rb
```

### Database Operations
The gem supports multiple databases via the `DB` environment variable:

```bash
# SQLite (default)
DB=sqlite bundle exec rake app:seed:migrate

# PostgreSQL
DB=postgresql bundle exec rake app:seed:migrate

# MySQL
DB=mysql bundle exec rake app:seed:migrate
```

### Development Commands
```bash
# Run seed migrations
bundle exec rake app:seed:migrate

# Check migration status
bundle exec rake app:seed:migrate:status

# Rollback migrations
bundle exec rake app:seed:rollback

# Reset database (for testing)
bundle exec rake app:db:reset
```

Note: Commands are prefixed with `app:` because this is a Rails engine.

## Architecture

### Core Components

**SeedMigration::Migrator** (`lib/seed_migration/migrator.rb`)
- Central orchestrator for migration execution and seeds.rb generation
- Handles discovery of models, registration loading, and file creation
- Contains complex logic for preserving model processing order and handling unregistered models

**Registration System**
- Models must be explicitly registered to appear in generated seeds.rb
- Registrations are stored in `@@registrar` class variable and include exclusion rules
- Registration context tracks which migration version created each registration

**Migration Execution Flow**
1. Migrations run via `run_migrations()` → `run_new_migrations()` → individual `up()` calls
2. Each migration sets `current_migration_version` for registration context
3. After migrations complete, `create_seed_file()` generates seeds.rb
4. Registration loading mechanism re-executes migration files to capture registrations

### Key Classes

- `SeedMigration::Migration`: Base class for data migrations (like ActiveRecord::Migration)
- `SeedMigration::RegisterEntry`: Holds model registration info and exclusion rules
- `SeedMigration::DataMigration`: ActiveRecord model tracking executed migrations
- `SeedMigration::Engine`: Rails engine configuration

### Registration and Exclusions

Models are registered within migrations:
```ruby
class AddUsers < SeedMigration::Migration
  def up
    SeedMigration.register User do
      exclude :password, :created_at, :updated_at
    end
    # ... create data
  end
end
```

### Critical Bug Fix Context

The codebase recently fixed a major issue where model exclusions weren't being respected. The problem was that registrations made during migrations weren't persisting when `create_seed_file()` ran later. The fix involved adding `load_all_executed_migration_registrations()` which re-loads and re-executes migration files to capture their registrations without re-running data operations.

## Database Configuration

- Supports SQLite, PostgreSQL, and MySQL
- Database selection via `DB` environment variable in development
- Uses `spec/dummy` Rails app for testing
- Migration tracking table: `seed_migration_data_migrations`

## File Structure

- `lib/seed_migration/`: Core gem classes
- `spec/dummy/`: Test Rails application
- `db/data/`: Directory for seed migration files (configurable)
- Generated migrations create table in `db/migrate/`