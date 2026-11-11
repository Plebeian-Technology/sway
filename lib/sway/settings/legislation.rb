# frozen_string_literal: true

module Sway
  module Settings
    # @lat: [[legislation-settings-group-design#Why every attribute defaults to nil]]
    class Legislation < Base
      config_name "legislation"
      env_prefix ""

      attr_config legislation_root: nil
      coerce_types legislation_root: :string

      attr_config legislation_bills_raw_root: nil
      coerce_types legislation_bills_raw_root: :string

      attr_config legislation_bills_text_root: nil
      coerce_types legislation_bills_text_root: :string

      attr_config legislation_hearings_root: nil
      coerce_types legislation_hearings_root: :string

      attr_config legislation_law_root: nil
      coerce_types legislation_law_root: :string

      attr_config legislation_diffs_root: nil
      coerce_types legislation_diffs_root: :string

      attr_config legislation_prompt_dumps_root: nil
      coerce_types legislation_prompt_dumps_root: :string

      attr_config legislation_attachments_root: nil
      coerce_types legislation_attachments_root: :string

      attr_config tessdata_prefix: nil
      coerce_types tessdata_prefix: :string

      attr_config pdf_extractor_url: nil
      coerce_types pdf_extractor_url: :string

      # @lat: [[settings-groups#Why the freeze runs after a group's own repair]]
      on_load { self.class.freeze_mutable_attributes!(self) }
    end
  end
end
