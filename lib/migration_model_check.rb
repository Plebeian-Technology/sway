# frozen_string_literal: true

require "prism"

# @lat: [[migrations-name-no-model#The gate]]
class MigrationModelCheck
  MIGRATION_DIRECTORIES = ["db/migrate", "db/data"].freeze

  MODEL_DIRECTORY = "app/models"

  # @lat: [[migrations-name-no-model#The calculators a stand-in cannot replace]]
  ALLOWED_REFERENCES = {
    "db/data/20260711000004_convert_duplicate_legislators_to_terms.rb" =>
      ["TermWindow", "SwayLocale::TermRulesRegistry"].freeze,
    "db/data/20260726000002_retire_untestified_draft_org_positions.rb" =>
      ["BillLlmProvisioning"].freeze,
    "db/data/20260731000001_correct_term_years_from_votes.rb" =>
      ["SwayLocale::TermRulesRegistry"].freeze,
    "db/data/20260731000002_correct_congress_term_lengths.rb" =>
      ["CongressChamber", "SwayLocale::JurisdictionRulesRegistry", "SwayLocale::TermRulesRegistry"].freeze,
    "db/data/20260801000001_merge_baltimore_seat_rows.rb" =>
      ["TermWindow", "SwayLocale::TermRulesRegistry"].freeze,
    "db/data/20260803000001_finish_merging_baltimore_seat_rows.rb" =>
      ["TermWindow", "SwayLocale::TermRulesRegistry"].freeze,
    "db/data/20260811140000_backfill_legislator_identifiers.rb" =>
      ["LegislatorIdentity", "SwayLocale::JurisdictionRulesRegistry", "SwayLocale::TermRulesRegistry"].freeze,
    "db/data/20260812000001_join_baltimore_council_rows_to_one_person.rb" =>
      ["LegislatorIdentity"].freeze
  }.freeze

  class Offence
    attr_reader :path, :line, :constant_name

    def initialize(path:, line:, constant_name:)
      @path = path
      @line = line
      @constant_name = constant_name
    end

    def to_s
      "#{path}:#{line} names #{constant_name}"
    end
  end

  class MissingAllowlistedPathError < StandardError; end

  class ConstantVisitor < Prism::Visitor
    attr_reader :definitions, :references

    def initialize
      super
      @definitions = []
      @references = []
      @nesting = []
    end

    def visit_class_node(node)
      record_definition(node) { super }
    end

    def visit_module_node(node)
      record_definition(node) { super }
    end

    def visit_constant_read_node(node)
      @references << [node.name.to_s, node.location.start_line]
      super
    end

    def visit_constant_path_node(node)
      name = qualified_name(node)
      if name
        @references << [name, node.location.start_line]
      else
        super
      end
    end

    private

    def record_definition(node)
      name = qualified_name(node.constant_path) || node.constant_path.slice
      @definitions << name
      @definitions << name.split("::").last
      @definitions << (@nesting + [name]).join("::")

      @nesting.push(name)
      yield
      @nesting.pop
    end

    def qualified_name(node)
      case node
      when Prism::ConstantReadNode
        node.name.to_s
      when Prism::ConstantPathNode
        own = node.name
        return nil if own.nil?
        return own.to_s if node.parent.nil?

        parent_name = qualified_name(node.parent)
        parent_name && "#{parent_name}::#{own}"
      end
    end
  end

  def initialize(root)
    @root = root
  end

  def offences
    assert_named_paths_exist!
    scanned_paths.flat_map { |path| offences_in(path) }
  end

  def scanned_paths
    @scanned_paths ||= MIGRATION_DIRECTORIES.flat_map { |directory|
      Dir.glob(File.join(root, directory, "*.rb")).map { |path| relative(path) }
    }.sort
  end

  def model_constant_names
    @model_constant_names ||= Dir.glob(File.join(root, MODEL_DIRECTORY, "**", "*.rb"))
      .flat_map { |path| definitions_in(File.read(path)) }
      .uniq
      .sort
  end

  private

  attr_reader :root

  def assert_named_paths_exist!
    missing = ALLOWED_REFERENCES.keys.reject { |path| File.file?(File.join(root, path)) }
    return if missing.empty?

    raise MissingAllowlistedPathError,
      "The named path(s) no longer exist on disk: #{missing.join(", ")}. " \
      "A renamed migration would otherwise switch its own exception off " \
      "silently. Update MigrationModelCheck::ALLOWED_REFERENCES."
  end

  def offences_in(relative_path)
    visitor = visit(File.read(File.join(root, relative_path)))
    defined_here = visitor.definitions.to_set
    allowed = ALLOWED_REFERENCES.fetch(relative_path, [])
    model_names = model_constant_names.to_set

    visitor.references.filter_map { |name, line|
      next unless model_names.include?(name)
      next if defined_here.include?(name)
      next if allowed.include?(name)

      Offence.new(path: relative_path, line: line, constant_name: name)
    }
  end

  def definitions_in(source)
    visit(source).definitions
  end

  def visit(source)
    visitor = ConstantVisitor.new
    Prism.parse(source).value.accept(visitor)
    visitor
  end

  def relative(path)
    path.delete_prefix("#{root}/")
  end
end
