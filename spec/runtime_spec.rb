# frozen_string_literal: true

require "tmpdir"

RSpec.describe SchemaReaper::Runtime::Store do
  it "buffers writes and does not create the file until flush" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "usage.jsonl")
      store = described_class.new(path: path, flush_every: 200)

      store.record("users", "email")
      expect(File.exist?(path)).to be false

      store.flush
      expect(File.exist?(path)).to be true
      line = JSON.parse(File.read(path).lines.first)
      expect(line).to include("key" => "users.email")
      expect(line["at"]).to match(/\AT|^\d{4}-\d{2}-\d{2}T/)
    end
  end

  it "auto-flushes once the buffer reaches flush_every" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "usage.jsonl")
      store = described_class.new(path: path, flush_every: 3)

      3.times { |i| store.record("users", "col#{i}") }

      lines = File.readlines(path)
      expect(lines.size).to eq(3)
    end
  end

  it "appends across multiple flushes instead of overwriting" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "usage.jsonl")
      store = described_class.new(path: path, flush_every: 200)

      store.record("users", "a")
      store.flush
      store.record("users", "b")
      store.flush

      expect(File.readlines(path).size).to eq(2)
    end
  end

  it "creates the parent directory if it does not exist" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "nested", "deeper", "usage.jsonl")
      expect { described_class.new(path: path) }.not_to raise_error
      expect(File.directory?(File.dirname(path))).to be true
    end
  end
end

RSpec.describe SchemaReaper::Runtime::Tracker do
  # Exercise .note directly (sampling + recording), without going through
  # .install! -- that permanently prepends onto the real global
  # ActiveRecord::Base and is tested separately, once, below.
  around do |example|
    original_store = described_class.store
    original_rate = described_class.sample_rate
    example.run
    described_class.store = original_store
    described_class.sample_rate = original_rate
  end

  def fake_ar_class(table_name)
    Class.new do
      define_singleton_method(:table_name) { table_name }
      define_singleton_method(:respond_to?) { |m, *| m == :table_name || super(m) }
    end
  end

  it "records when the sample succeeds" do
    store = instance_double(SchemaReaper::Runtime::Store, record: nil)
    described_class.store = store
    described_class.sample_rate = 1.0 # always sample

    described_class.note(fake_ar_class("users"), :email)

    expect(store).to have_received(:record).with("users", "email")
  end

  it "does not record when the sample misses" do
    store = instance_double(SchemaReaper::Runtime::Store, record: nil)
    described_class.store = store
    described_class.sample_rate = 0.0 # never sample

    described_class.note(fake_ar_class("users"), :email)

    expect(store).not_to have_received(:record)
  end

  it "does nothing when no store is configured" do
    described_class.store = nil
    described_class.sample_rate = 1.0

    expect { described_class.note(fake_ar_class("users"), :email) }.not_to raise_error
  end

  it "does not record for a class with no table_name (not an AR model)" do
    store = instance_double(SchemaReaper::Runtime::Store, record: nil)
    described_class.store = store
    described_class.sample_rate = 1.0

    klass = Class.new # no table_name method at all
    described_class.note(klass, :email)

    expect(store).not_to have_received(:record)
  end

  it "swallows an error from a misbehaving store instead of breaking the request" do
    store = instance_double(SchemaReaper::Runtime::Store)
    allow(store).to receive(:record).and_raise(StandardError, "disk full")
    described_class.store = store
    described_class.sample_rate = 1.0

    expect { described_class.note(fake_ar_class("users"), :email) }.not_to raise_error
  end

  # .install! is deliberately NOT exercised in this shared spec process:
  # `ActiveRecord::Base.prepend(Hook)` is a one-way, permanent mutation of
  # the real global ActiveRecord::Base. Calling it here contaminates every
  # example that runs after it for the rest of the suite -- confirmed the
  # hard way: an earlier version of this file did call it, and a later,
  # unrelated example crashed the whole run with
  # RSpec::Mocks::OutsideOfExampleError because the prepended hook fired
  # against a stale double from a finished example. install!'s own logic
  # (the @installed guard, and the single `ActiveRecord::Base.prepend`
  # call) is simple enough to trust by inspection, and is verified for real
  # in an isolated one-off process instead -- see the PR description.

  it "Hook#_read_attribute calls .note before delegating to the real implementation" do
    # Tested against the Hook module directly, not a live ActiveRecord::Base
    # instance -- ActiveRecord needs a real DB connection to back
    # _read_attribute's `super`, which this suite doesn't have.
    store = instance_double(SchemaReaper::Runtime::Store, record: nil)
    described_class.store = store
    described_class.sample_rate = 1.0

    base = Class.new do
      define_singleton_method(:table_name) { "users" }
      def _read_attribute(name, *)
        "real value for #{name}"
      end
    end
    hooked = Class.new(base) { prepend SchemaReaper::Runtime::Tracker::Hook }

    result = hooked.new._read_attribute("email")

    expect(result).to eq("real value for email") # super's return value still comes through
    expect(store).to have_received(:record).with("users", "email")
  end
end
