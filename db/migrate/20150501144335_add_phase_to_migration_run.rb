class AddPhaseToMigrationRun < ActiveRecord::Migration
  def change
    add_column :migration_runs, :phase, :integer
  end
end
