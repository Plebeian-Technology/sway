---
lat:
  mode: explanation
---
# News mobile links

Native bill detail and Bill of the Month screens display approved news articles as independent reading cards outside summary and testimony blocks.

## Placement outside summary and testimony

Native bill screens separate external journalism from generated summaries and stakeholder testimony to preserve reader clarity.

Legislative summaries synthesize bill text and amendments. Hearing testimonies capture formal stakeholder positions submitted to committee proceedings. Related news articles provide external journalistic context, investigations, and community reporting. Presenting related news in a dedicated card on the Summaries tab, ahead of the organization positions and away from Sway's own summary on the Bill tab, ensures readers understand the provenance of each information layer without conflating press reporting with official hearing records or bill text.

## Mobile link safety and external navigation

Native article links validate URL schemes before invoking external browser navigation.

Mobile devices process external navigation through platform URL handlers. Unchecked URLs could trigger arbitrary schemes or intent handlers. Using WHATWG URL parsing, the component verifies that article URLs strictly use standard `http:` or `https:` protocols and contain no embedded credentials. Articles bearing unsafe schemes render as inert text rather than interactive link targets, preserving accessibility without exposing readers to malicious navigation.

## Zero-node suppression and screen lifecycle

Native bill screens render zero nodes when approved articles are absent or when transitioning between bills and locales.

When a bill carries no approved articles, the related articles component returns null, emitting no container, headers, or spacing into the scroll view. On the featured bill screen, changing locales refreshes bootstrap data, and the newly featured bill remounts the screen's keyed detail body, which drops the previous bill's article list until the new bill's detail arrives. On the bill detail screen, navigating between bills re-fetches bill records and resets cached articles, preventing stale news items from persisting across route transitions.
