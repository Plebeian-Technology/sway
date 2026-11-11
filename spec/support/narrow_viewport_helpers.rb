# frozen_string_literal: true

# @lat: [[tab-strips-at-narrow-viewports#Why the layout backstops need a real browser]]
module NarrowViewportHelpers
  # The narrowest viewport the phase's UI contract names.
  NARROW_VIEWPORT_WIDTH = 320

  # Tall enough that nothing on these pages is below the fold for a click, so
  # only the WIDTH is under test.
  NARROW_VIEWPORT_HEIGHT = 2400

  # Sub-pixel layout rounds a fitting box a fraction over its container, so a
  # one-pixel overhang is not sideways scroll.
  OVERFLOW_TOLERANCE_PX = 1

  # Chrome will NOT narrow the window this far. manage.window.resize_to(320, …)
  # stops at the browser's own 500px minimum and still reports success, so a
  # check built on it measures a viewport more than half again as wide as the
  # one it claims and can never fail the way the contract intends (measured
  # 2026-08-16: resize_to(320) → window.innerWidth 500). The DevTools metrics
  # override sets the layout viewport itself and has no minimum.
  def with_narrow_viewport(width: NARROW_VIEWPORT_WIDTH, height: NARROW_VIEWPORT_HEIGHT)
    browser = page.driver.browser
    begin
      browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride",
        width: width, height: height, deviceScaleFactor: 1, mobile: false
      )
      yield
    ensure
      browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    end
  end

  # Visits inside a narrowed viewport and proves the narrowing survived the
  # navigation. Without this line a metrics override that stopped applying
  # would hand every check below a viewport wide enough to pass on markup that
  # does not fit 320px at all.
  def visit_narrow(path, width: NARROW_VIEWPORT_WIDTH)
    visit path
    wait_until_loaded
    measured = page.evaluate_script("window.innerWidth")
    return if measured == width

    Kernel.raise(
      "Expected a #{width}px viewport, measured #{measured}px. The DevTools " \
      "metrics override did not survive the navigation, so nothing below is " \
      "a narrow-viewport result."
    )
  end

  # Every theme ThemeHelper allows, read from the Ruby allowlist rather
  # than listed again here: a theme added there must be covered here too, and
  # a hand-kept third copy of that list would silently stop at six.
  def shipped_theme_ids = ThemeHelper::VALID_THEME_IDS

  # Switches the theme the way the application itself does — the signed cookie
  # Users::PreferencesController writes — rather than by setting data-theme on
  # <html> from the spec. A spec that paints the attribute on itself proves
  # the CSS reacts to an attribute; this proves the SERVER puts the attribute
  # there, which is what a real operator's theme change does.
  #
  # Takes effect on the next full page load, so callers visit afterwards.
  def choose_theme!(theme_id)
    result = browser_json_request("PATCH", "/users/preferences", {preferences: {theme_id: theme_id}})
    status = result.fetch("status")
    Kernel.raise("Theme PATCH answered #{status}: #{result["body"].inspect}") if status >= 400
  end

  # What <html> is actually carrying, so a caller can prove the theme it asked
  # for is the theme that rendered.
  def rendered_theme_id = page.evaluate_script("document.documentElement.dataset.theme")

  # How far the page can be scrolled sideways, against how much room it has.
  # documentElement.clientWidth is the viewport MINUS the vertical scrollbar,
  # which is the width content actually has to fit into.
  #
  # @return [Array(Integer, Integer)] [widest laid-out extent, room available]
  def page_horizontal_extent
    page.evaluate_script(<<~JS)
      (() => {
        const root = document.documentElement;
        return [
          Math.max(root.scrollWidth, document.body ? document.body.scrollWidth : 0),
          root.clientWidth,
        ];
      })()
    JS
  end

  def expect_no_horizontal_page_scroll!(context)
    extent, room = page_horizontal_extent
    expect(extent).to be <= (room + OVERFLOW_TOLERANCE_PX),
      "#{context}: the page scrolls sideways — laid out #{extent}px wide in #{room}px of " \
      "room. Widest elements reaching past the edge:\n  #{overflowing_elements.join("\n  ")}"
  end

  # The elements whose own box reaches past the right edge of the viewport,
  # innermost first, so a failure names the thing to fix rather than only the
  # total.
  #
  # Two whole families are dropped, and both would otherwise bury the one
  # element that is really too wide. Anything under an ancestor that handles
  # its own overflow cannot move the page at all — a wide table inside its
  # own scrolling container is where it is SUPPOSED to be, and content under a
  # hidden overflow is cut off there rather than pushing anything. And an
  # ancestor is over-wide only because of what is inside it, so listing the
  # whole chain up to <body> says nothing new.
  #
  # Also walks text nodes, not just elements — reported by their parent.
  # @lat: [[tab-strips-at-narrow-viewports#Tab strips at a narrow viewport#Text-node overflow diagnostics]]
  def overflowing_elements(limit: 6)
    page.evaluate_script(<<~JS)
      (() => {
        const room = document.documentElement.clientWidth;
        const scrolls = (el) => {
          const x = window.getComputedStyle(el).overflowX;
          return x === "auto" || x === "scroll" || x === "hidden";
        };
        const inScroller = (el) => {
          for (let node = el.parentElement; node && node !== document.documentElement; node = node.parentElement) {
            if (scrolls(node)) return true;
          }
          return false;
        };
        const elementsOver = Array.from(document.querySelectorAll("body *")).filter(
          (el) => el.getBoundingClientRect().right > room + #{OVERFLOW_TOLERANCE_PX} && !inScroller(el)
        );

        const textOverParents = new Set();
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        let textNode;
        while ((textNode = walker.nextNode())) {
          if (!(textNode.textContent || "").trim()) continue;
          const parent = textNode.parentElement;
          if (!parent || scrolls(parent) || inScroller(parent)) continue;
          const range = document.createRange();
          range.selectNodeContents(textNode);
          if (range.getBoundingClientRect().right > room + #{OVERFLOW_TOLERANCE_PX}) textOverParents.add(parent);
        }

        const over = elementsOver.concat(Array.from(textOverParents).filter((p) => !elementsOver.includes(p)));
        const innermost = over.filter((el) => !over.some((other) => other !== el && el.contains(other)));
        return innermost
          .sort((a, b) => b.getBoundingClientRect().right - a.getBoundingClientRect().right)
          .slice(0, #{limit})
          .map((el) => {
            const rect = el.getBoundingClientRect();
            const testid = el.getAttribute("data-testid");
            return [
              el.tagName.toLowerCase(),
              testid ? `[data-testid=${testid}]` : "",
              `.${(el.className || "").toString().split(/\\s+/).filter(Boolean).slice(0, 6).join(".")}`,
              ` left=${Math.round(rect.left)} right=${Math.round(rect.right)}`,
              ` text=${JSON.stringify((el.textContent || "").trim().slice(0, 40))}`,
            ].join("");
          });
      })()
    JS
  end

  # Cells whose own content is cut off inside them.
  #
  # A cell in a table that scrolls sideways in its own container is NOT
  # clipped: the cell box grows to fit its content and the CONTAINER scrolls,
  # so the cell's scrollWidth and clientWidth stay equal. A cell only reports
  # a difference when something holds its box narrower than its content and
  # hides the rest — which is text an operator can never reach.
  #
  # @return [Array<String>, nil] nil when the table never rendered
  def clipped_cells(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const root = document.querySelector(#{selector.to_json});
        if (!root) return null;
        return Array.from(root.querySelectorAll("th, td"))
          .filter((cell) => cell.scrollWidth - cell.clientWidth > #{OVERFLOW_TOLERANCE_PX})
          .map((cell) => (cell.textContent || "").slice(0, 60));
      })()
    JS
  end

  # Elements whose content is cut off inside them, for markup that is not a
  # table — the evidence row labels on the claimed-affiliation card.
  #
  # @return [Array<String>, nil] nil when nothing matched the selector
  def clipped_elements(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const nodes = Array.from(document.querySelectorAll(#{selector.to_json}));
        if (nodes.length === 0) return null;
        return nodes
          .filter((node) => node.scrollWidth - node.clientWidth > #{OVERFLOW_TOLERANCE_PX})
          .map((node) => (node.textContent || "").slice(0, 60));
      })()
    JS
  end

  # How many lines tall one element really rendered, and whether anything
  # between it and the document root turned text selection off.
  #
  # line-height computes to a pixel value on every element these specs read;
  # the 1.5 fallback covers a theme that ever leaves it at "normal" rather
  # than dividing by NaN and reporting Infinity lines.
  #
  # @return [Hash, nil] nil when the element never rendered
  def text_block_metrics(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector(#{selector.to_json});
        if (!el) return null;
        const style = window.getComputedStyle(el);
        const parsed = parseFloat(style.lineHeight);
        const lineHeight = Number.isFinite(parsed) ? parsed : parseFloat(style.fontSize) * 1.5;
        let selectionOff = false;
        for (let node = el; node && node !== document.documentElement; node = node.parentElement) {
          const s = window.getComputedStyle(node);
          if (s.userSelect === "none" || s.webkitUserSelect === "none") { selectionOff = true; break; }
        }
        return {
          height: el.getBoundingClientRect().height,
          line_height: lineHeight,
          lines: el.getBoundingClientRect().height / lineHeight,
          selection_off: selectionOff,
          text_length: (el.textContent || "").length,
        };
      })()
    JS
  end

  # @lat: [[browser-assertions#Browser assertions]]
  # @return [String, nil] nil when the subtree never rendered
  def rendered_text_within(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector(#{selector.to_json});
        return el ? (el.textContent || "") : null;
      })()
    JS
  end

  # Whether the server really put each of these strings in the page it built
  # for `path`. Lets a spec prove a string reached the browser before
  # asserting that no surface printed it — without which "the report never
  # showed it" would pass just as well on a page that was never sent it.
  #
  # Asks the server again rather than reading the props off the mounted DOM:
  # Inertia's client empties the data-page attribute as soon as it has read
  # it (measured 2026-08-16 — 3 characters left on a page carrying more than
  # 40,000), so the props a page was built from cannot be recovered from the
  # page itself.
  #
  # The search happens in the browser and only the answers come back, so a
  # page carrying tens of thousands of characters costs nothing on the wire.
  #
  # @return [Hash{String => Boolean | Integer}] one entry per string, plus
  #   "html_length" so an empty or refused response cannot read as an absence
  def served_page_carries(path, *needles)
    page.driver.browser.execute_async_script(<<~JS, path, needles)
      const done = arguments[arguments.length - 1];
      fetch(arguments[0], { credentials: "same-origin", headers: { Accept: "text/html" } })
        .then((response) => response.text())
        .then((html) => {
          const out = { html_length: html.length };
          arguments[1].forEach((needle) => { out[needle] = html.includes(needle); });
          done(out);
        })
        .catch((error) => done({ html_length: -1, error: String(error) }));
    JS
  end

  # Sets a React-controlled input the way a paste does: one value change and
  # one input event, rather than 40,000 keystrokes through the WebDriver wire.
  # Typing a 40,000-character name character by character takes minutes and
  # tests the driver, not the layout.
  def paste_into(selector, value)
    page.execute_script(<<~JS, value)
      const el = document.querySelector(#{selector.to_json});
      if (!el) throw new Error("nothing matched #{selector}");
      const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value").set;
      setter.call(el, arguments[0]);
      el.dispatchEvent(new Event("input", { bubbles: true }));
    JS
  end
end

RSpec.configure { |config| config.include NarrowViewportHelpers, type: :system }
