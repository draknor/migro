class AddToMigrationRuns < ActiveRecord::Migration
  def change
    change_table :migration_runs do |t|
      t.boolean :all_records
      t.text :record_list
    end
  end
end
