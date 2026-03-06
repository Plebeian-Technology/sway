# frozen_string_literal: true

class ScoreChannel < ApplicationCable::Channel
  def subscribed
    stream_from "scores_#{current_user.id}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
