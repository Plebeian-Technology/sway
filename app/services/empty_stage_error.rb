# frozen_string_literal: true

# @lat: [[legislation-pipeline#Runs, resume and restart#A stage that produced nothing is not a success]]
class EmptyStageError < StageError; end
