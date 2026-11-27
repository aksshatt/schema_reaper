# frozen_string_literal: true

RSpec.describe "accuracy guards" do
  describe "stats-sampled analyzers" do
    def run(klass, rows, col)
      schema = fake_schema(fake_table("events", row_count: rows, columns: [{ name: "id" }, col]))
      klass.new(context_for(schema: schema)).call.first
    end

    it "lowers always_null confidence when ANALYZE only sampled the table" do
      small = run(SchemaReaper::Analyzers::AlwaysNullColumn, 10_000, { name: "x", null_fraction: 1.0 })
      big = run(SchemaReaper::Analyzers::AlwaysNullColumn, 5_000_000, { name: "x", null_fraction: 1.0 })

      expect(small.confidence).to eq(0.85)
      expect(big.confidence).to eq(0.7)
      expect(big.evidence.join).to include("sample")
    end

    it "does not claim 'every row' for a single-value column that has NULLs" do
      f = run(SchemaReaper::Analyzers::SingleValueColumn, 1_000,
              { name: "flag", distinct_values: 1, null_fraction: 0.4 })
      expect(f.evidence.join(" ")).to include("40.0% of rows are NULL")
      expect(f.evidence.join(" ")).not_to include("every row")
    end
  end

  describe SchemaReaper::Analyzers::MissingFkIndex do
    it "finds the referenced table in the same non-public schema" do
      schema = fake_schema(
        fake_table("billing.accounts", columns: [{ name: "id" }]),
        fake_table("billing.invoices", columns: [{ name: "id" }, { name: "account_id" }])
      )
      f = described_class.new(context_for(schema: schema)).call.first
      expect(f.confidence).to eq(described_class::REFERENT_CONFIDENCE)
      expect(f.evidence.first).to include("`billing.accounts`")
    end
  end

  describe SchemaReaper::Runtime::Tracker do
    around do |ex|
      store = described_class.store
      rate = described_class.sample_rate
      ex.run
      described_class.store = store
      described_class.sample_rate = rate
    end

    it "records public-qualified SQL under the bare table name" do
      seen = []
      fake = Object.new
      fake.define_singleton_method(:record) { |t, c| seen << "#{t}.#{c}" }
      described_class.store = fake
      described_class.sample_rate = 1.0

      described_class.note_sql('SELECT 1 FROM "public"."users"')
      expect(seen).to eq(["users.*"])
    end
  end

  describe SchemaReaper::Notifier do
    let(:finding) do
      SchemaReaper::Finding.new(type: :dead_column, table: "users", column: "x", severity: :low,
                                confidence: 0.5, evidence: [], suggested_fix: "")
    end
    let(:config) do
      SchemaReaper::AlertConfig.new.tap do |c|
        c.webhook_url = "https://hooks.slack.com/services/T/B/X"
        c.alert_on = :changes
      end
    end
    let(:state) do
      data = {}
      cache = double("cache")
      allow(cache).to receive(:read) { |k| data[k] }
      allow(cache).to receive(:write) { |k, v| data[k] = v }
      SchemaReaper::AlertState.new(cache: cache)
    end

    def http_returning(response)
      client = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil)
      allow(client).to receive(:request).and_return(response)
      [class_double(Net::HTTP, new: client), client]
    end

    it "treats a non-2xx webhook response as a failure and does not remember the report" do
      http, client = http_returning(instance_double(Net::HTTPBadRequest, code: "400", body: "invalid_blocks"))
      allow(Kernel).to receive(:warn)

      2.times { described_class.new([finding], config: config, http: http, state: state).deliver }

      expect(state.previous_ids).to be_nil
      expect(client).to have_received(:request).twice # the retry is not suppressed as "unchanged"
    end

    it "remembers the report once a channel accepted it" do
      http, = http_returning(instance_double(Net::HTTPOK, code: "200", body: "ok"))
      described_class.new([finding], config: config, http: http, state: state).deliver

      expect(state.previous_ids).to eq(["dead_column/users/x"])
    end
  end
end
