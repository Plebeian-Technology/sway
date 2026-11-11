# frozen_string_literal: true

class PipelineRunChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user&.is_admin?
    stream_for params[:run_id]
  end

  def unsubscribed
  end
end
