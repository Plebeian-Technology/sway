# https://sorbet.org/docs/runtime

# (1) Register call_validation_error_handler callback.
# This runs every time a method with a sig fails to type check at runtime.
T::Configuration.call_validation_error_handler = lambda do |signature, opts|
  Rails.logger.error opts[:pretty_message]

  # Default behavior is to throw an error
  # if signature.on_failure && signature.on_failure[0] == :log
  #   puts opts[:pretty_message]
  # else
  #   raise TypeError.new(opts[:pretty_message])
  # end
end
