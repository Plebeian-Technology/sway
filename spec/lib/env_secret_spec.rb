# frozen_string_literal: true

require "rails_helper"

# @lat: [[env-secret-blank-value-handling#Why EnvSecret.fetch! raises instead of returning nil]]
RSpec.describe EnvSecret do
  let(:key) { "SWAY_ENV_SECRET_SPEC_KEY" }

  around do |example|
    had = ENV.key?(key)
    previous = ENV[key]
    begin
      example.run
    ensure
      had ? ENV[key] = previous : ENV.delete(key)
    end
  end

  describe ".read" do
    it "strips a trailing newline, the ordinary `kamal env push` outcome" do
      ENV[key] = "sk-ant-abc123\n"

      expect(described_class.read(key)).to eq("sk-ant-abc123")
    end

    it "strips leading and trailing whitespace of every kind" do
      ENV[key] = " \t\r\nsk-ant-abc123\r\n\t "

      expect(described_class.read(key)).to eq("sk-ant-abc123")
    end

    it "leaves interior whitespace alone" do
      ENV[key] = "  two words\n"

      expect(described_class.read(key)).to eq("two words")
    end

    it "returns nil -- not \"\" -- when the variable is unset" do
      ENV.delete(key)

      expect(described_class.read(key)).to be_nil
    end

    it "returns nil when the variable is set to the empty string" do
      ENV[key] = ""

      expect(described_class.read(key)).to be_nil
    end

    it "returns nil when the variable is whitespace-only" do
      ENV[key] = "\n"

      expect(described_class.read(key)).to be_nil
    end
  end

  describe ".read_base64" do
    it "round-trips a strict Base64 encoding of a multiline PEM payload, interior newlines intact" do
      # Generated rather than embedded: a PEM literal is a gitleaks private-key finding.
      pem = OpenSSL::PKey::EC.generate("prime256v1").private_to_pem
      with_env(key => Base64.strict_encode64(pem)) do
        expect(described_class.read_base64(key)).to eq(pem.strip)
      end
    end

    it "returns nil when the variable is unset" do
      with_env(key => nil) do
        expect(described_class.read_base64(key)).to be_nil
      end
    end

    it "returns nil when the variable is blank" do
      with_env(key => "") do
        expect(described_class.read_base64(key)).to be_nil
      end
    end

    it "returns nil when the variable is whitespace-only" do
      with_env(key => "  \n") do
        expect(described_class.read_base64(key)).to be_nil
      end
    end

    it "returns nil and logs an error naming the variable, never its value, when the value is not strict Base64" do
      pem = "-----BEGIN PRIVATE KEY-----\nMIGTAgEAMBMGB\n-----END PRIVATE KEY-----\n"
      logger = instance_double(Logger, error: nil)
      allow(Rails).to receive(:logger).and_return(logger)

      with_env(key => pem) do
        expect(described_class.read_base64(key)).to be_nil
      end

      expect(logger).to have_received(:error) do |message|
        expect(message).to include(key)
        expect(message).not_to include(pem)
      end
    end
  end

  describe ".fetch!" do
    it "returns the stripped value" do
      ENV[key] = "ghp_token\n"

      expect(described_class.fetch!(key)).to eq("ghp_token")
    end

    it "raises KeyError when unset, preserving ENV.fetch's fail-loud contract" do
      ENV.delete(key)

      expect { described_class.fetch!(key) }.to raise_error(KeyError, /#{key}/)
    end

    it "raises KeyError when whitespace-only, which bare ENV.fetch would return" do
      ENV[key] = "  \n"

      expect { described_class.fetch!(key) }.to raise_error(KeyError, /#{key}/)
    end

    it "names the variable without ever echoing its value" do
      ENV[key] = "  "

      expect { described_class.fetch!(key) }.to raise_error(KeyError) do |error|
        expect(error.message).to include(key)
      end
    end
  end

  describe ".open_states_api_key!" do
    it "returns the stripped OPEN_STATES_API_KEY value" do
      ENV["OPEN_STATES_API_KEY"] = "os_key_123\n"
      expect(described_class.open_states_api_key!).to eq("os_key_123")
    ensure
      ENV.delete("OPEN_STATES_API_KEY")
    end

    it "raises KeyError when OPEN_STATES_API_KEY is not set" do
      ENV.delete("OPEN_STATES_API_KEY")
      expect { described_class.open_states_api_key! }.to raise_error(KeyError, /OPEN_STATES_API_KEY/)
    end
  end

  describe ".congress_gov_api_key!" do
    it "returns the stripped CONGRESS_GOV_API_KEY value" do
      ENV["CONGRESS_GOV_API_KEY"] = "congress_key_123\n"
      expect(described_class.congress_gov_api_key!).to eq("congress_key_123")
    ensure
      ENV.delete("CONGRESS_GOV_API_KEY")
    end

    it "raises KeyError when CONGRESS_GOV_API_KEY is not set" do
      ENV.delete("CONGRESS_GOV_API_KEY")
      expect { described_class.congress_gov_api_key! }.to raise_error(KeyError, /CONGRESS_GOV_API_KEY/)
    end
  end

  describe ".brave_search_api_key!" do
    it "returns the stripped BRAVE_SEARCH_API_KEY value when set" do
      ENV["BRAVE_SEARCH_API_KEY"] = " \tbsa_key_123\n "
      expect(described_class.brave_search_api_key!).to eq("bsa_key_123")
    ensure
      ENV.delete("BRAVE_SEARCH_API_KEY")
    end

    it "raises KeyError when BRAVE_SEARCH_API_KEY is unset" do
      ENV.delete("BRAVE_SEARCH_API_KEY")
      expect { described_class.brave_search_api_key! }.to raise_error(KeyError, /BRAVE_SEARCH_API_KEY/)
    end

    it "raises KeyError when BRAVE_SEARCH_API_KEY is whitespace-only" do
      ENV["BRAVE_SEARCH_API_KEY"] = "  \n"
      expect { described_class.brave_search_api_key! }.to raise_error(KeyError, /BRAVE_SEARCH_API_KEY/)
    ensure
      ENV.delete("BRAVE_SEARCH_API_KEY")
    end
  end
end
