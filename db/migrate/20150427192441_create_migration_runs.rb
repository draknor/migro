class CreateMigrationRuns < ActiveRecord::Migration
  def change
    create_table :migration_runs do |t|
      t.timestamp :started_at
      t.timestamp :ended_at
      t.integer :source_system_id
      t.integer :destination_system_id
      t.integer :user_id
      t.string :entity_type
      t.integer :records_migrated
      t.integer :max_records
      t.integer :status, default: 0
      t.string :name

      t.timestamps null: false
    end
  end
end
