class AddSourceBeforeToMigrationLog < ActiveRecord::Migration
  def change
    add_column :migration_logs, :source_before, :text
  end
end
