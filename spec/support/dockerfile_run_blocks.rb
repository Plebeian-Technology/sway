# frozen_string_literal: true

# Split a Dockerfile into its RUN blocks, one string per block.
module DockerfileRunBlocks
  # @lat: [[testing-the-toolchain#A comment does not end a continued RUN block]]
  def self.split(text)
    blocks = []
    current = nil #: String?

    text.each_line do |line|
      trimmed = line.rstrip
      current = +"" if current.nil? && trimmed.start_with?("RUN ")
      block = current
      next if block.nil?
      checked_block = block #: String

      checked_block << line
      next if trimmed.match?(/\A\s*#/)
      next if trimmed.end_with?("\\")

      blocks << checked_block
      current = nil
    end

    blocks << current if current
    blocks
  end
end
