# typed: true

# DO NOT EDIT MANUALLY
# This is an autogenerated file for types exported from the `shortener` gem.
# Please instead update this file by running `bin/tapioca gem shortener`.


# source://shortener//lib/shortener.rb#3
module Shortener
  # source://shortener//lib/shortener.rb#45
  def auto_clean_url; end

  # source://shortener//lib/shortener.rb#45
  def auto_clean_url=(val); end

  # source://shortener//lib/shortener.rb#25
  def charset; end

  # source://shortener//lib/shortener.rb#25
  def charset=(val); end

  # source://shortener//lib/shortener.rb#29
  def default_redirect; end

  # source://shortener//lib/shortener.rb#29
  def default_redirect=(val); end

  # source://shortener//lib/shortener.rb#33
  def forbidden_keys; end

  # source://shortener//lib/shortener.rb#33
  def forbidden_keys=(val); end

  # source://shortener//lib/shortener.rb#37
  def ignore_robots; end

  # source://shortener//lib/shortener.rb#37
  def ignore_robots=(val); end

  # source://shortener//lib/shortener.rb#41
  def persist_retries; end

  # source://shortener//lib/shortener.rb#41
  def persist_retries=(val); end

  # source://shortener//lib/shortener.rb#14
  def subdomain; end

  # source://shortener//lib/shortener.rb#14
  def subdomain=(val); end

  # source://shortener//lib/shortener.rb#18
  def unique_key_length; end

  # source://shortener//lib/shortener.rb#18
  def unique_key_length=(val); end

  class << self
    # source://shortener//lib/shortener.rb#45
    def auto_clean_url; end

    # source://shortener//lib/shortener.rb#45
    def auto_clean_url=(val); end

    # source://shortener//lib/shortener.rb#25
    def charset; end

    # source://shortener//lib/shortener.rb#25
    def charset=(val); end

    # source://shortener//lib/shortener.rb#29
    def default_redirect; end

    # source://shortener//lib/shortener.rb#29
    def default_redirect=(val); end

    # source://shortener//lib/shortener.rb#33
    def forbidden_keys; end

    # source://shortener//lib/shortener.rb#33
    def forbidden_keys=(val); end

    # source://shortener//lib/shortener.rb#37
    def ignore_robots; end

    # source://shortener//lib/shortener.rb#37
    def ignore_robots=(val); end

    # source://shortener//lib/shortener.rb#48
    def key_chars; end

    # source://shortener//lib/shortener.rb#41
    def persist_retries; end

    # source://shortener//lib/shortener.rb#41
    def persist_retries=(val); end

    # source://shortener//lib/shortener.rb#14
    def subdomain; end

    # source://shortener//lib/shortener.rb#14
    def subdomain=(val); end

    # source://shortener//lib/shortener.rb#18
    def unique_key_length; end

    # source://shortener//lib/shortener.rb#18
    def unique_key_length=(val); end
  end
end

# source://shortener//lib/shortener/active_record_extension.rb#1
module Shortener::ActiveRecordExtension
  # source://shortener//lib/shortener/active_record_extension.rb#2
  def has_shortened_urls; end
end

# source://shortener//lib/shortener.rb#8
Shortener::CHARSETS = T.let(T.unsafe(nil), Hash)

# source://shortener//lib/shortener/engine.rb#7
class Shortener::Engine < ::Rails::Engine
  class << self
    # source://activesupport/7.1.4/lib/active_support/callbacks.rb#70
    def __callbacks; end
  end
end

# source://shortener//lib/shortener/railtie.rb#4
class Shortener::Railtie < ::Rails::Railtie; end

class Shortener::Record < ::ActiveRecord::Base
  include ::Shortener::Record::GeneratedAttributeMethods
  include ::Shortener::Record::GeneratedAssociationMethods

  class << self
    # source://activemodel/7.1.4/lib/active_model/validations.rb#71
    def _validators; end

    # source://activerecord/7.1.4/lib/active_record/enum.rb#167
    def defined_enums; end
  end
end

module Shortener::Record::GeneratedAssociationMethods; end
module Shortener::Record::GeneratedAttributeMethods; end

# The Shorten URL Interceptor is a mail interceptor which shortens any URLs
# in generated emails.
#
# Usage:
#
#   class MyMailer < ActionMailer::Base
#     register_interceptor Shortener::ShortenUrlInterceptor.new
#   end
#
# source://shortener//lib/shortener/shorten_url_interceptor.rb#13
class Shortener::ShortenUrlInterceptor
  # @return [ShortenUrlInterceptor] a new instance of ShortenUrlInterceptor
  #
  # source://shortener//lib/shortener/shorten_url_interceptor.rb#23
  def initialize(opts = T.unsafe(nil)); end

  # source://shortener//lib/shortener/shorten_url_interceptor.rb#29
  def delivering_email(email); end

  protected

  # source://shortener//lib/shortener/shorten_url_interceptor.rb#41
  def shorten_url(url); end

  class << self
    # source://shortener//lib/shortener/shorten_url_interceptor.rb#54
    def infer_base_url; end
  end
end

# source://shortener//lib/shortener/shorten_url_interceptor.rb#18
Shortener::ShortenUrlInterceptor::DEFAULT_LENGTH_THRESHOLD = T.let(T.unsafe(nil), Integer)

# source://shortener//lib/shortener/shorten_url_interceptor.rb#15
Shortener::ShortenUrlInterceptor::DEFAULT_NOT_SHORTEN = T.let(T.unsafe(nil), Array)

# source://shortener//lib/shortener/shorten_url_interceptor.rb#21
Shortener::ShortenUrlInterceptor::MIME_TYPES = T.let(T.unsafe(nil), Array)

# source://shortener//lib/shortener/shorten_url_interceptor.rb#20
Shortener::ShortenUrlInterceptor::URL_REGEX = T.let(T.unsafe(nil), Regexp)

class Shortener::ShortenedUrl < ::Shortener::Record
  include ::Shortener::ShortenedUrl::GeneratedAttributeMethods
  include ::Shortener::ShortenedUrl::GeneratedAssociationMethods

  # source://activerecord/7.1.4/lib/active_record/autosave_association.rb#160
  def autosave_associated_records_for_owner(*args); end

  def custom_key; end
  def custom_key=(_arg0); end
  def increment_usage_count; end
  def to_param; end

  private

  def generate_unique_key(retries = T.unsafe(nil)); end

  class << self
    # source://activesupport/7.1.4/lib/active_support/callbacks.rb#70
    def __callbacks; end

    # source://activerecord/7.1.4/lib/active_record/reflection.rb#11
    def _reflections; end

    # source://activemodel/7.1.4/lib/active_model/validations.rb#71
    def _validators; end

    def clean_url(url); end

    # source://activerecord/7.1.4/lib/active_record/enum.rb#167
    def defined_enums; end

    def extract_token(token_str); end
    def fetch_with_token(token: T.unsafe(nil), additional_params: T.unsafe(nil), track: T.unsafe(nil)); end
    def generate(destination_url, owner: T.unsafe(nil), custom_key: T.unsafe(nil), expires_at: T.unsafe(nil), fresh: T.unsafe(nil), category: T.unsafe(nil)); end
    def generate!(destination_url, owner: T.unsafe(nil), custom_key: T.unsafe(nil), expires_at: T.unsafe(nil), fresh: T.unsafe(nil), category: T.unsafe(nil)); end
    def merge_params_to_url(url: T.unsafe(nil), params: T.unsafe(nil)); end

    # source://activerecord/7.1.4/lib/active_record/scoping/named.rb#174
    def unexpired(*args, **_arg1); end

    def unique_key_candidate; end
  end
end

module Shortener::ShortenedUrl::GeneratedAssociationMethods
  # source://activerecord/7.1.4/lib/active_record/associations/builder/association.rb#103
  def owner; end

  # source://activerecord/7.1.4/lib/active_record/associations/builder/association.rb#111
  def owner=(value); end

  # source://activerecord/7.1.4/lib/active_record/associations/builder/belongs_to.rb#145
  def owner_changed?; end

  # source://activerecord/7.1.4/lib/active_record/associations/builder/belongs_to.rb#149
  def owner_previously_changed?; end

  # source://activerecord/7.1.4/lib/active_record/associations/builder/singular_association.rb#19
  def reload_owner; end

  # source://activerecord/7.1.4/lib/active_record/associations/builder/singular_association.rb#23
  def reset_owner; end
end

module Shortener::ShortenedUrl::GeneratedAttributeMethods; end
Shortener::ShortenedUrl::REGEX_LINK_HAS_PROTOCOL = T.let(T.unsafe(nil), Regexp)

class Shortener::ShortenedUrlsController < ::ActionController::Metal
  include ::ActionController::StrongParameters
  include ::AbstractController::Logger
  include ::ActiveSupport::Benchmarkable
  include ::ActionDispatch::Routing::PolymorphicRoutes
  include ::ActionDispatch::Routing::UrlFor
  include ::AbstractController::UrlFor
  include ::ActionController::UrlFor
  include ::ActionController::Redirecting
  include ::ActionController::Instrumentation
  include ::Shortener
  extend ::AbstractController::UrlFor::ClassMethods
  extend ::ActionController::Instrumentation::ClassMethods

  # source://actionpack/7.1.4/lib/action_dispatch/routing/url_for.rb#97
  def default_url_options; end

  # source://actionpack/7.1.4/lib/action_dispatch/routing/url_for.rb#97
  def default_url_options=(_arg0); end

  # source://actionpack/7.1.4/lib/action_dispatch/routing/url_for.rb#97
  def default_url_options?; end

  # source://activesupport/7.1.4/lib/active_support/configurable.rb#115
  def logger; end

  # source://activesupport/7.1.4/lib/active_support/configurable.rb#116
  def logger=(value); end

  # source://actionpack/7.1.4/lib/action_controller/metal/redirecting.rb#15
  def raise_on_open_redirects; end

  # source://actionpack/7.1.4/lib/action_controller/metal/redirecting.rb#15
  def raise_on_open_redirects=(val); end

  def show; end

  class << self
    # source://actionpack/7.1.4/lib/action_dispatch/routing/route_set.rb#584
    def _routes; end

    # source://actionpack/7.1.4/lib/action_dispatch/routing/url_for.rb#97
    def default_url_options; end

    # source://actionpack/7.1.4/lib/action_dispatch/routing/url_for.rb#97
    def default_url_options=(value); end

    # source://actionpack/7.1.4/lib/action_dispatch/routing/url_for.rb#97
    def default_url_options?; end

    # source://activesupport/7.1.4/lib/active_support/configurable.rb#115
    def logger; end

    # source://activesupport/7.1.4/lib/active_support/configurable.rb#116
    def logger=(value); end

    # source://actionpack/7.1.4/lib/action_controller/metal.rb#262
    def middleware_stack; end

    # source://actionpack/7.1.4/lib/action_controller/metal/redirecting.rb#15
    def raise_on_open_redirects; end

    # source://actionpack/7.1.4/lib/action_controller/metal/redirecting.rb#15
    def raise_on_open_redirects=(val); end
  end
end

module Shortener::ShortenerHelper
  def short_url(url, owner: T.unsafe(nil), custom_key: T.unsafe(nil), expires_at: T.unsafe(nil), fresh: T.unsafe(nil), category: T.unsafe(nil), url_options: T.unsafe(nil)); end
end
