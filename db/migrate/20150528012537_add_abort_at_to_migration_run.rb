class AddAbortAtToMigrationRun < ActiveRecord::Migration
  def change
    add_column :migration_runs, :abort_at, :timestamp
  end
end
