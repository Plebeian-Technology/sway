class AddStatusAndActiveAndAudioBucketPathAndAudioByLineToBill < ActiveRecord::Migration[7.1]
  def change
    add_column :bills, :status, :string
    add_column :bills, :active, :boolean
    add_column :bills, :audio_bucket_path, :string
    add_column :bills, :audio_by_line, :string
  end
end
