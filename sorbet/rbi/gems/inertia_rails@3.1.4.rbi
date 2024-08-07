# typed: true

# DO NOT EDIT MANUALLY
# This is an autogenerated file for types exported from the `inertia_rails` gem.
# Please instead update this file by running `bin/tapioca gem inertia_rails`.


class ActionDispatch::DebugExceptions
  include ::InertiaDebugExceptions
end

# source://inertia_rails//lib/patches/debug_exceptions/patch-5-1.rb#10
module InertiaDebugExceptions
  # source://inertia_rails//lib/patches/debug_exceptions/patch-5-1.rb#11
  def render_for_browser_request(request, wrapper); end
end

# source://inertia_rails//lib/inertia_rails/lazy.rb#1
module InertiaRails
  # source://activesupport/7.1.3.3/lib/active_support/core_ext/module/attribute_accessors_per_thread.rb#74
  def threadsafe_html_headers; end

  # source://activesupport/7.1.3.3/lib/active_support/core_ext/module/attribute_accessors_per_thread.rb#116
  def threadsafe_html_headers=(obj); end

  # source://activesupport/7.1.3.3/lib/active_support/core_ext/module/attribute_accessors_per_thread.rb#74
  def threadsafe_shared_blocks; end

  # source://activesupport/7.1.3.3/lib/active_support/core_ext/module/attribute_accessors_per_thread.rb#116
  def threadsafe_shared_blocks=(obj); end

  # source://activesupport/7.1.3.3/lib/active_support/core_ext/module/attribute_accessors_per_thread.rb#74
  def threadsafe_shared_plain_data; end

  # source://activesupport/7.1.3.3/lib/active_support/core_ext/module/attribute_accessors_per_thread.rb#116
  def threadsafe_shared_plain_data=(obj); end

  class << self
    # @yield [Configuration]
    #
    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#10
    def configure; end

    # @return [Boolean]
    #
    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#44
    def deep_merge_shared_data?; end

    # @return [Boolean]
    #
    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#36
    def default_render?; end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#103
    def evaluated_blocks(controller, blocks); end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#40
    def html_headers; end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#57
    def html_headers=(headers); end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#24
    def layout; end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#67
    def lazy(value = T.unsafe(nil), &block); end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#61
    def reset!; end

    # "Setters"
    #
    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#49
    def share(**args); end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#53
    def share_block(block); end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#95
    def shared_blocks; end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#99
    def shared_blocks=(val); end

    # "Getters"
    #
    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#15
    def shared_data(controller); end

    # Getters and setters to provide default values for the threadsafe attributes
    #
    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#87
    def shared_plain_data; end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#91
    def shared_plain_data=(val); end

    # @return [Boolean]
    #
    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#28
    def ssr_enabled?; end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#32
    def ssr_url; end

    # source://activesupport/7.1.3.3/lib/active_support/core_ext/module/attribute_accessors_per_thread.rb#49
    def threadsafe_html_headers; end

    # source://activesupport/7.1.3.3/lib/active_support/core_ext/module/attribute_accessors_per_thread.rb#108
    def threadsafe_html_headers=(obj); end

    # source://activesupport/7.1.3.3/lib/active_support/core_ext/module/attribute_accessors_per_thread.rb#49
    def threadsafe_shared_blocks; end

    # source://activesupport/7.1.3.3/lib/active_support/core_ext/module/attribute_accessors_per_thread.rb#108
    def threadsafe_shared_blocks=(obj); end

    # source://activesupport/7.1.3.3/lib/active_support/core_ext/module/attribute_accessors_per_thread.rb#49
    def threadsafe_shared_plain_data; end

    # source://activesupport/7.1.3.3/lib/active_support/core_ext/module/attribute_accessors_per_thread.rb#108
    def threadsafe_shared_plain_data=(obj); end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#20
    def version; end
  end
end

# source://inertia_rails//lib/inertia_rails/inertia_rails.rb#73
module InertiaRails::Configuration
  # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#79
  def deep_merge_shared_data; end

  # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#79
  def deep_merge_shared_data=(val); end

  # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#78
  def default_render; end

  # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#78
  def default_render=(val); end

  # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#74
  def layout; end

  # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#74
  def layout=(val); end

  # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#76
  def ssr_enabled; end

  # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#76
  def ssr_enabled=(val); end

  # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#77
  def ssr_url; end

  # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#77
  def ssr_url=(val); end

  # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#75
  def version; end

  # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#75
  def version=(val); end

  class << self
    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#79
    def deep_merge_shared_data; end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#79
    def deep_merge_shared_data=(val); end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#78
    def default_render; end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#78
    def default_render=(val); end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#81
    def evaluated_version; end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#74
    def layout; end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#74
    def layout=(val); end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#76
    def ssr_enabled; end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#76
    def ssr_enabled=(val); end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#77
    def ssr_url; end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#77
    def ssr_url=(val); end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#75
    def version; end

    # source://inertia_rails//lib/inertia_rails/inertia_rails.rb#75
    def version=(val); end
  end
end

# source://inertia_rails//lib/inertia_rails/controller.rb#5
module InertiaRails::Controller
  extend ::ActiveSupport::Concern

  mixes_in_class_methods ::InertiaRails::Controller::ClassMethods

  # source://inertia_rails//lib/inertia_rails/controller.rb#36
  def default_render; end

  # source://inertia_rails//lib/inertia_rails/controller.rb#58
  def inertia_view_assigns; end

  # source://inertia_rails//lib/inertia_rails/controller.rb#49
  def redirect_back(fallback_location:, allow_other_host: T.unsafe(nil), **options); end

  # source://inertia_rails//lib/inertia_rails/controller.rb#44
  def redirect_to(options = T.unsafe(nil), response_options = T.unsafe(nil)); end

  private

  # source://inertia_rails//lib/inertia_rails/controller.rb#78
  def capture_inertia_errors(options); end

  # source://inertia_rails//lib/inertia_rails/controller.rb#65
  def inertia_layout; end

  # source://inertia_rails//lib/inertia_rails/controller.rb#73
  def inertia_location(url); end
end

# source://inertia_rails//lib/inertia_rails/controller.rb#20
module InertiaRails::Controller::ClassMethods
  # source://inertia_rails//lib/inertia_rails/controller.rb#21
  def inertia_share(**args, &block); end

  # source://inertia_rails//lib/inertia_rails/controller.rb#28
  def use_inertia_instance_props; end
end

# source://inertia_rails//lib/inertia_rails/engine.rb#5
class InertiaRails::Engine < ::Rails::Engine
  class << self
    # source://activesupport/7.1.3.3/lib/active_support/callbacks.rb#70
    def __callbacks; end
  end
end

# source://inertia_rails//lib/inertia_rails.rb#23
class InertiaRails::Error < ::StandardError; end

# source://inertia_rails//lib/inertia_rails/helper.rb#3
module InertiaRails::Helper
  # source://inertia_rails//lib/inertia_rails/helper.rb#4
  def inertia_headers; end
end

# source://inertia_rails//lib/inertia_rails/lazy.rb#2
class InertiaRails::Lazy
  # @return [Lazy] a new instance of Lazy
  #
  # source://inertia_rails//lib/inertia_rails/lazy.rb#3
  def initialize(value = T.unsafe(nil), &block); end

  # source://inertia_rails//lib/inertia_rails/lazy.rb#8
  def call; end

  # source://inertia_rails//lib/inertia_rails/lazy.rb#12
  def to_proc; end
end

# source://inertia_rails//lib/inertia_rails/middleware.rb#2
class InertiaRails::Middleware
  # @return [Middleware] a new instance of Middleware
  #
  # source://inertia_rails//lib/inertia_rails/middleware.rb#3
  def initialize(app); end

  # source://inertia_rails//lib/inertia_rails/middleware.rb#7
  def call(env); end
end

# source://inertia_rails//lib/inertia_rails/middleware.rb#14
class InertiaRails::Middleware::InertiaRailsRequest
  # @return [InertiaRailsRequest] a new instance of InertiaRailsRequest
  #
  # source://inertia_rails//lib/inertia_rails/middleware.rb#15
  def initialize(app, env); end

  # source://inertia_rails//lib/inertia_rails/middleware.rb#20
  def response; end

  private

  # source://inertia_rails//lib/inertia_rails/middleware.rb#94
  def copy_xsrf_to_csrf!; end

  # source://inertia_rails//lib/inertia_rails/middleware.rb#89
  def force_refresh(request); end

  # @return [Boolean]
  #
  # source://inertia_rails//lib/inertia_rails/middleware.rb#59
  def get?; end

  # @return [Boolean]
  #
  # source://inertia_rails//lib/inertia_rails/middleware.rb#51
  def inertia_non_post_redirect?(status); end

  # @return [Boolean]
  #
  # source://inertia_rails//lib/inertia_rails/middleware.rb#71
  def inertia_request?; end

  # source://inertia_rails//lib/inertia_rails/middleware.rb#67
  def inertia_version; end

  # @return [Boolean]
  #
  # source://inertia_rails//lib/inertia_rails/middleware.rb#35
  def keep_inertia_errors?(status); end

  # @return [Boolean]
  #
  # source://inertia_rails//lib/inertia_rails/middleware.rb#47
  def non_get_redirectable_method?; end

  # @return [Boolean]
  #
  # source://inertia_rails//lib/inertia_rails/middleware.rb#43
  def redirect_status?(status); end

  # source://inertia_rails//lib/inertia_rails/middleware.rb#63
  def request_method; end

  # source://inertia_rails//lib/inertia_rails/middleware.rb#85
  def saved_version; end

  # source://inertia_rails//lib/inertia_rails/middleware.rb#79
  def sent_version; end

  # @return [Boolean]
  #
  # source://inertia_rails//lib/inertia_rails/middleware.rb#55
  def stale_inertia_get?; end

  # @return [Boolean]
  #
  # source://inertia_rails//lib/inertia_rails/middleware.rb#39
  def stale_inertia_request?; end

  # @return [Boolean]
  #
  # source://inertia_rails//lib/inertia_rails/middleware.rb#75
  def version_stale?; end
end

# source://inertia_rails//lib/inertia_rails/renderer.rb#6
class InertiaRails::Renderer
  # @return [Renderer] a new instance of Renderer
  #
  # source://inertia_rails//lib/inertia_rails/renderer.rb#9
  def initialize(component, controller, request, response, render_method, props: T.unsafe(nil), view_data: T.unsafe(nil), deep_merge: T.unsafe(nil)); end

  # Returns the value of attribute component.
  #
  # source://inertia_rails//lib/inertia_rails/renderer.rb#7
  def component; end

  # source://inertia_rails//lib/inertia_rails/renderer.rb#20
  def render; end

  # Returns the value of attribute view_data.
  #
  # source://inertia_rails//lib/inertia_rails/renderer.rb#7
  def view_data; end

  private

  # source://inertia_rails//lib/inertia_rails/renderer.rb#45
  def computed_props; end

  # source://inertia_rails//lib/inertia_rails/renderer.rb#76
  def deep_transform_values(hash, proc); end

  # source://inertia_rails//lib/inertia_rails/renderer.rb#41
  def layout; end

  # source://inertia_rails//lib/inertia_rails/renderer.rb#67
  def page; end

  # source://inertia_rails//lib/inertia_rails/renderer.rb#82
  def partial_keys; end

  # source://inertia_rails//lib/inertia_rails/renderer.rb#90
  def prop_merge_method; end

  # source://inertia_rails//lib/inertia_rails/renderer.rb#33
  def render_ssr; end

  # @return [Boolean]
  #
  # source://inertia_rails//lib/inertia_rails/renderer.rb#86
  def rendering_partial_component?; end
end
