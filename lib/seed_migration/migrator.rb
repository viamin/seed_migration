require "logger"
require "pathname"
require "ostruct"

module SeedMigration
  class Migrator
    SEEDS_FILE_PATH = Rails.root.join("db", "seeds.rb")
    STDNULL = File.open(File::NULL, "w")

    def self.data_migration_directory
      Rails.root.join("db", SeedMigration.migrations_path)
    end

    def self.migration_path(filename)
      data_migration_directory.join(filename).to_s
    end

    def initialize(migration_path)
      @path = Pathname.new(migration_path)
      raise "Can't find migration at #{@path}." if !@path.exist?
    end

    def up
      # Check if we already migrated this file
      klass = class_from_path
      version, _ = self.class.parse_migration_filename(@path)
      raise "#{klass} has already been migrated." if SeedMigration::DataMigration.where(version: version).first

      start_time = Time.now
      announce("#{klass}: migrating")

      # Set the current migration version so registrations can be tracked
      SeedMigration.current_migration_version = version

      ActiveRecord::Base.transaction do
        klass.new.up
        end_time = Time.now
        runtime = (end_time - start_time).to_d.round(2)

        # Create record
        migration = SeedMigration::DataMigration.new
        migration.version = version
        migration.runtime = runtime.to_i
        migration.migrated_on = DateTime.now
        begin
          migration.save!
        rescue => e
          SeedMigration::Migrator.logger.error e
        end
        announce("#{klass}: migrated (#{runtime}s)")

        # Clear current migration version
        SeedMigration.current_migration_version = nil
      end
    end

    def down
      klass = class_from_path
      version = @path.basename.to_s.split("_", 2).first

      # Get migration record
      migration = SeedMigration::DataMigration.where(version: version).first

      # Do not proceed without it!
      raise "#{klass} hasn't been migrated." if migration.nil?

      # Revert
      start_time = Time.now
      announce("#{klass}: reverting")
      ActiveRecord::Base.transaction do
        klass.new.down
        end_time = Time.now
        runtime = (end_time - start_time).to_d.round(2)

        # Delete record of migration
        migration.destroy
        announce("#{klass}: reverted (#{runtime}s)")
      end
    end

    def self.check_pending!
      if get_new_migrations.any?
        raise SeedMigration::Migrator::PendingMigrationError
      end
    end

    # Rake methods
    def self.run_new_migrations
      # TODO : Add warning about empty registered_models
      get_new_migrations.each do |migration|
        migration = migration_path(migration)
        new(migration).up
      end
    end

    def self.run_migrations(filename = nil)
      if filename.blank?
        # Run any outstanding migrations
        run_new_migrations
      else
        path = migration_path(filename)
        new(path).up
      end
      create_seed_file
    end

    def self.last_migration
      SeedMigration::DataMigration.maximum("version")
    end

    def self.rollback_migrations(filename = nil, steps = 1)
      if filename.blank?
        to_run = get_last_x_migrations(steps)
        to_run.each do |migration|
          new(migration).down
        end
      else
        path = migration_path(filename)
        new(path).down
      end
      create_seed_file
    end

    def self.display_migrations_status
      logger.info "\ndatabase: #{ActiveRecord::Base.connection_db_config.database}\n\n"
      logger.info "#{"Status".center(8)}  #{"Migration ID".ljust(14)}  Migration Name"
      logger.info "-" * 50

      up_versions = get_all_migration_versions
      get_migration_files.each do |file|
        version, name = parse_migration_filename(file)
        status = up_versions.include?(version) ? "up" : "down"
        logger.info "#{status.center(8)}  #{version.ljust(14)}  #{name}"
      end
    end

    def self.bootstrap(last_timestamp = nil)
      logger.info "Assume seed data migrated up to #{last_timestamp}"
      files = get_migration_files(last_timestamp.to_s)
      files.each do |file|
        migration = SeedMigration::DataMigration.new
        migration.version, _ = parse_migration_filename(file)
        migration.runtime = 0
        migration.migrated_on = DateTime.now
        migration.save!
      end
    end

    def self.logger
      set_logger if @logger.nil?
      @logger
    end

    def self.set_logger(logger_instance = nil)
      output = ENV.fetch("SILENT_MIGRATION", false) ? STDNULL : $stdout
      @logger = logger_instance || Logger.new(output)
    end

    private

    def class_from_path
      announce("Loading migration class at '#{@path}'")
      require @path.to_s
      filename = @path.basename.to_s
      classname_and_extension = filename.split("_", 2).last
      classname = classname_and_extension.split(".").first.camelize
      classname.constantize
    end

    def announce(text)
      length = [0, 75 - text.length].max
      SeedMigration::Migrator.logger.info "== %s %s" % [text, "=" * length]
    end

    class << self
      def get_new_migrations
        migrations = []
        files = get_migration_files

        # If there is no last migration, all migrations are new
        if get_last_migration_date.nil?
          return files
        end

        all_migration_versions = get_all_migration_versions

        files.each do |file|
          filename = file.split("/").last
          version = filename.split("_").first
          if !all_migration_versions.include?(version)
            migrations << filename
          end
        end

        # Sort the files so they execute in order
        migrations.sort!

        migrations
      end

      def get_last_x_migrations(x = 1)
        # Grab data from DB
        migrations = SeedMigration::DataMigration.order("version DESC").limit(x).pluck("version")

        # Get actual files to load
        to_rollback = []
        files = get_migration_files
        migrations.each do |migration|
          files.each do |file|
            if !file.split("/").last[migration].nil?
              to_rollback << file
            end
          end
        end

        to_rollback
      end

      def get_last_migration_date
        return nil if SeedMigration::DataMigration.count == 0
        DateTime.parse(last_migration)
      end

      def get_migration_files(last_timestamp = nil)
        files = Dir.glob(migration_path("*_*.rb"))
        if last_timestamp.present?
          files.delete_if do |file|
            timestamp = File.basename(file).split("_").first
            timestamp > last_timestamp
          end
        end

        # Just in case
        files.sort!
      end

      def get_all_migration_versions
        SeedMigration::DataMigration.all.map(&:version)
      end

      def parse_migration_filename(filename)
        basename = File.basename(filename, ".rb")
        _, version, underscored_name = basename.match(/(\d+)_(.*)/).to_a
        name = underscored_name.tr("_", " ").capitalize
        [version, name]
      end

      def create_seed_file
        if !SeedMigration.update_seeds_file || !Rails.env.development?
          return
        end

        # First, check for and warn about unregistered models with data
        # This preserves data but warns the user about potential issues
        discovered_models = discover_models_from_database
        registered_models = SeedMigration.registrar.map(&:model).to_set
        unregistered_with_data = discovered_models.select do |model_class|
          !registered_models.include?(model_class) && model_has_seed_data?(model_class)
        end

        warn_about_unregistered_models(unregistered_with_data) if unregistered_with_data.any?

        File.open(SEEDS_FILE_PATH, "w") do |file|
          file.write <<~EOS
            # encoding: UTF-8
            # This file is auto-generated from the current content of the database. Instead
            # of editing this file, please use the migrations feature of Seed Migration to
            # incrementally modify your database, and then regenerate this seed file.
            #
            # If you need to create the database on another system, you should be using
            # db:seed, not running all the migrations from scratch. The latter is a flawed
            # and unsustainable approach (the more migrations you'll amass, the slower
            # it'll run and the greater likelihood for issues).
            #
            # It's strongly recommended to check this file into your version control system.

            ActiveRecord::Base.transaction do
          EOS

          # Get the existing order from seeds.rb if it exists, otherwise use registration order
          existing_model_order = extract_model_order_from_existing_seeds
          all_models_to_include = get_all_models_preserving_existing_order(existing_model_order, unregistered_with_data)

          # Process models in the preserved order
          all_models_to_include.each do |model_class|
            register_entry = find_register_entry_for_model(model_class)

            # If no current registration exists, try to determine what attributes
            # were originally included by analyzing existing seeds.rb
            if register_entry.nil?
              register_entry = create_temp_register_entry_preserving_exclusions(model_class)
            end

            process_model_for_seeds(file, model_class, register_entry)
          end

          file.write <<~EOS
            end

            SeedMigration::Migrator.bootstrap(#{last_migration})
          EOS
        end
      end

      # Extract the order of models from existing seeds.rb file
      # This preserves the working order that's already in production
      def extract_model_order_from_existing_seeds
        return [] unless File.exist?(SEEDS_FILE_PATH)

        content = File.read(SEEDS_FILE_PATH)
        model_order = []

        # Look for Model.create patterns and extract model names
        content.scan(/^\s*(\w+)\.create[!(]/) do |match|
          model_name = match[0]
          # Skip internal migration tracking
          next if model_name == "SeedMigration"

          # Add to order if not already present (preserve first occurrence order)
          model_order << model_name unless model_order.include?(model_name)
        end

        logger.info "Found existing seeds.rb model order: #{model_order.join(", ")}" if model_order.any?
        model_order
      end

      # Get all models that need to be included, preserving existing order
      def get_all_models_preserving_existing_order(existing_model_order, unregistered_with_data)
        all_models = []
        registered_models = SeedMigration.registrar.map(&:model)

        # First, add models in the existing order (if they still exist and have registrations or data)
        existing_model_order.each do |model_name|
          model_class = model_name.constantize
          if registered_models.include?(model_class) || unregistered_with_data.include?(model_class)
            all_models << model_class
          end
        rescue NameError
          # Model no longer exists, skip
          logger.debug "Model #{model_name} from existing seeds.rb no longer exists, skipping"
        end

        # Then add any new registered models that weren't in the existing order
        # Sort these by migration execution order (chronological), not registration order
        new_registered_models = registered_models.reject { |model| all_models.include?(model) }
        if new_registered_models.any?
          sorted_new_models = sort_models_by_migration_execution_order(new_registered_models)
          sorted_new_models.each do |model_class|
            all_models << model_class
            logger.info "Adding newly migrated model to end: #{model_class.name}"
          end
        end

        # Finally add any new unregistered models with data (also sorted by migration order)
        new_unregistered_models = unregistered_with_data.reject { |model| all_models.include?(model) }
        if new_unregistered_models.any?
          sorted_unregistered_models = sort_models_by_migration_execution_order(new_unregistered_models)
          sorted_unregistered_models.each do |model_class|
            all_models << model_class
            logger.info "Adding unregistered model with migrated data to end: #{model_class.name}"
          end
        end

        all_models
      end

      # Sort models by the chronological order of migration execution
      # This ensures that models follow the dependency order from actual migration history
      def sort_models_by_migration_execution_order(models)
        return models if models.empty?

        # Create model -> earliest_migration_timestamp mapping
        model_timestamps = {}

        models.each do |model_class|
          timestamp = find_earliest_migration_for_model(model_class)
          model_timestamps[model_class] = timestamp
        end

        # Sort by timestamp (chronological migration execution order)
        models.sort_by { |model| model_timestamps[model] }
      end

      # Create a temporary register entry for unregistered models with data
      # This tries to preserve the original attribute exclusions by analyzing existing seeds.rb
      def create_temp_register_entry_preserving_exclusions(model_class)
        # First try to determine what attributes were originally included
        # by analyzing the existing seeds.rb file
        original_attributes = extract_attributes_from_existing_seeds(model_class)

        if original_attributes.any?
          # Use the attributes that were actually in the seeds.rb file
          logger.debug "Preserving original attributes for #{model_class.name}: #{original_attributes.join(", ")}"
          attributes_to_include = original_attributes
        else
          # Fallback to all attributes if we can't determine the original set
          logger.warn "Could not determine original attributes for #{model_class.name}, using all attributes"
          attributes_to_include = model_class.attribute_names
        end

        # Create a register entry that preserves the original exclusions
        OpenStruct.new(
          model: model_class,
          attributes: attributes_to_include
        )
      end

      # Extract the attributes that were actually used for a model in existing seeds.rb
      def extract_attributes_from_existing_seeds(model_class)
        return [] unless File.exist?(SEEDS_FILE_PATH)

        content = File.read(SEEDS_FILE_PATH)
        model_name = model_class.name
        attributes = []

        # Look for model creation lines and extract the attributes used
        # Pattern matches: ModelName.create({"attr1"=>"value1", "attr2"=>"value2"})
        content.scan(/^\s*#{model_name}\.create!?\(\{([^}]+)\}\)/) do |match|
          attr_hash = match[0]
          # Extract attribute names from the hash
          attr_hash.scan(/"([^"]+)"\s*=>/) do |attr_match|
            attr_name = attr_match[0]
            attributes << attr_name unless attributes.include?(attr_name)
          end
        end

        attributes
      end

      # Create a temporary register entry for unregistered models with data
      def create_temp_register_entry(model_class)
        # Create a register entry that includes all attributes
        OpenStruct.new(
          model: model_class,
          attributes: model_class.attribute_names
        )
      end

      # Process a single model for seed file generation
      def process_model_for_seeds(file, model_class, register_entry)
        model_class.order("id").each do |instance|
          file.write generate_model_creation_string(instance, register_entry)
        end

        if !SeedMigration.ignore_ids
          file.write <<-EOS
    ActiveRecord::Base.connection.reset_pk_sequence!('#{model_class.table_name}')
          EOS
        end
      end

      # Find models in the database that look like they contain seed data
      def discover_models_from_database
        models = []

        # Get all tables except Rails internal ones
        excluded_tables = %w[
          schema_migrations ar_internal_metadata
          seed_migration_data_migrations
        ]

        ActiveRecord::Base.connection.tables.each do |table_name|
          next if excluded_tables.include?(table_name)

          begin
            # Try to find the corresponding model class
            model_class = table_name.classify.constantize
            next unless model_class < ActiveRecord::Base

            models << model_class
          rescue NameError, LoadError
            # Model class doesn't exist or can't be loaded, skip
            logger.debug "Skipping table #{table_name}: corresponding model not found"
          end
        end

        models
      end

      # Check if a model has data that should be preserved in seeds
      def model_has_seed_data?(model_class)
        # Only preserve data for models that have records
        model_class.exists?
      rescue => e
        logger.warn "Could not check seed data for #{model_class.name}: #{e.message}"
        false
      end

      # Find existing register entry or create a default one for discovered models
      def find_or_create_register_entry(model_class)
        # First try to find existing registration
        existing_entry = SeedMigration.registrar.find { |entry| entry.model == model_class }
        return existing_entry if existing_entry

        # Create a default registration for unregistered models
        # This preserves their data but warns the user
        RegisterEntry.new(model_class)
      end

      # Warn about models that have seed data but are not explicitly registered
      def warn_about_unregistered_models(unregistered_models_with_data)
        return if unregistered_models_with_data.empty?

        model_names = unregistered_models_with_data.map(&:name).sort.join(", ")
        logger.warn <<~WARNING
          ⚠️  SEED MIGRATION WARNING: Found seed data for unregistered models: #{model_names}
          
          These models have data in the database but are not explicitly registered with SeedMigration.
          Their data will be preserved in seeds.rb, but you should consider registering them explicitly:
          
          #{unregistered_models_with_data.map { |m| "  SeedMigration.register #{m.name}" }.join("\n")}
          
          This usually happens when:
          1. Model registrations were cleared/reset
          2. A migration created data but didn't register the model
          3. Data was created outside of seed migrations
          
          To suppress this warning, either register these models or exclude them from seeds.rb generation.
        WARNING
      end

      def generate_model_creation_string(instance, register_entry)
        attributes = instance.attributes.select { |key| register_entry.attributes.include?(key) }
        if SeedMigration.ignore_ids
          attributes.delete("id")
        end
        sorted_attributes = {}
        attributes.sort.each do |key, value|
          sorted_attributes[key] = value
        end

        model_creation_string = if Rails::VERSION::MAJOR == 3 || defined?(ActiveModel::MassAssignmentSecurity)
          "#{instance.class}.#{create_method}(#{JSON.parse(sorted_attributes.to_json)}, :without_protection => true)"
        else
          "#{instance.class}.#{create_method}(#{JSON.parse(sorted_attributes.to_json)})"
        end

        # With pretty indents, please.
        <<-EOS

    #{model_creation_string}
        EOS
      end

      def create_method
        SeedMigration.use_strict_create? ? "create!" : "create"
      end

      private

      # Sort registered models by the order they were likely introduced in migrations
      # This examines migration timestamps to determine dependency order
      def sort_registered_models_by_migration_order
        registered_models = SeedMigration.registrar.map(&:model)
        return [] if registered_models.empty?

        # Create model -> earliest_migration_timestamp mapping
        model_timestamps = {}

        registered_models.each do |model_class|
          timestamp = find_earliest_migration_for_model(model_class)
          model_timestamps[model_class] = timestamp
        end

        # Sort by timestamp (chronological order)
        registered_models.sort_by { |model| model_timestamps[model] }
      end

      # Find the earliest migration timestamp that could have introduced this model
      # This preserves migration dependency order
      def find_earliest_migration_for_model(model_class)
        table_name = model_class.table_name

        # Get all executed migrations in chronological order
        executed_migrations = SeedMigration::DataMigration.order(:version).pluck(:version)

        # Try to find which migration likely created this table
        # Look for migration files that might have created this model
        migration_files = get_migration_files

        migration_files.each do |file_path|
          filename = File.basename(file_path, ".rb")
          timestamp = filename.split("_").first

          # Skip if this migration hasn't been executed
          next unless executed_migrations.include?(timestamp)

          # Check if this migration file mentions this model or table
          if migration_mentions_model?(file_path, model_class, table_name)
            return timestamp
          end
        end

        # If we can't determine the migration, use a default timestamp
        # This will sort unknown models last
        "99999999999999"
      end

      # Check if a migration file mentions a specific model or table
      def migration_mentions_model?(file_path, model_class, table_name)
        content = File.read(file_path)
        model_name = model_class.name
        # Use ActiveSupport's singularize if available, otherwise simple fallback
        singular_table = table_name.respond_to?(:singularize) ? table_name.singularize : table_name.sub(/s$/, "")

        # Look for various patterns that might indicate this migration created/uses this model
        patterns = [
          /\b#{model_name}\.create!?\s*[({]/,       # Model.create( or Model.create!( or with blocks
          /\b#{model_name}\.new\s*[({]/,              # Model.new( or with blocks
          /\b#{model_name}\.find/,                      # Model.find
          /\b#{model_name}\.where/,                     # Model.where
          /\b#{model_name}\.destroy_all/,               # Model.destroy_all
          /^\s*#{model_name}\s/,                        # Model at start of line
          /create_table\s+[:"']#{table_name}/,          # create_table :table_name
          /create.*#{table_name}/,                      # General create table patterns
          /add.*#{singular_table}/                     # Add model patterns
        ]

        patterns.any? { |pattern| content.match?(pattern) }
      rescue => e
        logger.debug "Could not read migration file #{file_path}: #{e.message}"
        false
      end

      # Find the register entry for a given model
      def find_register_entry_for_model(model_class)
        SeedMigration.registrar.find { |entry| entry.model == model_class }
      end
    end

    class PendingMigrationError < StandardError
      def initialize
        super("Data migrations are pending. To resolve this issue, " \
          "run the following:\n\n\trake seed:migrate\n")
      end
    end
  end
end
