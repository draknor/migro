class AddStartPageToMigrationRun < ActiveRecord::Migration
  def change
    add_column :migration_runs, :start_page, :integer
  end
end
