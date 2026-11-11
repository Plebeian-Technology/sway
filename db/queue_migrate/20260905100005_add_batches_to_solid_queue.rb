# frozen_string_literal: true

# @lat: [[auxiliary-databases#Why the queue database names a migrations path]]
class AddBatchesToSolidQueue < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:solid_queue_jobs)

    unless column_exists?(:solid_queue_jobs, :batch_id)
      add_column :solid_queue_jobs, :batch_id, :bigint
      add_index :solid_queue_jobs, :batch_id
    end

    unless table_exists?(:solid_queue_batches)
      create_table :solid_queue_batches do |t|
        t.string :active_job_batch_id
        t.string :description
        t.text :on_finish
        t.text :on_success
        t.text :on_failure
        t.text :metadata
        t.integer :total_jobs, default: 0, null: false
        t.integer :completed_jobs, default: 0, null: false
        t.integer :failed_jobs, default: 0, null: false
        t.datetime :enqueued_at
        t.datetime :finished_at
        t.datetime :failed_at
        t.datetime :created_at, null: false
        t.datetime :updated_at, null: false

        t.index :active_job_batch_id, unique: true
        t.index :finished_at
      end
    end

    return if table_exists?(:solid_queue_batch_executions)

    create_table :solid_queue_batch_executions do |t|
      t.bigint :job_id, null: false
      t.bigint :batch_id, null: false
      t.datetime :created_at, null: false

      t.index :job_id, unique: true
      t.index :batch_id
      t.foreign_key :solid_queue_batches, column: :batch_id, on_delete: :cascade
      t.foreign_key :solid_queue_jobs, column: :job_id, on_delete: :cascade
    end
  end

  def down
    drop_table :solid_queue_batch_executions, if_exists: true
    drop_table :solid_queue_batches, if_exists: true

    return unless column_exists?(:solid_queue_jobs, :batch_id)

    remove_index :solid_queue_jobs, :batch_id, if_exists: true
    remove_column :solid_queue_jobs, :batch_id
  end
end
