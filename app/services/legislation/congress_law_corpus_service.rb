# frozen_string_literal: true

require "tmpdir"
require "uri"
require "zip"
require "zlib"

# @lat: [[legislation-pipeline#Congress law corpus acquisition]]
module Legislation
  class CongressLawCorpusService
    CATALOG_URL = "https://uscode.house.gov/download/download.shtml"
    MAX_CATALOG_BYTES = 2 * 1024 * 1024
    MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
    MAX_TITLE_BYTES = 256 * 1024 * 1024
    MAX_CORPUS_BYTES = 2 * 1024 * 1024 * 1024
    MAX_ARCHIVES = 100
    CHUNK_BYTES = 64 * 1024

    def initialize(law_root:, http: nil)
      @law_root = law_root
      @http = http || Sway::FaradayStack.build(
        base_url: CATALOG_URL,
        timeout_seconds: 120,
        retry_options: Sway::FaradayStack::OPEN_DATA_DEFAULTS
      )
    end

    def call
      @law_root.mkpath
      File.open(@law_root.join(".congress-corpus.lock"), "w") do |lock|
        lock.flock(File::LOCK_EX)
        raw_root = @law_root.join("raw")
        if corpus_present?(raw_root)
          yield raw_root
          next
        end

        Dir.mktmpdir(".congress-corpus-", @law_root.to_s) do |temp|
          staged_root = Pathname.new(temp).join("raw")
          staged_root.mkpath
          @extracted_bytes = 0
          archive_urls.each do |url|
            archive = Pathname.new(temp).join("title.zip")
            download(url, archive, MAX_ARCHIVE_BYTES)
            extract_title(archive, staged_root, url)
          end
          raise StageError, "fetch_law: US Code download contained no XML" unless corpus_present?(staged_root)

          yield staged_root
          FileUtils.rm_r(raw_root) if raw_root.directory?
          File.rename(staged_root, raw_root)
        end
      end
    rescue Faraday::Error, Zip::Error, Zlib::Error, URI::InvalidURIError => e
      raise StageError, "fetch_law: US Code corpus acquisition failed: #{e.message.to_s[0, 300]}"
    end

    private

    def corpus_present?(root)
      Pathname.glob(root.join("**", "*.{xml,json}").to_s).any?
    end

    def archive_urls
      catalog = @law_root.join(".congress-catalog.html")
      download(CATALOG_URL, catalog, MAX_CATALOG_BYTES)
      document = Nokogiri::HTML(catalog.read)
      urls = document.css("a[href]").filter_map do |link|
        title = link.ancestors(".uscitem").first&.at_css(".usctitle")&.text.to_s
        next if title.match?(/\[Reserved\]/i)

        href = link["href"].to_s
        next unless href.match?(/xml_usc\d+(?:@[^\/?]+)?\.zip\z/)

        uri = URI.join(CATALOG_URL, href)
        unless uri.scheme == "https" && uri.host == "uscode.house.gov" && uri.port == 443 &&
            uri.userinfo.nil? && uri.path.to_s.start_with?("/download/releasepoints/") && uri.query.nil?
          raise StageError, "fetch_law: unexpected US Code archive URL"
        end
        uri.to_s
      end.uniq
      if urls.empty? || urls.size > MAX_ARCHIVES
        raise StageError, "fetch_law: US Code catalog has an invalid archive count (#{urls.size})"
      end
      urls
    ensure
      catalog&.delete if catalog&.exist?
    end

    def download(url, destination, limit)
      File.open(destination, "wb") do |file|
        response = @http.get(url) do |request|
          request.options.on_data = proc do |chunk, total, _env|
            if total == chunk.bytesize
              file.rewind
              file.truncate(0)
            end
            raise StageError, "fetch_law: US Code download exceeds #{limit} bytes" if total > limit

            file.write(chunk)
          end
        end
        unless response.status == 200
          raise StageError, "fetch_law: US Code download returned HTTP #{response.status}"
        end
        if response.headers["content-length"].to_i > limit
          raise StageError, "fetch_law: US Code download advertises more than #{limit} bytes"
        end
      end
    end

    def extract_title(archive, destination, url)
      Zip::File.open(archive.to_s) do |zip|
        entries = zip.entries
        unless entries.size == 1 && entries.first.name.match?(/\Ausc\d+[aA]?\.xml\z/) && entries.first.file?
          raise StageError, "fetch_law: unexpected US Code ZIP contents"
        end
        entry = entries.first
        expected = URI.parse(url).path.to_s[/xml_(usc\d+[aA]?)/, 1]
        unless entry.name == "#{expected}.xml"
          raise StageError, "fetch_law: US Code archive title does not match its catalog entry"
        end
        if entry.size > MAX_TITLE_BYTES || @extracted_bytes + entry.size > MAX_CORPUS_BYTES
          raise StageError, "fetch_law: expanded US Code corpus exceeds its byte cap"
        end
        target = destination.join(entry.name)
        raise StageError, "fetch_law: duplicate US Code title #{entry.name}" if target.exist?

        title_bytes = 0
        checksum = 0
        entry.get_input_stream do |input|
          File.open(target, "wb") do |output|
            while (chunk = input.read(CHUNK_BYTES))
              checksum = Zlib.crc32(chunk, checksum)
              title_bytes += chunk.bytesize
              @extracted_bytes += chunk.bytesize
              if title_bytes > MAX_TITLE_BYTES || @extracted_bytes > MAX_CORPUS_BYTES
                raise StageError, "fetch_law: expanded US Code corpus exceeds its byte cap"
              end
              output.write(chunk)
            end
          end
        end
        if title_bytes != entry.size || checksum != entry.crc
          raise StageError, "fetch_law: incomplete US Code title #{entry.name}"
        end
      end
    end
  end
end
