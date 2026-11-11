# frozen_string_literal: true

module RuboCop
  module Cop
    module Sway
      # @lat: [[inertia-matcher-required-cop-rationale#Why this rarely fires falsely]]
      class InertiaMatcherRequired < RuboCop::Cop::Base
        MSG = "Inertia prop assertions must pin the component with " \
          "`render_component(...)` so a wrong-component regression fails here. " \
          "If this example asserts cross-component shared data, exclude the " \
          "file in .rubocop/rspec.yml."

        GROUP_METHODS = %i[describe context feature].freeze

        def_node_search :reads_inertia_props?, <<~PATTERN
          (send (send nil? :inertia) :props ...)
        PATTERN

        # @lat: [[inertia-matcher-required-cop-rationale#Why matcher names are written literally in the node pattern]]
        def_node_search :asserts_inertia_props?, <<~PATTERN
          (send _ {:to :to_not :not_to} (send nil? {:have_props :have_exact_props :have_deferred_props} ...))
        PATTERN

        def_node_search :pins_component?, <<~PATTERN
          (send nil? :render_component ...)
        PATTERN

        # @lat: [[inertia-matcher-required-cop-rationale#Why flagging works per top-level group]]
        def on_block(node)
          return unless top_level_group?(node)

          body = node.body
          return if body.nil?
          return unless reads_inertia_props?(body) || asserts_inertia_props?(body)
          return if pins_component?(body)

          add_offense(node.send_node)
        end
        alias_method :on_numblock, :on_block

        private

        def group_block?(node)
          node.block_type? && GROUP_METHODS.include?(node.method_name)
        end

        # @lat: [[inertia-matcher-required-cop-rationale#Known limitation: shared examples are not inspected]]
        def top_level_group?(node)
          return false unless node.block_type?
          return false unless GROUP_METHODS.include?(node.send_node.method_name)

          node.each_ancestor(:block, :numblock).none? { |ancestor| group_block?(ancestor) }
        end
      end
    end
  end
end
