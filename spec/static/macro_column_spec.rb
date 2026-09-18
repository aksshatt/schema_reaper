# frozen_string_literal: true

require "prism"

RSpec.describe "macro-derived column tokens" do
  let(:scanner) { SchemaReaper::Static::Scanner.new(SchemaReaper::Config.new(SchemaReaper::Config::DEFAULTS.dup)) }

  def tokens_for(source)
    result = Prism.parse(source)
    out = Set.new
    scanner.send(:collect_from_node, result.value, out)
    out
  end

  describe "has_secure_password" do
    it "derives password_digest for the bare form" do
      expect(tokens_for("has_secure_password")).to include("password_digest")
    end

    it "derives <attribute>_digest for a named attribute" do
      expect(tokens_for("has_secure_password :recovery_password")).to include("recovery_password_digest")
    end
  end

  describe "attr_encrypted" do
    # Confirmed against the gem's own attr_encrypted_default_options:
    # prefix: "encrypted_", suffix: "".
    it "derives the real default column, encrypted_<attribute>, a prefix not a suffix" do
      expect(tokens_for("attr_encrypted :ssn")).to include("encrypted_ssn")
    end

    it "also keeps the suffix form as a fallback for calls that override the naming" do
      expect(tokens_for("attr_encrypted :ssn")).to include("ssn_encrypted")
    end
  end

  describe "Lockbox" do
    # Lockbox's real macro is has_encrypted; lockbox_encrypts is not a method
    # that exists in the gem and would never match real code.
    it "recognizes has_encrypted, not a nonexistent lockbox_encrypts" do
      expect(tokens_for("has_encrypted :diagnosis")).to include("diagnosis_ciphertext")
    end

    it "derives the iv and tag columns too" do
      tokens = tokens_for("has_encrypted :diagnosis")
      expect(tokens).to include("diagnosis_iv", "diagnosis_tag")
    end
  end

  describe "encrypts (Rails-native)" do
    it "adds no extra column -- the bare attribute is already a symbol literal" do
      tokens = tokens_for("encrypts :patient_name")
      expect(tokens).to include("patient_name")
      expect(tokens).not_to include("patient_name_ciphertext", "patient_name_encrypted")
    end
  end

  it "does not invent a token for an unrelated method call" do
    expect(tokens_for("validates :email, presence: true")).not_to include(a_string_ending_with("_digest"))
  end
end
