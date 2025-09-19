require "rubygems"

# Use existing BUNDLE_GEMFILE if set (for version matrix testing), otherwise default to root Gemfile
unless ENV["BUNDLE_GEMFILE"]
  gemfile = File.expand_path("../../../../Gemfile", __FILE__)
  if File.exist?(gemfile)
    ENV["BUNDLE_GEMFILE"] = gemfile
  end
end

require "bundler"
Bundler.setup

$:.unshift File.expand_path("../../../../lib", __FILE__)
