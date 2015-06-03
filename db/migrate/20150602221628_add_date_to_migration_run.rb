class AddDateToMigrationRun < ActiveRecord::Migration
  def change
    add_column :migration_runs, :from_date, :date
    add_column :migration_runs, :through_date, :date
  end
end
