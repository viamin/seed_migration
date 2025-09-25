require "spec_helper"

describe "Seeds.rb regression test" do
  before(:all) do
    # Clean slate
    SeedMigration::DataMigration.delete_all
    User.delete_all
    Product.delete_all
    
    # Clear registrar
    SeedMigration.registrar.clear
  end

  after(:all) do
    # Cleanup
    SeedMigration::DataMigration.delete_all
    User.delete_all 
    Product.delete_all
    SeedMigration.registrar.clear
    if File.exist?(SeedMigration::Migrator::SEEDS_FILE_PATH)
      FileUtils.rm(SeedMigration::Migrator::SEEDS_FILE_PATH)
    end
  end

  context "incremental migrations and seeds.rb preservation" do
    before(:all) do
      SeedMigration.update_seeds_file = true
      SeedMigration.ignore_ids = false
    end
    
    before(:each) do
      # Ensure clean state for each test
      User.delete_all
      Product.delete_all
      SeedMigration.registrar.clear
      if File.exist?(SeedMigration::Migrator::SEEDS_FILE_PATH)
        FileUtils.rm(SeedMigration::Migrator::SEEDS_FILE_PATH)
      end
    end

    it "preserves existing seed data when running new migrations" do
      # Mock Rails environment for this test
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      
      # === MIGRATION 1: Create some users ===
      # Simulate first migration that creates users and registers User model
      2.times { |i| User.create!(username: "user_#{i}") }
      SeedMigration.register User
      
      # Run first migration - should generate seeds.rb with users  
      SeedMigration::Migrator.create_seed_file
      
      # Ensure file exists
      expect(File.exist?(SeedMigration::Migrator::SEEDS_FILE_PATH)).to be true
      first_contents = File.read(SeedMigration::Migrator::SEEDS_FILE_PATH)
      
      expect(first_contents).to include("User.create")
      expect(first_contents).to include("user_0")
      expect(first_contents).to include("user_1")
      expect(first_contents).not_to include("Product.create")

      # === SIMULATION OF THE ACTUAL PROBLEM ===
      # What happens in production: registrations can get cleared/reset
      # This simulates the scenario where a new migration runs but previous
      # model registrations are not preserved
      SeedMigration.registrar.clear  # This is what causes the bug!
      
      # === MIGRATION 2: Create some products ===  
      # Simulate second migration that creates products and registers Product model
      # The previous User registration is now gone!
      2.times { |i| Product.create! }
      SeedMigration.register Product  # Only Product is registered now
      
      # Run second migration - this should preserve users BUT it won't because
      # User is no longer registered, so create_seed_file will only see Product data
      SeedMigration::Migrator.create_seed_file
      second_contents = File.read(SeedMigration::Migrator::SEEDS_FILE_PATH)
      
      # This is the BUG: User data gets lost because User model is no longer registered
      expect(second_contents).to include("User.create"), "REGRESSION: User data should be preserved from first migration even if User model is no longer registered"
      expect(second_contents).to include("user_0"), "REGRESSION: Specific user data should be preserved"
      expect(second_contents).to include("user_1"), "REGRESSION: Specific user data should be preserved"
      expect(second_contents).to include("Product.create"), "New product data should be added"
    end

    it "warns about unregistered models with seed data" do
      # Mock Rails environment for this test
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      
      # Create some data without registering the models
      User.create!(username: "unregistered_user")
      Product.create!
      
      # Only register User, leaving Product unregistered
      SeedMigration.register User
      
      # Capture warnings by checking logger output
      logger_output = StringIO.new
      allow(SeedMigration::Migrator).to receive(:logger).and_return(Logger.new(logger_output))
      
      # Generate seeds file - should warn about unregistered Product model
      SeedMigration::Migrator.create_seed_file
      
      # Check warning was logged
      warning_text = logger_output.string
      expect(warning_text).to include("⚠️  SEED MIGRATION WARNING")
      expect(warning_text).to include("Found seed data for unregistered models: Product")
      expect(warning_text).to include("SeedMigration.register Product")
      expect(warning_text).to include("Model registrations were cleared/reset")
      
      # Ensure the unregistered model's data is still preserved
      contents = File.read(SeedMigration::Migrator::SEEDS_FILE_PATH)
      expect(contents).to include("User.create")
      expect(contents).to include("Product.create"), "Unregistered model data should still be preserved"
    end

    it "does not warn when all models with data are registered" do
      # Mock Rails environment for this test
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      
      # Create data and register all models
      User.create!(username: "registered_user")
      Product.create!
      
      SeedMigration.register User
      SeedMigration.register Product
      
      # Capture warnings
      logger_output = StringIO.new
      allow(SeedMigration::Migrator).to receive(:logger).and_return(Logger.new(logger_output))
      
      # Generate seeds file - should NOT warn since all models are registered
      SeedMigration::Migrator.create_seed_file
      
      # Check no warning was logged
      warning_text = logger_output.string
      expect(warning_text).not_to include("⚠️  SEED MIGRATION WARNING")
      expect(warning_text).not_to include("unregistered models")
      
      # Ensure both models are in seeds.rb
      contents = File.read(SeedMigration::Migrator::SEEDS_FILE_PATH)
      expect(contents).to include("User.create")
      expect(contents).to include("Product.create")
    end
  end
end