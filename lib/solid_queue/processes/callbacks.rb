# frozen_string_literal: true

module SolidQueue::Processes
  module Callbacks
    extend ActiveSupport::Concern

    included do
      extend ActiveModel::Callbacks
      define_model_callbacks :boot, :shutdown
      # define_callbacks :boot, :shutdown
    end

    private
      def boot
      end

      def shutdown
      end
  end
end
