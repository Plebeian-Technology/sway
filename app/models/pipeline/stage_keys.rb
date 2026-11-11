# frozen_string_literal: true

module Pipeline
  # @lat: [[legislation-pipeline-fail-fast-integrity-checks#Pipeline::StageKeys]]
  # @lat: [[legislation-pipeline#Fail-fast on drift]]
  module StageKeys
    KEY_TO_SYMBOL = {
      "fetch-bills" => :fetch_bills,
      "fetch-law" => :fetch_law,
      "extract-text" => :extract_text,
      "parse-sections" => :parse_sections,
      "generate-diffs" => :generate_diffs,
      "fetch-hearings" => :fetch_hearings,
      "clean-testimony" => :clean_testimony,
      "summarize-bill" => :summarize
    }.freeze #: Hash[String, stage_symbol]

    SYMBOL_TO_KEY = KEY_TO_SYMBOL.invert.freeze #: Hash[stage_symbol, stage_key]

    # @lat: [[legislation-pipeline-fail-fast-integrity-checks#Pipeline::StageKeys]]
    KEY_TO_SYMBOL.each do |key, symbol|
      unless SYMBOL_TO_KEY[symbol] == key
        raise "Pipeline::StageKeys: round-trip drift — KEY_TO_SYMBOL[#{key.inspect}] = #{symbol.inspect} " \
          "but SYMBOL_TO_KEY[#{symbol.inspect}] = #{SYMBOL_TO_KEY[symbol].inspect}"
      end
    end

    # @lat: [[legislation-pipeline-fail-fast-integrity-checks#Pipeline::StageKeys]]
    stage_keys_symbols = SYMBOL_TO_KEY.keys.sort
    dag_order_symbols = RunLegislationPipelineJob::DAG_ORDER.sort
    if stage_keys_symbols != dag_order_symbols
      raise "Pipeline::StageKeys: SYMBOL_TO_KEY.keys (#{stage_keys_symbols.inspect}) drift from " \
        "RunLegislationPipelineJob::DAG_ORDER (#{dag_order_symbols.inspect})"
    end

    def self.to_symbol(key)
      KEY_TO_SYMBOL.fetch(key.to_s)
    end

    def self.to_key(symbol)
      SYMBOL_TO_KEY.fetch(symbol.to_sym)
    end
  end
end
