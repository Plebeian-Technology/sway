# frozen_string_literal: true

# A-WR-05: gives the stage-3 verdict cache an invalidation path.
#
# 20260725000001 stored `model` on every row and nothing ever read it back, so
# a verdict was permanent: change the classifier model, fix the classification
# prompt, and every attachment already labelled "not_testimony" stayed
# excluded for the life of the database. The design accepts that Haiku will
# sometimes be wrong — that is why stage 3 exists — so "wrong forever" was the
# one outcome it could not afford.
#
# `prompt_version` is the second half of the read predicate (the first is the
# `model` column that already exists). Existing rows get NULL, which matches no
# current prompt version, so they are re-classified once on the next run and
# then re-cached — which is exactly the intended behaviour for rows produced by
# a prompt nobody can reconstruct.
#
# Nullable and unindexed on purpose: it is read as part of an
# attachment_id-keyed lookup that the unique index already resolves to at most
# one row, so a second index would cost writes and buy nothing.
class AddPromptVersionToTestimonyClassifications < ActiveRecord::Migration[8.1]
  def change
    add_column :testimony_attachment_classifications, :prompt_version, :string
  end
end
