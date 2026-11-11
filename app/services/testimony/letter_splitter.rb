# frozen_string_literal: true

module Testimony
  # @lat: [[extracted-text-phrase-matching#Telling a real letter's header from a forwarded one]]
  # @lat: [[extracted-text-phrase-matching#Handling multiline envelope headers and forwarded wrappers]]
  # @lat: [[testimony-letters#Attachment boundaries and the five-page constituent ceiling]]
  class LetterSplitter
    LETTER_MARKER = Testimony::ExtractedText.header_line_pattern("From:")
    MARKER_LOOKBACK_LINES = 4
    ATTACHMENT_BOUNDARY = /\f\n{3,}/
    PAGE_BREAK = /\f\n*/
    PAGE_TOP_LOOKAHEAD_LINES = 10

    PAGE_TOP_LETTER_CUE = /\A(?=(?-i:[A-Z]))(?:
      dear\b
      |to[ \t]+the[ \t]+(?:honorable\b[^.\n]{0,50}[,:]?\z|(?:[a-z]+[ \t]+){0,3}(?:city[ \t]+council|council|committee|chair(?:man|woman|person)?|members|mayor|senate|house[ \t]+of[ \t]+delegates|general[ \t]+assembly|delegation)(?![ \t]*'s\b)(?:[ \t]*[,:]|[ \t]*\z))
      |(?:the[ \t]+)?honorable\b(?![^\n]*\b(?:asked|questioned|stated|said|noted|voted|introduced|sponsored|amended)\b)[^.\n]{0,60}\z
      |good[ \t]+(?:morning|afternoon|evening)\b
      |members[ \t]+of[ \t]+the[ \t]+(?:[a-z]+[ \t]+){0,4}(?:council|committee|board|commission|senate|house|assembly|delegation)(?:[ \t]*[,:]|[ \t]*\z)
      |chair(?:man|woman|person)?[ \t]+(?-i:[A-Z])[a-zA-Z .'-]{0,35}(?:[,:]|[ \t]+and[ \t]+[^.\n]{0,40}[,:]?|[ \t]*\z)
      |memorandum\b
      |posi(?:ti|[ \t]+)on:\s*(?:supports?|opposes?|favorable|unfavorable|without[ \t]+recommendation)\b
      |(?:written[ \t]+)?testimony[ \t]+(?:in[ \t]+(?:support|opposition)|on[ \t]+(?:bill|council|hb|sb|cb)|for[ \t]+(?:bill|council|hb|sb|cb|fy)|against|to[ \t]+(?:the[ \t]+)?(?:baltimore|city|council|committee|honorable)|by\b)\b
      |open[ \t]+letter[ \t]+to\b
      |my[ \t]+name[ \t]+is\b
      |thank[ \t]+you[ \t]+for[ \t]+(?:this|the)[ \t]+opportunity[ \t]+to[ \t]+(?:talk|speak|provide[ \t]+testimony|submit|share|comment)\b
    )/ix

    Entry = Data.define(:position, :character_offset, :text)

    class << self
      def call(text)
        new(text).call
      end
    end

    def initialize(text)
      @text = text.to_s
    end

    def call
      return [] if @text.strip.empty?

      segments = Testimony::BoilerplateRemover.classify_segments(@text)
      base_segments = if segments.empty?
        [[0, @text.length, false]]
      else
        non_wrappers = segments.reject { |_start, _finish, is_wrapper| is_wrapper }
        non_wrappers.empty? ? segments : non_wrappers
      end

      expanded = [] #: Array[[Integer, Integer]]
      base_segments.each do |start, finish, _is_wrapper|
        split_attachment_boundaries(start, finish).each do |att_start, att_finish|
          split_overlong_segment(att_start, att_finish).each do |sub_start, sub_finish|
            expanded << [sub_start, sub_finish]
          end
        end
      end
      expanded = fold_print_header_stubs(expanded)

      expanded.each_with_index.map do |(start, finish), position|
        # @lat: [[rbs-signatures#Why a provably-safe value still needs a guard]]
        Entry.new(position: position, character_offset: start, text: @text[start...finish].to_s)
      end
    end

    private

    def split_attachment_boundaries(start, finish)
      seg = @text[start...finish].to_s
      breaks = [] #: Array[Integer]
      # @lat: [[rbs-signatures#Why a provably-safe value still needs a guard]]
      seg.scan(ATTACHMENT_BOUNDARY) do
        match = Regexp.last_match
        next unless match

        break_end = match.end(0)
        breaks << (start + break_end) if break_end
      end
      return [[start, finish]] if breaks.empty?

      result = [] #: Array[[Integer, Integer]]
      cursor = start
      breaks.each do |break_pos|
        part = @text[cursor...break_pos].to_s
        next if part.strip.empty?

        result << [cursor, break_pos]
        cursor = break_pos
      end
      if cursor < finish && !@text[cursor...finish].to_s.strip.empty?
        result << [cursor, finish]
      elsif result.any?
        last_pair = result.last
        result[-1] = [last_pair[0], finish] if last_pair
      end
      result.empty? ? [[start, finish]] : result
    end

    def fold_print_header_stubs(segments)
      return segments if segments.length <= 1

      folded = [] #: Array[[Integer, Integer]]
      pending_start = nil #: Integer?

      segments.each_with_index do |(sub_start, sub_finish), idx|
        effective_start = pending_start || sub_start
        seg_text = @text[sub_start...sub_finish].to_s

        if collapsible_print_header_stub?(seg_text)
          next_pair = segments[idx + 1]
          if next_pair && (Testimony::ExtractedText.starts_with_from_header?(@text[next_pair[0]...next_pair[1]].to_s) || folded.empty?)
            pending_start = effective_start
          elsif folded.any?
            last_pair = folded.last
            folded[-1] = [last_pair[0], sub_finish] if last_pair
            pending_start = nil
          else
            pending_start = effective_start
          end
        else
          folded << [effective_start, sub_finish]
          pending_start = nil
        end
      end

      if pending_start
        last_finish = segments.last&.at(1) || @text.length
        if folded.any?
          last_pair = folded.last
          folded[-1] = [last_pair[0], last_finish] if last_pair
        else
          folded << [pending_start, last_finish]
        end
      end

      folded
    end

    def collapsible_print_header_stub?(seg_text)
      Testimony::ExtractedText.clerk_print_header_stub?(seg_text)
    end

    def split_overlong_segment(start, finish)
      seg = @text[start...finish].to_s
      return [[start, finish]] unless Testimony::ExtractedText.over_constituent_page_limit?(seg)

      page_starts = [0]
      # @lat: [[rbs-signatures#Why a provably-safe value still needs a guard]]
      seg.scan(PAGE_BREAK) do
        match = Regexp.last_match
        next unless match

        match_end = match.end(0)
        page_starts << match_end if match_end && match_end < seg.length
      end
      return [[start, finish]] if page_starts.length <= 1

      starts_with_from = Testimony::ExtractedText.starts_with_from_header?(seg)
      first_page_end = page_starts[1] || seg.length
      current_letter_opened = starts_with_from || page_opens_new_letter?(seg[page_starts.first.to_i...first_page_end].to_s)
      split_offsets = [0]
      non_empty_pages_in_current = 0
      capped_current = false

      page_starts.each_with_index do |page_start, idx|
        page_end = page_starts[idx + 1] || seg.length
        page_text = seg[page_start...page_end].to_s
        next if page_text.strip.empty?

        if idx.zero?
          non_empty_pages_in_current = (Testimony::ExtractedText.print_header_stub?(page_text) && !page_opens_new_letter?(page_text) && !starts_with_from) ? 0 : 1
          next
        end

        if !starts_with_from && page_opens_new_letter?(page_text)
          split_offsets << page_start if non_empty_pages_in_current.positive?
          non_empty_pages_in_current = 1
          current_letter_opened = true
          capped_current = false
          next
        end
        next if Testimony::ExtractedText.print_header_stub?(page_text)

        if current_letter_opened &&
            !capped_current &&
            remaining_unheaded_pages(seg, page_starts, idx) > Testimony::ExtractedText::MAX_CONSTITUENT_PAGES &&
            (non_empty_pages_in_current >= Testimony::ExtractedText::MAX_CONSTITUENT_PAGES ||
              report_appendix_start?(seg[(split_offsets.last || 0)...page_start].to_s, page_text))
          split_offsets << page_start
          non_empty_pages_in_current = 1
          capped_current = true
          current_letter_opened = false
        else
          non_empty_pages_in_current += 1
        end
      end

      return [[start, finish]] if split_offsets.length <= 1

      result = [] #: Array[[Integer, Integer]]
      split_offsets.each_with_index do |rel_start, idx|
        rel_end = split_offsets[idx + 1] || seg.length
        result << [start + rel_start, start + rel_end]
      end
      result
    end

    def report_appendix_start?(preceding_text, page_text)
      trimmed_preceding = preceding_text.gsub(/[\f\s]+\z/, "")
      has_attachment_or_signoff =
        /\b(?:attached|attachment|enclosed|included|below|see[ \t]+the)\b/i.match?(trimmed_preceding) ||
        /\b(?:sincerely|respectfully|regards|cordially|truly|thank[ \t]+you)[,!]?[ \t]*\n+[ \t]*[A-Z][a-zA-Z .'-]+\z/i.match?(trimmed_preceding)
      return false unless has_attachment_or_signoff

      trimmed_page = page_text.lstrip
      return false if /\A(?:page[ \t]+\d+[ \t]+of[ \t]+(?:my|our|constituent)\b|(?:dear|I|we|my|our)\b)/i.match?(trimmed_page)

      /\A(?:page[ \t]+1\b|section[ \t]+1\b|table[ \t]+of[ \t]+contents\b|executive[ \t]+summary\b|introduction\b|background\b|methodology\b|appendix\b)/i.match?(trimmed_page) ||
        /\A[A-Z0-9][A-Z0-9 ,.:'&\/-]{4,80}\n/.match?(trimmed_page)
    end

    def remaining_unheaded_pages(seg, page_starts, current_idx)
      count = 0
      idx = current_idx
      while idx < page_starts.length
        page_start = page_starts.fetch(idx)
        page_end = page_starts[idx + 1] || seg.length
        page_text = seg[page_start...page_end].to_s
        break if page_opens_new_letter?(page_text)

        count += 1 unless Testimony::ExtractedText.print_header_stub?(page_text)
        idx += 1
      end
      count
    end

    def page_opens_new_letter?(page_text)
      lines = page_text.lines.map { |line| line.gsub(/\A(?:&nbsp;|\s)+|\s+\z/i, "") }.reject(&:empty?).first(PAGE_TOP_LOOKAHEAD_LINES)
      return false if lines.empty?

      first_content_line = /\A\d+\z/.match?(lines[0].to_s) ? lines[1].to_s : lines[0].to_s
      return false if /\A(?:appendix|exhibit|attachment|table|figure|chart|section|part|chapter)\b/i.match?(first_content_line)

      memo_fields = 0
      lines.each_with_index do |line, idx|
        memo_fields += 1 if /\A(?:to|from|date|subject|re)[;:]\s+\S/i.match?(line)
        return true if memo_fields >= 2

        if PAGE_TOP_LETTER_CUE.match?(line)
          if /\Athank[ \t]+you[ \t]+for[ \t]+(?:this|the)[ \t]+opportunity\b/i.match?(line)
            next if lines.length <= 5

            next_lines = lines[(idx + 1), 3].to_a
            next if next_lines.any? { |following| /\b(?:sincerely|respectfully|regards|cordially|truly|thank[ \t]+you|submitted[ \t]+by)\b/i.match?(following) }
          end

          return true
        end

        break if line.length > 65 && /[.!?]\z/.match?(line)
      end

      false
    end
  end
end
