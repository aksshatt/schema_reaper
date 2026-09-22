# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "generators/schema_reaper/install/install_generator"

RSpec.describe SchemaReaper::Generators::InstallGenerator do
  def build_generator(destination)
    generator = described_class.new
    generator.destination_root = destination
    generator
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @destination = dir
      FileUtils.mkdir_p(File.join(dir, "config"))
      example.run
    end
  end

  def read(relative_path)
    File.read(File.join(@destination, relative_path))
  end

  def exist?(relative_path)
    File.exist?(File.join(@destination, relative_path))
  end

  describe "#create_initializer" do
    it "writes a commented-out AlertConfig block, safe by default" do
      build_generator(@destination).create_initializer

      content = read("config/initializers/schema_reaper.rb")
      expect(content).to include("SchemaReaper::AlertConfig.configure do |config|")
      expect(content).to include("# config.emails =")
      expect(content).to include("# config.webhook_url =")
    end
  end

  describe "#create_manual_trigger" do
    it "writes the token-protected controller and adds the route" do
      generator = build_generator(@destination)
      File.write(File.join(@destination, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")

      generator.create_manual_trigger

      controller = read("app/controllers/schema_reaper_controller.rb")
      expect(controller).to include("class SchemaReaperController < ActionController::Base")
      expect(controller).to include("SchemaReaper::ScanJob.perform_later")
      expect(controller).to include("ActiveSupport::SecurityUtils.secure_compare")
      expect(controller).to include("Rails.application.credentials.dig(:schema_reaper, :trigger_token)")
      expect(controller).to include("ActiveSupport::EncryptedFile::MissingKeyError")

      routes = read("config/routes.rb")
      expect(routes).to include("post '/internal/schema_scan', to: 'schema_reaper#trigger'")
    end

    it "skips CSRF verification so a bare curl POST is not rejected by every standard Rails app" do
      # ActionController::Base itself gets `protect_from_forgery with: :exception`
      # wired onto it by Rails' own action_controller.request_forgery_protection
      # initializer whenever default_protect_from_forgery is on (the default since
      # Rails 5.2) -- every subclass inherits that before_action, this one
      # included, unless it explicitly opts out.
      generator = build_generator(@destination)
      File.write(File.join(@destination, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")

      generator.create_manual_trigger

      controller = read("app/controllers/schema_reaper_controller.rb")
      expect(controller).to include("skip_before_action :verify_authenticity_token, raise: false")
    end

    it "does not duplicate the route when the generator is re-run" do
      generator = build_generator(@destination)
      File.write(File.join(@destination, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")

      generator.create_manual_trigger
      generator.create_manual_trigger

      routes = read("config/routes.rb")
      expect(routes.scan("schema_reaper#trigger").size).to eq(1)
    end
  end

  describe "#detected_scheduler (real Bundler.locked_gems, not stubbed)" do
    # Every other #add_schedule example stubs detected_scheduler directly,
    # which never exercises the actual Bundler.locked_gems parsing this
    # method does. Test that for real here.
    it "returns nil in this gem's own bundle, which has neither whenever nor sidekiq-cron" do
      generator = build_generator(@destination)
      expect(generator.send(:detected_scheduler)).to be_nil
    end

    it "detects whenever from a real-shaped Bundler.locked_gems result" do
      generator = build_generator(@destination)
      fake_spec = Struct.new(:name).new("whenever")
      fake_locked_gems = instance_double(Bundler::LockfileParser, specs: [fake_spec])
      allow(Bundler).to receive(:locked_gems).and_return(fake_locked_gems)

      expect(generator.send(:detected_scheduler)).to eq(:whenever)
    end

    it "detects sidekiq-cron from a real-shaped Bundler.locked_gems result" do
      generator = build_generator(@destination)
      fake_spec = Struct.new(:name).new("sidekiq-cron")
      fake_locked_gems = instance_double(Bundler::LockfileParser, specs: [fake_spec])
      allow(Bundler).to receive(:locked_gems).and_return(fake_locked_gems)

      expect(generator.send(:detected_scheduler)).to eq(:sidekiq_cron)
    end

    it "does not crash when Bundler.locked_gems returns nil (no Gemfile.lock yet)" do
      generator = build_generator(@destination)
      allow(Bundler).to receive(:locked_gems).and_return(nil)

      expect(generator.send(:detected_scheduler)).to be_nil
    end

    it "does not crash when Bundler.locked_gems itself raises" do
      generator = build_generator(@destination)
      allow(Bundler).to receive(:locked_gems).and_raise(Bundler::GemfileNotFound)

      expect(generator.send(:detected_scheduler)).to be_nil
    end
  end

  describe "#add_schedule" do
    it "creates config/schedule.rb with a whenever entry when whenever is detected" do
      generator = build_generator(@destination)
      allow(generator).to receive(:detected_scheduler).and_return(:whenever)

      generator.add_schedule

      schedule = read("config/schedule.rb")
      expect(schedule).to include("every 3.months do")
      expect(schedule).to include('rake "schema_reaper:alert"')
      # Real wheneverize-generated files never have this -- whenever's CLI
      # evaluates schedule.rb through its own DSL, it doesn't need the file
      # to require itself.
      expect(schedule).not_to include('require "whenever"')
    end

    it "appends to an existing config/schedule.rb rather than clobbering it" do
      generator = build_generator(@destination)
      allow(generator).to receive(:detected_scheduler).and_return(:whenever)
      File.write(File.join(@destination, "config/schedule.rb"), "every 1.day do\n  runner \"Existing.task\"\nend\n")

      generator.add_schedule

      schedule = read("config/schedule.rb")
      expect(schedule).to include("Existing.task")
      expect(schedule).to include('rake "schema_reaper:alert"')
    end

    it "does not duplicate the whenever entry when the generator is re-run" do
      generator = build_generator(@destination)
      allow(generator).to receive(:detected_scheduler).and_return(:whenever)

      generator.add_schedule
      generator.add_schedule # re-running the generator is a normal recovery action

      schedule = read("config/schedule.rb")
      expect(schedule.scan('rake "schema_reaper:alert"').size).to eq(1)
    end

    it "creates config/schedule.yml with a sidekiq-cron entry when sidekiq-cron is detected" do
      generator = build_generator(@destination)
      allow(generator).to receive(:detected_scheduler).and_return(:sidekiq_cron)

      generator.add_schedule

      schedule = read("config/schedule.yml")
      expect(schedule).to include("schema_reaper_scan:")
      expect(schedule).to include('class: "SchemaReaper::ScanJob"')
      # Explicit rather than relying on sidekiq-cron's ActiveJob
      # ancestry auto-detection.
      expect(schedule).to include("active_job: true")
    end

    it "appends to an existing config/schedule.yml rather than clobbering it" do
      generator = build_generator(@destination)
      allow(generator).to receive(:detected_scheduler).and_return(:sidekiq_cron)
      File.write(File.join(@destination, "config/schedule.yml"),
                 "existing_job:\n  cron: \"0 0 * * *\"\n  class: \"Existing\"\n")

      generator.add_schedule

      schedule = read("config/schedule.yml")
      expect(schedule).to include("existing_job:")
      expect(schedule).to include("schema_reaper_scan:")
    end

    it "does not duplicate the sidekiq-cron entry when the generator is re-run" do
      generator = build_generator(@destination)
      allow(generator).to receive(:detected_scheduler).and_return(:sidekiq_cron)

      generator.add_schedule
      generator.add_schedule

      schedule = read("config/schedule.yml")
      expect(schedule.scan("schema_reaper_scan:").size).to eq(1)
    end

    it "prints a manual-setup notice instead of guessing when neither scheduler is present" do
      generator = build_generator(@destination)
      allow(generator).to receive(:detected_scheduler).and_return(nil)

      expect { generator.add_schedule }.to output(/no `whenever` or `sidekiq-cron` gem detected/).to_stdout
      expect(exist?("config/schedule.rb")).to be false
      expect(exist?("config/schedule.yml")).to be false
    end
  end

  describe "#warn_if_dev_scoped" do
    it "warns when the Gemfile scopes schema_reaper to group: :development" do
      generator = build_generator(@destination)
      File.write(File.join(@destination, "Gemfile"), "gem \"schema_reaper\", group: :development\n")

      expect { generator.warn_if_dev_scoped }.to output(/will not run in production/).to_stdout
    end

    it "warns for the block form too, not just the inline group: form" do
      # The gem's own line never mentions :development in this style -- the
      # `group :development do` line above it does. A naive per-line regex
      # misses this entirely, and it's the more common style in practice.
      generator = build_generator(@destination)
      File.write(File.join(@destination, "Gemfile"), <<~RUBY)
        source "https://rubygems.org"
        group :development do
          gem "schema_reaper"
        end
      RUBY

      expect { generator.warn_if_dev_scoped }.to output(/will not run in production/).to_stdout
    end

    it "says nothing when the gem is not dev-scoped" do
      generator = build_generator(@destination)
      File.write(File.join(@destination, "Gemfile"), "gem \"schema_reaper\"\n")

      expect { generator.warn_if_dev_scoped }.not_to output(/will not run in production/).to_stdout
    end

    it "says nothing when there is no Gemfile at all" do
      generator = build_generator(@destination)
      expect { generator.warn_if_dev_scoped }.not_to output(/will not run in production/).to_stdout
    end

    it "does not crash the generator when the Gemfile can't be parsed" do
      generator = build_generator(@destination)
      File.write(File.join(@destination, "Gemfile"), "this is not { valid ruby (((")

      expect { generator.warn_if_dev_scoped }.not_to raise_error
      expect { generator.warn_if_dev_scoped }.not_to output(/will not run in production/).to_stdout
    end
  end

  describe "#print_token_instructions" do
    it "prints one token and reuses the exact same value in both the credentials snippet and the curl example" do
      generator = build_generator(@destination)
      output = capture_stdout { generator.print_token_instructions }

      tokens = output.scan(/app-[0-9a-f]{64}/)
      expect(tokens.uniq.size).to eq(1)
      expect(output).to include("rails credentials:edit")
      expect(output).to include("trigger_token: #{tokens.first}")
      expect(output).to include("Authorization: Bearer #{tokens.first}")
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
