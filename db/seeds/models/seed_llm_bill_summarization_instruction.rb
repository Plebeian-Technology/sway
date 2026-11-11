# frozen_string_literal: true

require_relative "../seedable"

class SeedLlmBillSummarizationInstruction
  include Seedable

  DESCRIPTIONS = {
    "baltimore-maryland-united_states" =>
      "A 15-member legislative body governing the City of Baltimore. Ordinances (\"council bills\") " \
      "amend the Baltimore City Code or Charter; resolutions express the Council's position " \
      "without binding force. Council bills cite the city ordinance number (e.g., \"CB 23-0312\") " \
      "and the relevant Code title. Sponsorship cosignatures matter: a bill with five or more " \
      "cosponsors typically has the floor majority needed to pass. The Mayor signs or vetoes " \
      "ordinances; the Council can override a veto with 12 votes.",

    "maryland-maryland-united_states" =>
      "It is bicameral, comprising the House of Delegates (141 members) and the Senate (47 members). " \
      "State bills cite chapter titles and section numbers (e.g., \"HB 1234\" or \"SB 567\"). " \
      "The legislative session runs 90 days annually. A bill must pass both chambers in identical form, " \
      "be presented to the Governor, and either be signed or allowed to become law without signature. " \
      "Fiscal notes from the Department of Legislative Services accompany most bills.",

    "congress-congress-united_states" =>
      "A bicameral legislature comprising the House of Representatives (435 voting members) and " \
      "the Senate (100 members). Federal bills cite the session number and bill number (e.g., \"H.R. 2030\" " \
      "in the 118th session). A bill becomes law when it passes both chambers in identical form and is " \
      "signed by the President (or passed over a veto by two-thirds of each chamber). Public laws then " \
      "receive a P.L. citation."
  }.freeze

  NEWS_MEDIA_WEBSITE_URLS = {
    "baltimore-maryland-united_states" => [
      "https://www.thebanner.com/baltimore/",
      "https://www.wypr.org/",
      "https://www.baltimoresun.com/location/maryland/baltimore/",
      "https://www.thebanner.com/topic/politics-power/",
      "https://baltimorebrew.com/",
      "https://www.cbsnews.com/baltimore/",
      "https://www.wmar2news.com/",
      "https://foxbaltimore.com/",
      "https://www.southbmore.com/",
      "https://baltimorebeat.com/",
      "https://baltimorefishbowl.com/"
    ].freeze,

    "maryland-maryland-united_states" => [
      "https://marylandmatters.org/",
      "https://www.baltimoresun.com/location/maryland/",
      "https://www.thebanner.com/topic/politics-power/"
    ].freeze,

    "congress-congress-united_states" => [
      "https://thehill.com/",
      "https://www.politico.com/",
      "https://apnews.com/"
    ].freeze
  }.freeze

  WORKED_EXAMPLES = {
    "baltimore-maryland-united_states" => <<~MD.chomp,
      For a hypothetical Baltimore City Council ordinance "CB 23-0312, an
      ordinance amending Title 14 of the Baltimore City Code to require
      annual lead-paint inspections for rental units constructed before
      1978," a well-formed response would look like:

      ```json
      {
        "summary_markdown": "### Purpose\\n\\nCB 23-0312 amends Title 14 of the Baltimore City Code to require annual lead-paint inspections for rental units built before 1978.\\n\\n### Key Provisions\\n\\n- Landlords must arrange a certified inspection each year\\n- Inspection certificates must be provided to tenants\\n\\n### Who Is Affected\\n\\nTenants and landlords of residential rental units constructed prior to 1978 in Baltimore City.\\n\\n### Timing and Implementation\\n\\nThe ordinance applies citywide and takes effect 90 days after the Mayor's signature.",
        "full_breakdown_markdown": "### Section 14-301 (new). Annual inspection requirement.\\n\\nRequires every rental unit constructed before 1978 to receive a certified lead-paint inspection within twelve months of the ordinance taking effect, and annually thereafter. The certificate must be provided to the tenant within thirty days of inspection.\\n\\n### Section 14-302 (new). Penalties.\\n\\nFailure to provide an inspection certificate subjects the owner to a civil penalty of $500 per unit per month of non-compliance, payable to the Baltimore City General Fund.\\n\\n### Effective date.\\n\\n90 days after the Mayor's signature."
      }
      ```
    MD

    "maryland-maryland-united_states" => <<~MD.chomp,
      For a hypothetical Maryland General Assembly bill "HB 452, an act
      concerning Housing - Rental Property Lead Hazard Reduction, amending
      Environment Article Section 6-801 of the Annotated Code of Maryland,"
      a well-formed response would look like:

      ```json
      {
        "summary_markdown": "### Purpose\\n\\nHB 452 amends Environment Article Section 6-801 of the Annotated Code of Maryland to require annual lead-paint inspections for residential rental properties constructed before 1978.\\n\\n### Key Provisions\\n\\n- Property owners must obtain annual certified lead-paint inspections\\n- Verification certificates must be filed with the Maryland Department of the Environment\\n\\n### Who Is Affected\\n\\nResidential rental property owners and tenants across Maryland.\\n\\n### Timing and Implementation\\n\\nThe bill applies statewide and takes effect October 1 upon the Governor's signature.",
        "full_breakdown_markdown": "### Section 6-801 (amended). Lead hazard reduction compliance.\\n\\nRequires affected residential rental properties built before 1978 to satisfy annual lead inspection standards certified by an accredited inspector. Certificates must be submitted to the Maryland Department of the Environment within thirty days of inspection.\\n\\n### Section 6-802 (new). Civil penalties.\\n\\nViolations are subject to an administrative penalty assessed by the Department of up to $500 per unit for each month of noncompliance.\\n\\n### Effective date.\\n\\nOctober 1 following enactment."
      }
      ```
    MD

    "congress-congress-united_states" => <<~MD.chomp
      For a hypothetical United States Congress bill "H.R. 2030, a bill to
      amend Title 42 of the United States Code to require annual residential
      lead hazard inspections in pre-1978 housing," a well-formed response
      would look like:

      ```json
      {
        "summary_markdown": "### Purpose\\n\\nH.R. 2030 amends Title 42 of the United States Code to establish annual lead hazard risk assessment requirements for pre-1978 federally assisted rental housing.\\n\\n### Key Provisions\\n\\n- Mandates annual certified lead hazard risk assessments and clearance examinations\\n- Inspection records must be delivered to tenants and the Department of Housing and Urban Development\\n\\n### Who Is Affected\\n\\nFederally assisted rental housing providers, managers, and tenants nationwide.\\n\\n### Timing and Implementation\\n\\nThe requirements take effect nationwide one year after presidential enactment.",
        "full_breakdown_markdown": "### Section 4852d (amended). Residential lead hazard reduction.\\n\\nMandates annual risk assessments and clearance examinations for target housing covered by federal assistance programs. Inspection records must be maintained and transmitted to the Secretary of Housing and Urban Development.\\n\\n### Section 4852e (new). Enforcement and penalties.\\n\\nAuthorizes civil money penalties under the Lead-Based Paint Poisoning Prevention Act for failure to comply with certification schedules.\\n\\n### Effective date.\\n\\nOne year after the date of enactment."
      }
      ```
    MD
  }.freeze

  def self.run(locales = SwayLocale.all, force: false)
    seeder = new
    locales.map { |locale| seeder.seed(locale, force: force) }.compact
  end

  def seed(locale, force: false)
    makeup = DESCRIPTIONS[locale.name]
    return nil unless makeup

    doc = resolve_locale_document(locale.name)
    target_urls = doc ? doc.news_sources.pluck("url") : NEWS_MEDIA_WEBSITE_URLS.fetch(locale.name, [])
    instruction = locale.llm_bill_summarization_instruction || locale.build_llm_bill_summarization_instruction
    if seed_or_skip?(instruction, force: force)
      Rails.logger.info("SeedLlmBillSummarizationInstruction: skipping #{locale.name} — edited out-of-band since last seed")
      return instruction
    end

    instruction.legislative_body_makeup = makeup if makeup
    instruction.news_media_website_urls = target_urls
    instruction.worked_example = WORKED_EXAMPLES[locale.name] if WORKED_EXAMPLES[locale.name]
    instruction.save!
    stamp_seeded_at!(instruction)
    instruction
  end

  private

  def resolve_locale_document(name)
    SwayLocale::DocumentReader.current_for(name)
  rescue KeyError
    SwayLocale::DocumentReader.find(name)
  end
end
