# frozen_string_literal: true

RSpec.describe "gem-owned tables" do
  it "treats Rails 8 solid_* tables as owned when the gem is bundled" do
    owned = SchemaReaper::GemAwareness.owned_tables(installed: %w[solid_queue solid_cache])
    expect(owned).to include("solid_queue_jobs", "solid_cache_entries")
    expect(owned).not_to include("solid_cable_messages")
  end

  it "keeps column analyzers off every column of an owned table" do
    schema = fake_schema(fake_table("solid_queue_jobs", row_count: 10_000, columns: [
                                      { name: "id" }, { name: "concurrency_key", null_fraction: 1.0 }
                                    ]))
    ctx = context_for(schema: schema, gem_owned_tables: Set["solid_queue_jobs"])

    expect(SchemaReaper::Analyzers::DeadColumn.new(ctx).call).to be_empty
    expect(SchemaReaper::Analyzers::AlwaysNullColumn.new(ctx).call).to be_empty
  end

  it "reserves discard's discarded_at on any table that has it" do
    reserved = SchemaReaper::GemAwareness.reserved_columns(
      installed: %w[discard], tables: [fake_table("posts", columns: [{ name: "id" }, { name: "discarded_at" }])]
    )
    expect(reserved["posts"]).to include("discarded_at")
  end
end
