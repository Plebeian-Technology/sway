# frozen_string_literal: true

# @lat: [[registration-funnel-telemetry#Bot traffic classification]]
module BotUserAgent
  PATTERN = /
    (?<!cu)bot\b | crawl | spider | slurp | scraper | archiver | facebookexternalhit |
    headless | phantomjs | puppeteer | playwright | selenium | lighthouse | pagespeed |
    \bcurl\b | \bwget\b | python | aiohttp | httpx | go-http-client | \bjava\/ |
    okhttp | node-fetch | axios | undici | libwww-perl | \bruby\b | faraday |
    postmanruntime | insomnia | scrapy
  /ix

  def self.bot?(user_agent)
    ua = user_agent.to_s.scrub.strip
    return true if ua.empty?

    PATTERN.match?(ua)
  end
end
