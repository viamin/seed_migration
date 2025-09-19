require "spec_helper"

describe SeedMigration::Migrator do
  before :each do
    # Generate test migrations
    2.times do |i|
      timestamp = Time.now.utc + i
      Rails::Generators.invoke("seed_migration", ["TestMigration#{i}", timestamp.strftime("%Y%m%d%H%M%S")])
    end

    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
  end

  after :each do
    # Delete fixtures from folder
    FileUtils.rm(SeedMigration::Migrator.get_migration_files)
    SeedMigration::DataMigration.delete_all
  end

  let(:test_migration_path) {
    SeedMigration::Migrator.get_migration_files.min
  }
  let(:migrator) { SeedMigration::Migrator.new(test_migration_path) }

  it "is a kind of class" do
    expect(described_class).to be_a_kind_of Class
  end

  describe "#up" do
    it "should load the migration and call up on it" do
      require test_migration_path
      expect_any_instance_of(TestMigration0).to receive(:up)
      expect { migrator.up }.to change { SeedMigration::DataMigration.count }.by(1)
      SeedMigration::DataMigration.order("version DESC").reload.first.destroy
    end
  end

  describe "#down" do
    it "should not work if the initial migration hasn't been run" do
      require test_migration_path
      expect { migrator.down }.to raise_error(/hasn't been migrated/)
    end

    it "should load the migration and call down on it do" do
      require test_migration_path
      # Run migration first
      expect_any_instance_of(TestMigration0).to receive(:up)
      expect { migrator.up }.to change { SeedMigration::DataMigration.count }.by(1)

      # Now rollback
      expect_any_instance_of(TestMigration0).to receive(:down)
      expect { migrator.down }.to change { SeedMigration::DataMigration.count }.by(-1)
    end
  end

  describe ".check_pending!" do
    it "returns nil when no migrations are pending" do
      SeedMigration::Migrator.run_new_migrations
      expect(SeedMigration::Migrator.check_pending!).to be_nil
    end

    it "raises a PendingMigrationError when migrations are pending" do
      error = SeedMigration::Migrator::PendingMigrationError
      expect { SeedMigration::Migrator.check_pending! }.to raise_error(error)
    end
  end

  describe ".get_new_migrations" do
    before(:each) do
      SeedMigration::Migrator.run_new_migrations
      Rails::Generators.invoke("seed_migration", ["TestMigrationBefore", 5.days.ago.utc.strftime("%Y%m%d%H%M%S")])
    end

    it "runs all non ran migrations" do
      expect { SeedMigration::Migrator.run_new_migrations }.to change { SeedMigration::DataMigration.count }.by(1)
    end
  end

  describe ".bootstrap" do
    let(:timestamp) { 5.days.ago.utc.strftime("%Y%m%d%H%M%S") }
    before(:each) do
      FileUtils.rm(SeedMigration::Migrator.get_migration_files)
      Rails::Generators.invoke("seed_migration", ["TestMigrationBefore", timestamp])
    end

    it "runs all migrations" do
      expect { SeedMigration::Migrator.bootstrap }.to change { SeedMigration::DataMigration.count }.by(1)
      expect(SeedMigration::DataMigration.first.version).to eq(timestamp)
    end
  end

  describe "rake tasks" do
    describe "rake migrate" do
      it "should run migrations and insert a record into the data_migrations table" do
        expect { SeedMigration::Migrator.run_new_migrations }.to change { SeedMigration::DataMigration.count }.by(2)
        SeedMigration::DataMigration.order("version DESC").limit(2).destroy_all
      end
    end

    describe "rake rollback" do
      it "should by default roll back one step" do
        expect(SeedMigration::Migrator).to receive(:create_seed_file).once
        # Run migrations
        SeedMigration::Migrator.run_new_migrations

        # Rollback
        expect { SeedMigration::Migrator.rollback_migrations }.to change { SeedMigration::DataMigration.count }.by(-1)
        SeedMigration::DataMigration.order("version DESC").first.destroy
      end

      it "should roll back more than one if specified" do
        expect(SeedMigration::Migrator).to receive(:create_seed_file).once
        # Run migrations
        SeedMigration::Migrator.run_new_migrations

        # Rollback
        expect { SeedMigration::Migrator.rollback_migrations(nil, 2) }.to change { SeedMigration::DataMigration.count }.by(-2)
      end

      it "should roll back specified migration" do
        Rails::Generators.invoke("seed_migration", ["foo", 1])
        # Run the migration
        expect_any_instance_of(SeedMigration::Migrator).to receive(:down).once
        expect(SeedMigration::Migrator).to receive(:create_seed_file).once
        SeedMigration::Migrator.rollback_migrations("1_foo.rb")
      end
    end

    describe "rake migrate:status" do
      before(:each) do
        SeedMigration::Migrator.run_new_migrations
        @files = SeedMigration::Migrator.get_migration_files
      end

      it "should display the appropriate statuses after a migrate" do
        output = capture_stdout do
          SeedMigration::Migrator.set_logger(Logger.new($stdout))
          SeedMigration::Migrator.display_migrations_status
        end

        expect(output).to contain(@files.count).occurrences_of(" up ")
      end

      it "should display the appropriate statuses after a migrate/rollback" do
        SeedMigration::Migrator.rollback_migrations
        output = capture_stdout do
          SeedMigration::Migrator.set_logger(Logger.new($stdout))
          SeedMigration::Migrator.display_migrations_status
        end

        expect(output).to contain(@files.count - 1).occurrences_of(" up ")
        expect(output).to contain(1).occurrences_of(" down ")
      end

      context "when SILENT_MIGRATION is set in the environment" do
        before { allow(ENV).to receive(:fetch).with("SILENT_MIGRATION", false).and_return("true") }

        it "does not output any statuses" do
          output = capture_stdout do
            SeedMigration::Migrator.set_logger
            SeedMigration::Migrator.display_migrations_status
          end

          expect(output).not_to contain(@files.count).occurrences_of(" up ")
        end
      end
    end
  end

  describe "seeds.rb generation" do
    before(:all) do
      2.times { |i|
        u = User.new
        u.username = i
        u.save
      }
      2.times { |i| Product.create }
      2.times { |i| UselessModel.create }
    end

    after(:all) do
      User.delete_all
      Product.delete_all
      UselessModel.delete_all
    end

    before(:each) { SeedMigration::Migrator.run_migrations }
    let(:contents) { File.read(SeedMigration::Migrator::SEEDS_FILE_PATH) }

    context "when not updating seeds file" do
      before(:all) do
        SeedMigration.ignore_ids = false
        SeedMigration.update_seeds_file = false
        SeedMigration.register User
        SeedMigration.register Product
      end

      context "when exists seeds file" do
        before(:all) do
          File.write(SeedMigration::Migrator::SEEDS_FILE_PATH, "dummy seeds script")
          SeedMigration::Migrator.run_new_migrations
        end

        it "should not update seeds.rb file" do
          expect(File.read(SeedMigration::Migrator::SEEDS_FILE_PATH)).to eq "dummy seeds script"
        end
      end

      context "when not exists seeds file" do
        before(:all) do
          if File.exist? SeedMigration::Migrator::SEEDS_FILE_PATH
            FileUtils.rm(SeedMigration::Migrator::SEEDS_FILE_PATH)
          end
          SeedMigration::Migrator.run_new_migrations
        end

        it "should not creates seeds.rb file" do
          expect(File.exist?(SeedMigration::Migrator::SEEDS_FILE_PATH)).to eq(false)
        end
      end

      after(:all) do
        # generate seeds.rb
        SeedMigration.update_seeds_file = true
        SeedMigration::Migrator.run_new_migrations
      end
    end

    context "models" do
      before(:all) do
        SeedMigration.ignore_ids = false
        SeedMigration.update_seeds_file = true
        SeedMigration.register User
        SeedMigration.register Product
      end

      it "creates seeds.rb file" do
        expect(File.exist?(File.join(Rails.root, "db", "seeds.rb"))).to eq(true)
      end

      it "outputs models creation in seeds.rb file" do
        expect(contents).not_to be_nil
        expect(contents).not_to be_empty
        expect(contents).to include("User.create")
        expect(contents).to include("Product.create")
      end

      it "only outputs registered models" do
        expect(contents).not_to include("SeedMigration::DataMigration.create")
        expect(contents).not_to include("UselessModel.create")
      end

      it "should output all attributes" do
        # Allow optional spaces around => and optional bang method (create/create!)
        expect(contents).to match(/(?=.*User\.create!?)(?=.*"id"\s*=>)(?=.*"username"\s*=>).*/)
        expect(contents).to match(/(?=.*Product\.create!?)(?=.*"id"\s*=>)(?=.*"created_at"\s*=>)(?=.*"updated_at"\s*=>).*/)
      end

      it "should output attributes alphabetically ordered" do
        # Keys appear sorted alphabetically; allow spacing and optional bang
        expect(contents).to match(/(?=.*User\.create!?)(?=.*"a"\s*=>.*"id"\s*=>.*"username"\s*=>).*/)
      end

      context "with strict_create option" do
        before(:all) do
          SeedMigration.use_strict_create = true
        end

        it "outputs models creation with the bang method" do
          expect(contents).not_to be_nil
          expect(contents).not_to be_empty
          expect(contents).to include("User.create!")
          expect(contents).to include("Product.create!")
        end
      end
    end

    context "attributes" do
      before(:all) do
        SeedMigration.register User do
          exclude :id
        end
      end

      it "only outputs selected attributes" do
        expect(contents).to match(/(?=.*User\.create!?)(?!.*"id"\s*=>)(?=.*"username"\s*=>).*/)
      end

      context "ignore_ids option" do
        before(:all) do
          SeedMigration.ignore_ids = true
          SeedMigration.register User
        end

        it "doesn't output ids" do
          expect(contents).to match(/(?=.*User\.create!?)(?!.*"id"\s*=>)(?=.*"username"\s*=>).*/)
        end

        it "doesn't reset the pk sequence" do
          expect(contents).not_to include("ActiveRecord::Base.connection.reset_pk_sequence")
        end
      end
    end

    context "bootstrap" do
      it "should contain the bootstrap call" do
        expect(contents).to match("SeedMigration::Migrator.bootstrap")
      end

      it "should contain the last migrations timestamp" do
        last_timestamp = SeedMigration::Migrator.get_migration_files.map { |pathname| File.basename(pathname).split("_").first }.last
        expect(contents).to include("SeedMigration::Migrator.bootstrap(#{last_timestamp})")
      end
    end

    context "non development environment" do
      before(:each) do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        FileUtils.rm(SeedMigration::Migrator::SEEDS_FILE_PATH)
        SeedMigration::Migrator.run_new_migrations
      end
      it "doesn't generate seed file" do
        expect(File.exist?(SeedMigration::Migrator::SEEDS_FILE_PATH)).to eq(false)
      end
    end
  end

  describe "seeds file evaluation" do
    before(:each) do
      2.times { |i|
        u = User.new
        u.username = i
        u.save
      }
      2.times { |i| Product.create }
      2.times { |i| UselessModel.create }

      SeedMigration.ignore_ids = true
      SeedMigration.update_seeds_file = true
      SeedMigration.register User
      SeedMigration.register Product

      SeedMigration::Migrator.run_migrations
    end

    after(:each) do
      User.delete_all
      Product.delete_all
      UselessModel.delete_all
    end

    it "creates seeds.rb file" do
      expect(File.exist?(File.join(Rails.root, "db", "seeds.rb"))).to eq(true)
    end

    it "evaluates without throwing any errors" do
      load File.join(Rails.root, "db", "seeds.rb")
    end
  end

  describe ".get_migration_files" do
    context "without params" do
      it "return all migrations" do
        expect(SeedMigration::Migrator.get_migration_files.length).to eq(2)
      end
    end

    context "with params" do
      let(:timestamp1) { 1.minutes.from_now.strftime("%Y%m%d%H%M%S") }
      let(:timestamp2) { 2.minutes.from_now.strftime("%Y%m%d%H%M%S") }

      it "returns migration up to the given timestamp" do
        Rails::Generators.invoke("seed_migration", ["TestMigration#{timestamp1}", timestamp1])
        Rails::Generators.invoke("seed_migration", ["TestMigration#{timestamp2}", timestamp2])

        expect(SeedMigration::Migrator.get_migration_files(timestamp1).length).to eq(3)
      end
    end
  end

  describe ".bootstrap" do
    context "without params" do
      it "marks all migrations as ran" do
        SeedMigration::Migrator.bootstrap
        expect(SeedMigration::DataMigration.all.length).to eq(2)
      end
    end

    context "with timestamp param" do
      let(:timestamp1) { 1.minutes.from_now.strftime("%Y%m%d%H%M%S") }
      let(:timestamp2) { 2.minutes.from_now.strftime("%Y%m%d%H%M%S") }

      it "marks migrations prior to timestamp" do
        Rails::Generators.invoke("seed_migration", ["TestMigration#{timestamp1}", timestamp1])
        Rails::Generators.invoke("seed_migration", ["TestMigration#{timestamp2}", timestamp2])

        SeedMigration::Migrator.bootstrap(timestamp1)
        expect(SeedMigration::DataMigration.all.length).to eq(3)
      end
    end
  end

  describe ".run_new_migrations" do
    context "with pending migrations" do
      it "runs migrations" do
        expect { SeedMigration::Migrator.run_new_migrations }.to_not raise_error
      end
    end

    context "without pending migrations" do
      before(:each) { SeedMigration::Migrator.run_new_migrations }

      it "runs migrations" do
        expect { SeedMigration::Migrator.run_new_migrations }.to_not raise_error
      end
    end
  end

  describe ".run_migrations" do
    context "without parameters" do
      it "run migrations" do
        expect(SeedMigration::Migrator).to receive(:run_new_migrations)
        expect(SeedMigration::Migrator).to receive(:create_seed_file).once
        SeedMigration::Migrator.run_migrations
      end
    end
    context "with migration parameter" do
      it "run migrations" do
        Rails::Generators.invoke("seed_migration", ["foo", 1])
        expect_any_instance_of(SeedMigration::Migrator).to receive(:up).once
        expect(SeedMigration::Migrator).to receive(:create_seed_file).once
        SeedMigration::Migrator.run_migrations("1_foo.rb")
      end
    end
  end

  describe ".migrations_path" do
    context "with default path" do
      it "it should create migrations in db/data" do
        SeedMigration::Migrator.get_migration_files.each do |f|
          expect(File.split(File.dirname(f))[1]).to eq("data")
        end
      end
    end

    context "with custom path" do
      before(:all) do
        SeedMigration.migrations_path = "foo"
      end

      after(:all) do
        SeedMigration.migrations_path = "data"
      end

      it "it should create migrations in db/foo" do
        SeedMigration::Migrator.get_migration_files.each do |f|
          expect(File.split(File.dirname(f))[1]).to eq("foo")
        end
      end
    end
  end
end
