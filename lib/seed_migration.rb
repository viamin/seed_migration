require "seed_migration/version"
require "seed_migration/engine"

module SeedMigration
  autoload :Migrator, "seed_migration/migrator" # Is it needed ?
  autoload :Migration, "seed_migration/migration"
  autoload :RegisterEntry, "seed_migration/register_entry"
  autoload :DataMigration, "seed_migration/data_migration"

  @@registrar = []
  mattr_accessor :registrar

  class << self
    def register(model, &block)
      unregister model
      entry = RegisterEntry.new(model)
      entry.instance_eval(&block) if block

      # Track which migration (if any) this registration is coming from
      entry.migration_version = current_migration_version if defined?(@current_migration_version) && @current_migration_version

      registrar << entry
    end

    def unregister(model)
      registrar.delete_if { |entry| entry.model_name == model.to_s }
    end

    # Set the current migration version when running migrations
    # This allows us to track which migration each registration came from
    attr_accessor :current_migration_version
  end
end
