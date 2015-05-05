class CreateMigrationLogs < ActiveRecord::Migration
  def change
    create_table :migration_logs do |t|
      t.integer :log_type
      t.integer :migration_run_id
      t.string :message
      t.string :source_id
      t.string :target_id
      t.text :target_before
      t.text :target_after

      t.timestamps null: false
    end
  end
end
