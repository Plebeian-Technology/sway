# frozen_string_literal: true

require "nokogiri"

# @lat: [[fetch-law-service-design#AkomaNtosoParser: the same namespace strategy, at the XML-parsing layer]]
class FetchLawService
  class AkomaNtosoParser
    # @lat: [[fetch-law-service-design#Why AkomaNtosoParser caps XML input at 50MB]]
    MAX_XML_BYTES = 50 * 1024 * 1024

    def initialize(xml_path, corpus_type:)
      size = xml_path.size
      if size > MAX_XML_BYTES
        raise StageError,
          "fetch_law: XML too large (#{size} bytes > #{MAX_XML_BYTES} byte cap) at #{xml_path}"
      end
      @xml_path = xml_path
      @corpus_type = corpus_type
      @doc = Nokogiri::XML(xml_path.read) { |cfg| cfg.strict }
      @doc.remove_namespaces!
    end

    def parse
      articles = [] #: Array[article_payload]
      sections = [] #: Array[section_payload]

      @doc.xpath("//container").each do |container|
        art_num = text_of(container, "num")
        art_heading = text_of(container, "heading")
        next if art_num.empty?

        articles << {num: art_num, heading: art_heading}
        art_slug = slugify_article(art_num)
        article_label = art_heading.empty? ? "Article #{art_num}" : "Article #{art_num} - #{art_heading}"

        container.xpath("section").each do |section|
          sec_num = text_of(section, "num")
          sec_heading = text_of(section, "heading")
          next if sec_num.empty?

          key = "art_#{art_num}__sec_#{sec_num}"
          rel_path = "#{@corpus_type}/#{art_slug}/#{slugify_section(sec_num)}"
          sec_md = render_section_md(section, article_label, sec_num, sec_heading)

          sections << {
            key: key,
            article: art_heading.empty? ? art_num : art_heading,
            section: sec_num,
            title: sec_heading.empty? ? sec_num : sec_heading,
            body: sec_md,
            source_path: rel_path
          }
        end
      end

      {articles: articles, sections: sections}
    end

    private

    def slugify_article(num_text)
      if @corpus_type == "charter"
        "art-#{num_text}"
      else
        safe = num_text.to_s.tr(" /", "--")
        begin
          format("art-%02d", Integer(safe))
        rescue ArgumentError, TypeError
          "art-#{safe}"
        end
      end
    end

    def slugify_section(num_text)
      "sec-#{num_text}.md"
    end

    def render_section_md(section_node, article_label, sec_num, sec_heading)
      text_nodes = section_node.xpath("text")
      content = text_nodes.map { |n| n.content.to_s.strip }.reject(&:empty?).join("\n\n")
      heading_line = sec_heading.empty? ? "## Section #{sec_num}" : "## Section #{sec_num}. #{sec_heading}"
      "# #{article_label}\n\n#{heading_line}\n\n#{content}"
    end

    def text_of(node, name)
      child = node.at_xpath(name)
      return "" if child.nil?

      child.content.to_s.strip
    end
  end
end
