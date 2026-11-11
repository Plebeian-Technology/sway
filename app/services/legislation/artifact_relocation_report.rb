# frozen_string_literal: true

module Legislation
  # @lat: [[legislation-artifact-relocation#Why the report keeps moved and left-behind counts apart]]
  class ArtifactRelocationReport
    attr_reader :moved
    attr_reader :left

    def initialize
      @moved = []
      @left = {}
    end

    def record_moved(relative_path)
      @moved << relative_path
    end

    def record_left(relative_path, reason)
      @left[relative_path] = reason
    end

    def moved_count
      @moved.size
    end

    def left_count
      @left.size
    end

    # @lat: [[legislation-artifact-relocation#Why the report keeps moved and left-behind counts apart]]
    def left_lines
      @left.map { |path, reason| "#{path}: #{reason}" }
    end
  end
end
